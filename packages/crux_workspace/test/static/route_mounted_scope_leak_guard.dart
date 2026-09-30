// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The ROUTE-MOUNTED per-tab scope-leak rule, as a reusable library.
//
// WHY THIS IS A LIBRARY AND NOT JUST A TEST
// The rule has to run in nine places: here, and in each of the eight product
// trees (four apps × open-core/Pro). The sibling `per_tab_provider_scope_leak`
// guard was rolled out by copy-paste, and the result is eight divergent
// ~700–950-line scanners that no improvement ever propagates to — the guard's
// own first sweep found six real bugs that none of those copies could see,
// because none of them has `routeMounts()`. Copying this rule eight more times
// would repeat that mistake at exactly the moment it was diagnosed.
//
// So the rule lives here, once, next to the scanner it depends on. A product
// adds a ~30-line `test/static/route_mounted_scope_leak_test.dart` that
// relative-imports this file across its `crux-shared/` submodule and calls
// [defineRouteMountedScopeLeakGuard] with its own source roots and per-tab
// seed list. That is the same mechanism the Pro overlays already use to share
// `scope_leak_scanner.dart` with their open-core repo, so it is a shape the
// suite already runs in CI.
//
// The rule itself, its three accepted forms of re-binding, and the seven
// documented things it deliberately does NOT catch are all described at the
// top of `route_mounted_scope_leak_test.dart`. Read that first; this file is
// the mechanism, not the argument.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'scope_leak_scanner.dart';

/// One route mount that reads per-tab state with no scope on the path.
class RouteScopeViolation {
  /// Creates a violation record.
  RouteScopeViolation({
    required this.routeApi,
    required this.callSite,
    required this.widget,
    required this.widgetPath,
    required this.reads,
    required this.via,
  });

  /// The routing API that mounted the widget (`showDialog`, `Navigator.push`…).
  final String routeApi;

  /// `<path>:<line>` of the route call.
  final String callSite;

  /// The constructed widget's class name.
  final String widget;

  /// Repo-relative path of the widget class declaration.
  final String widgetPath;

  /// Names of the per-tab providers the widget reads.
  final List<String> reads;

  /// Intermediate providers the first read reached the per-tab state through.
  final List<String> via;

  /// The `_allowlist` key form: stable under everything except moving the
  /// call site, which is exactly when an exemption should be re-justified.
  String get allowlistKey => '$widget @ $callSite';
}

/// The per-tab provider set: the seeds plus every provider that transitively
/// reads one.
///
/// The taint closure matters as much as it does for the sibling guard: a
/// dialog that reads only an intermediate provider still ends up reading
/// per-tab state, and would otherwise look clean.
///
/// Exactly one seed source must be supplied.
///
/// * [seedOverrideSpecs] — `path[#symbol]` entries naming an overrides list.
///   A provider is per-tab iff something overrides it per tab, so this is the
///   right notion in a PRODUCT tree: point it at the product's per-tab
///   override factory. Paths are relative to the test's working directory.
/// * [scopeKeyLibrary] — a path suffix; every provider declared in that
///   library seeds the set. This is the shape crux-shared's own scan uses,
///   with the scope-key sentinels (`tabIdProvider` / `paneIdProvider`) as
///   the seeds.
Set<String> routeScopePerTabProviders(
  ScopeGraph graph, {
  List<String> seedOverrideSpecs = const <String>[],
  String? scopeKeyLibrary,
}) {
  assert(
    (seedOverrideSpecs.isNotEmpty) != (scopeKeyLibrary != null),
    'supply exactly one of seedOverrideSpecs / scopeKeyLibrary',
  );
  final seeds = <String>{};
  for (final entry in seedOverrideSpecs) {
    if (entry.trim().isEmpty) continue;
    final parts = entry.trim().split('#');
    seeds.addAll(
      graph.overrideTargets(parts.first, parts.length > 1 ? parts[1] : null),
    );
  }
  if (scopeKeyLibrary != null) {
    for (final info in graph.providers.values) {
      if (p.posix.joinAll(p.split(info.path)).endsWith(scopeKeyLibrary)) {
        seeds.add(info.key);
      }
    }
  }
  return <String>{...seeds, ...taintClosure(graph.reads(), seeds).keys};
}

/// Every route mount that reads per-tab state with no scope on the path.
List<RouteScopeViolation> routeScopeViolations(
  ScopeGraph graph,
  Set<String> perTab, {
  Map<String, String> allowlist = const <String, String>{},
}) {
  final out = <RouteScopeViolation>[];
  for (final mount in graph.routeMounts()) {
    if (mount.scoped) continue;
    final hits = <String>[];
    final via = <String>[];
    for (final read in mount.reads) {
      if (!perTab.contains(read.target)) continue;
      hits.add(graph.nameOf(read.target));
      if (via.isEmpty) via.addAll(read.via);
    }
    if (hits.isEmpty) continue;
    if (allowlist.containsKey('${mount.widget} @ ${mount.callSite}')) continue;
    hits.sort();
    out.add(
      RouteScopeViolation(
        routeApi: mount.routeApi,
        callSite: mount.callSite,
        widget: mount.widget,
        widgetPath: mount.widgetPath ?? '<outside the source roots>',
        reads: hits,
        via: via,
      ),
    );
  }
  out.sort((a, b) => a.callSite.compareTo(b.callSite));
  return out;
}

/// The failure report. Shared so every tree explains the defect — and the two
/// valid fixes, and the one invalid one — in the same words.
String describeRouteScopeViolations(List<RouteScopeViolation> violations) {
  final buf = StringBuffer()
    ..writeln('Route-mounted per-tab scope leak(s) detected:')
    ..writeln();
  for (final v in violations) {
    buf
      ..writeln('  ${v.widget}  (${v.routeApi})')
      ..writeln('    mounted at ${v.callSite}')
      ..writeln('    declared in ${v.widgetPath}')
      ..writeln('    per-tab reads: ${v.reads.join(', ')}');
    if (v.via.isNotEmpty) {
      buf.writeln('    read reached through: ${v.via.join(' > ')}');
    }
    buf.writeln();
  }
  buf
    ..writeln(
      'Each widget above is pushed onto a Navigator that may sit OUTSIDE '
      "the active tab's UncontrolledProviderScope, yet reads per-tab "
      'state. At the root container those reads return the empty '
      'root-scope instances: the dialog shows nothing and writes to '
      "nothing, silently (NetCrux's Search Design dialog shipped this).",
    )
    ..writeln()
    ..writeln("Fix by wrapping the builder in the active tab's container:")
    ..writeln('    showDialog(')
    ..writeln('      context: context,')
    ..writeln('      builder: (_) => UncontrolledProviderScope(')
    ..writeln('        container: container,')
    ..writeln('        child: const FooDialog(),')
    ..writeln('      ),')
    ..writeln('    );')
    ..writeln()
    ..writeln(
      'Passing the data in by constructor parameter instead is equally '
      'valid — but ONLY if the widget then reads nothing. A NULLABLE '
      'parameter with a `ref.read` fallback does not clear the site and '
      'should not: the fallback is the leak, and it fires for every call '
      'site that forgets the argument. Make the parameter required, or '
      'wrap the builder. Adding `useRootNavigator: false` fixes nothing: '
      'it only helps when a nested Navigator happens to live inside the '
      'scope.',
    )
    ..writeln(
      'If a site is genuinely correct, add it to `_allowlist` with a '
      'documented reason.',
    );
  return buf.toString();
}

/// Declares the standard three-test guard over [sourceRoots].
///
/// Call this from a `*_test.dart` `main()`. The three tests are:
///
///  1. **resolution covered the tree** — every library resolved and the
///     per-tab seed set is non-empty. Without this a misconfigured scan
///     reports zero violations and looks like a pass.
///  2. **no route-mounted widget reads per-tab state** — the rule itself.
///  3. **allowlist entries still name a real route mount** — so an exemption
///     cannot outlive the call site it excused.
///
/// [sourceRoots] is a callback rather than a value so the directories are
/// resolved inside `setUpAll`, after the test's working directory is settled.
void defineRouteMountedScopeLeakGuard({
  required List<Directory> Function() sourceRoots,
  List<String> seedOverrideSpecs = const <String>[],
  String? scopeKeyLibrary,
  Map<String, String> allowlist = const <String, String>{},
  String bootstrapHint = 'run `flutter pub get`',
}) {
  late final ScopeGraph graph;
  late final Set<String> perTab;

  setUpAll(() async {
    graph = await ScopeGraph.resolve(sourceRoots());
    perTab = routeScopePerTabProviders(
      graph,
      seedOverrideSpecs: seedOverrideSpecs,
      scopeKeyLibrary: scopeKeyLibrary,
    );
  });

  test('resolution covered the tree', () {
    expect(
      graph.unresolved,
      isEmpty,
      reason:
          'these libraries did not resolve, so any widget they declare is '
          'invisible to the scan — $bootstrapHint',
    );
    expect(
      perTab,
      isNotEmpty,
      reason:
          'the per-tab provider set is empty, which would make every route '
          'mount trivially clean. The seed source is wrong, not the code.',
    );
  });

  test(
    'no route-mounted widget reads per-tab state without an '
    'UncontrolledProviderScope on the path',
    () {
      final violations = routeScopeViolations(
        graph,
        perTab,
        allowlist: allowlist,
      );
      if (violations.isEmpty) return;
      fail(describeRouteScopeViolations(violations));
    },
  );

  test('allowlist entries still name a real route mount', () {
    final live = <String>{
      for (final mount in graph.routeMounts())
        '${mount.widget} @ ${mount.callSite}',
    };
    for (final entry in allowlist.keys) {
      expect(
        live,
        contains(entry),
        reason:
            'allowlisted route mount `$entry` no longer exists — remove or '
            'update its entry in _allowlist.',
      );
    }
  });
}
