// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against the "per-tab/per-pane provider scope leak" bug
// class, scanning the scope-owning shared packages `crux_workspace` and
// `crux_projects` with a resolved AST.
//
// WHY THIS LIVES HERE, AND WHAT IT LOCKS
// crux-shared gives every open tab its own child `ProviderContainer` and every
// pane its own child of that. The container is keyed by the scope-key sentinel
// providers in `crux_workspace/lib/src/id_providers.dart` — `tabIdProvider`
// and `paneIdProvider` — which each per-tab / per-pane container overrides with
// its own id and which *throw* when read at the root scope. Products hang their
// own per-tab state off those keys; the shared packages must not.
//
// An audit verified crux-shared's scoping SOUND: no shared-package
// provider reads scope-keyed state, the sentinel leaves fail loudly at root
// rather than serving shared state, and `PaneHost` takes its provider by
// constructor rather than reaching for a global. This guard's job is to lock
// that property in so a future edit cannot quietly reopen it. It is expected to
// find ZERO leaks; its value is the machine-checked invariant, not a fix.
//
// THE BUG CLASS (why it would matter if it returned)
// A provider whose body reads a scope-key sentinel (directly or transitively)
// but which is not itself instantiated inside a per-tab / per-pane container is
// hoisted to the ROOT container, where the sentinel throws — or, for a
// product's own scope-keyed state hung off it, reads the empty root-scope
// version. For shared infrastructure the deeper defect is architectural: a
// shared package that couples to a per-tab key has smuggled a product's
// tab/pane model into the substrate.
//
// WHY UNIT TESTS DON'T CATCH IT
// Every provider unit test builds a single FLAT `ProviderContainer` with the
// scope-keyed dependency overridden inline. With no parent container there is
// no fallthrough, so the scoping defect is structurally invisible. This is why
// the guard is static and source-driven.
//
// ANALYSIS MODEL
// The scan resolves every library under the source roots with
// `package:analyzer` and works on elements, not on text. Four steps:
//
//  1. PROVIDER REGISTRY. A top-level variable is a provider when its static
//     type, or any of its supertypes, is declared in a riverpod library. That
//     is a type test, so it covers hand-written providers, generated providers
//     and families alike, and it does not depend on the variable being named
//     `…Provider`. Each provider is keyed by `<library uri>::<name>`, which is
//     stable across the two analysis contexts a cross-package scan needs.
//
//  2. BODIES. A provider's build logic is whatever its initializer supplies:
//     an inline closure (scanned in place), a referenced top-level function, or
//     a `Notifier` class named by a `Foo.new` tear-off.
//
//  3. READS. A read is a `watch`/`read`/`listen`/`refresh`/`invalidate`
//     invocation whose *receiver's static type* is riverpod's `Ref` or
//     `WidgetRef`. Testing the receiver's type rather than the token `ref` is
//     what makes a read through a stored `Ref` field visible. The provider
//     being read is then taken from every element referenced in the argument
//     expression, so a family applied to a run-time argument, a conditional and
//     a `.select(…)` chain all resolve to the underlying symbol.
//
//     Reads are collected over the call graph, not just the provider's own
//     body: every invocation resolving to a declaration inside the source roots
//     is followed, memoized per declaration and guarded against cycles. This is
//     what reaches a read hidden in a helper object, an extension method on
//     `Ref`, or a private method of a notifier. The reported reach names the
//     helper chain it travelled.
//
//     The analysis is deliberately a may-analysis: a run-time selection between
//     two providers contributes both. Over-approximating costs an occasional
//     allowlist entry; under-approximating reinstates the blind spot the guard
//     exists to close.
//
//  4. TAINT CLOSURE. A provider is tainted if it reads a scope-key seed or any
//     other tainted provider, so a consumer that reads only an intermediate
//     inherits the leak without naming a seed in its own body. Every tainted
//     provider that is not itself a seed is a violation.
//
// The shapes this model resolves are pinned by `scope_leak_shapes/shapes.dart`
// and asserted below, so a future simplification of the analysis cannot quietly
// reopen a closed blind spot.
//
// COST AND HOW TO RUN
// Resolving the tree costs a few seconds per source root, which is why this
// file carries a raised timeout. It runs in the default `flutter test` suite.

@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'scope_leak_scanner.dart';

/// Providers that read scope-keyed state but are *intentionally* root-scoped,
/// with the reason they are exempt. Kept empty: crux-shared's scoping is sound
/// and this guard exists to keep it that way, so a real leak is fixed
/// rather than listed.
const Map<String, String> _allowlist = <String, String>{};

/// The library declaring the scope-key sentinel providers, as a path suffix
/// (only `crux_workspace` owns it). Every provider declared here is a seed;
/// every provider elsewhere that reaches one is a leak.
const String _scopeKeyLibrary = 'lib/src/id_providers.dart';

void main() {
  late final ScopeGraph graph;

  setUpAll(() async {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason:
          'run this test from the crux_workspace package root (flutter '
          'test)',
    );
    graph = await ScopeGraph.resolve(_sourceRoots());
  });

  test('resolution covered the tree', () {
    expect(
      graph.unresolved,
      isEmpty,
      reason:
          'these libraries did not resolve, so any provider they declare is '
          'invisible to the scan — run `melos bootstrap`',
    );
    expect(
      graph.providers.length,
      greaterThan(4),
      reason:
          'sanity: far fewer providers than expected were registered, which '
          'means the registry, not the tree, changed',
    );
  });

  test(
    'no shared-package provider reads scope-keyed state (directly or '
    'transitively) without being a scope-key seed',
    () {
      final seeds = _scopeKeySeeds(graph);
      expect(
        seeds.map(graph.nameOf),
        containsAll(<String>['tabIdProvider', 'paneIdProvider']),
        reason:
            'the scope-key sentinel providers were not found — did '
            '$_scopeKeyLibrary move or change shape?',
      );

      final reach = taintClosure(graph.reads(), seeds);

      final violations = <_Leak>[];
      for (final entry in reach.entries) {
        if (seeds.contains(entry.key)) continue;
        final provider = graph.providers[entry.key]!;
        if (_allowlist.containsKey(provider.name)) continue;
        violations.add(
          _Leak(
            provider.name,
            provider.path,
            <String>[for (final k in entry.value) graph.nameOf(k)],
            graph.viaFor(entry.value),
          ),
        );
      }

      if (violations.isNotEmpty) {
        violations.sort((a, b) => a.symbol.compareTo(b.symbol));
        final buf = StringBuffer()
          ..writeln('Scope-key provider leak(s) detected in shared packages:')
          ..writeln();
        for (final v in violations) {
          buf
            ..writeln('  ${v.symbol}')
            ..writeln('    in ${v.path}')
            ..writeln('    scope-key reach: ${v.reach.join(' -> ')}');
          if (v.via.isNotEmpty) {
            buf.writeln('    read reached through: ${v.via.join(' > ')}');
          }
          buf.writeln();
        }
        buf
          ..writeln(
            'Each provider above reads a per-tab / per-pane scope key '
            '(directly or transitively). A shared-package provider must not: '
            'it is hoisted to the ROOT container, where the sentinel throws, '
            'and it couples the substrate to a product-owned scope model.',
          )
          ..writeln(
            'Fix by moving the read into the product, or by not reading the '
            'scope key from a shared provider at all.',
          )
          ..writeln(
            'If a shared provider is intentionally root-scoped despite naming '
            'a scope key, add it to `_allowlist` with a documented reason.',
          );
        fail(buf.toString());
      }
    },
  );

  test('scope-leak allowlist entries still exist as providers', () {
    final known = graph.providers.values.map((i) => i.name).toSet();
    for (final symbol in _allowlist.keys) {
      expect(
        known,
        contains(symbol),
        reason:
            'allowlisted provider `$symbol` no longer exists — remove or '
            'update its entry in _allowlist.',
      );
    }
  });

  test('taint closure propagates through intermediate providers', () {
    // Guards the guard: a two-hop chain (leaf -> middle -> seed) must flag
    // BOTH hops. A direct-reads-only scan flags `middle` and lets `leaf`
    // through — the escape path a transitive leak would take.
    final reads = <String, List<ProviderRead>>{
      'middle': <ProviderRead>[ProviderRead('seed', const <String>[])],
      'leaf': <ProviderRead>[ProviderRead('middle', const <String>[])],
      'unrelated': <ProviderRead>[ProviderRead('root', const <String>[])],
      // A self-read must not taint (a notifier reading its own provider).
      'self': <ProviderRead>[ProviderRead('self', const <String>[])],
    };

    final reach = taintClosure(reads, <String>{'seed'});

    expect(reach.keys, containsAll(<String>['middle', 'leaf']));
    expect(reach.keys, isNot(contains('unrelated')));
    expect(reach.keys, isNot(contains('self')));
    expect(
      reach['leaf'],
      <String>['leaf', 'middle', 'seed'],
      reason: 'the reported reach must name every hop down to the seed',
    );
  });

  group('reach analysis resolves indirect reads', () {
    late final ScopeGraph shapes;
    late final Map<String, List<ProviderRead>> reads;

    setUpAll(() async {
      shapes = await ScopeGraph.resolve(<Directory>[
        Directory('test/static/scope_leak_shapes'),
      ]);
      expect(shapes.unresolved, isEmpty);
      reads = shapes.reads();
    });

    Set<String> readsOf(String provider) {
      final key = shapes.keyOf(provider);
      expect(key, isNotNull, reason: '`$provider` was not registered');
      return <String>{
        for (final r in reads[key] ?? const <ProviderRead>[])
          shapes.nameOf(r.target),
      };
    }

    // A `Ref` captured on a field is still a `Ref`; matching on the receiver's
    // type rather than the identifier `ref` is what makes this visible.
    test('through a Ref stored on a field', () {
      expect(readsOf('storedRefProvider'), contains('seedProvider'));
    });

    test('through a helper object taking a Ref', () {
      expect(readsOf('helperObjectProvider'), contains('seedProvider'));
    });

    test('through an extension method on Ref', () {
      expect(readsOf('extensionProvider'), contains('seedProvider'));
    });

    // May-analysis: a run-time choice between providers contributes every
    // candidate, so the scope-keyed one cannot hide behind the branch.
    test('through a run-time provider selection', () {
      expect(readsOf('runtimeSelectedProvider'), contains('seedProvider'));
    });

    test('through a family applied to a run-time argument', () {
      expect(readsOf('familyArgProvider'), contains('familyProvider'));
    });

    test('and reports the helper chain it travelled', () {
      final key = shapes.keyOf('helperObjectProvider')!;
      final read = reads[key]!.firstWhere(
        (r) => shapes.nameOf(r.target) == 'seedProvider',
      );
      expect(read.via, isNotEmpty);
    });

    test('without over-reporting a provider that reads only root state', () {
      expect(readsOf('decoyProvider'), isNot(contains('seedProvider')));
    });

    test('and the closure reaches a two-hop chain', () {
      final seed = shapes.keyOf('seedProvider')!;
      final reach = taintClosure(reads, <String>{seed});
      expect(reach.keys, contains(shapes.keyOf('leafProvider')));
      expect(reach.keys, isNot(contains(shapes.keyOf('decoyProvider'))));
    });
  });
}

/// Source roots contributing provider definitions to the read-graph: this
/// package's `lib/` plus the sibling `crux_projects/lib/`, which owns the
/// per-project scoping helper. A taint chain crossing the package boundary
/// still resolves because both are analyzed in one context collection.
List<Directory> _sourceRoots() {
  final roots = <Directory>[Directory('lib')];
  final projects = Directory('../crux_projects/lib');
  if (projects.existsSync()) roots.add(projects);
  return roots;
}

/// The scope-key seed set: every provider declared in the sentinel library.
/// A provider is a seed by *where it is declared*, so adding a third scope key
/// beside `tabIdProvider` / `paneIdProvider` extends the guard automatically.
Set<String> _scopeKeySeeds(ScopeGraph graph) {
  final seeds = <String>{
    for (final info in graph.providers.values)
      if (p.posix.joinAll(p.split(info.path)).endsWith(_scopeKeyLibrary))
        info.key,
  };
  expect(
    seeds,
    isNotEmpty,
    reason: 'no scope-key seed providers found in $_scopeKeyLibrary',
  );
  return seeds;
}

class _Leak {
  _Leak(this.symbol, this.path, this.reach, this.via);
  final String symbol;
  final String path;

  /// The reach chain from this provider down to the scope-key seed it depends
  /// on.
  final List<String> reach;

  /// The helper declarations the first hop's read was found behind, if any.
  final List<String> via;
}
