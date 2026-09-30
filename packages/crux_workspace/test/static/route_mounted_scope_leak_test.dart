// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against the ROUTE-MOUNTED form of the per-tab provider
// scope-leak bug class. Companion to `per_tab_provider_scope_leak_test.dart`,
// which cannot see this form at all.
//
// THE BUG (a NetCrux beta defect)
// NetCrux's Search Design dialog returned "No results." for every query on a
// fully loaded design, and applying a result did nothing. `SearchDialog` was
// pushed with `showDialog`, which mounts on the ROOT navigator — outside the
// active tab's `UncontrolledProviderScope`. Its `ref.watch(hierarchyTree…)`
// therefore resolved against the empty root container: it searched an empty
// model and wrote the selection to a tab nobody was looking at. No exception,
// no log line.
//
// WHY THE SIBLING GUARD STRUCTURALLY CANNOT CATCH IT
// `per_tab_provider_scope_leak_test.dart` analyses the PROVIDER graph: it flags
// providers whose bodies transitively read per-tab providers without being
// re-bound per tab. The search dialog was a WIDGET, reading per-tab providers
// through a `WidgetRef`, mounted from a route builder. No provider is involved
// anywhere in the chain, so nothing in that guard's taint closure ever looks at
// it. The receiver-type machinery the two guards share already covers
// `WidgetRef`; what was missing was the route-builder entry point, which is
// what this file adds.
//
// WIDGET TESTS DON'T CATCH IT EITHER, for the same reason provider unit tests
// miss the sibling form: a widget test pumps the dialog under whatever single
// `ProviderScope` the test wired up, so the dialog reads the state the test
// just seeded and passes. The defect only exists relative to a container
// hierarchy no test builds.
//
// ============================ WHAT THIS GUARD DOES ==========================
//
// THE RULE
//   For every route-builder callback — `showDialog`, `showGeneralDialog`,
//   `showModalBottomSheet`, `showBottomSheet`, `showCupertinoDialog`,
//   `showCupertinoModalPopup`, `showAdaptiveDialog`, `showMenu`, and
//   `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` /
//   `restorablePush*` (both `Navigator.of(context).push` and the static form)
//   — take each widget the callback CONSTRUCTS. If that widget's own class
//   body, or its `State` / `ConsumerState`, reads a per-tab provider — or a
//   provider that transitively reads one — then the container must be re-bound
//   on the path. Three forms count as re-binding:
//     * an `UncontrolledProviderScope` / `ProviderScope` written in the
//       builder callback,
//     * one written in the widget's own class body, or
//     * a helper the builder calls whose body writes one — LintCrux's
//       `wrapInActiveTabScope(context, child)`. Resolved one hop; a helper
//       that delegates to a second helper is not followed.
//   None of the three present is a violation.
//
// WHAT IT DOES **NOT** CATCH — read this before trusting a green run
//  1. DEPTH ONE ONLY. Only widgets the builder constructs directly are
//     analysed, plus their `State`. If the builder mounts `FooDialog()` and
//     `FooDialog.build` returns `BarPanel()` which is what reads the per-tab
//     provider, this guard is silent. Following the widget tree properly is an
//     inter-procedural analysis that would have to model conditional
//     construction, builder callbacks and child parameters; that was judged
//     out of proportion to the bug. In practice the reading code is usually in
//     the dialog itself or its `State`, which is depth one — it was for the
//     search dialog.
//  2. NOT A REACHABILITY PROOF. A constructed widget is assumed mounted. A
//     builder that constructs a widget in a branch never taken still counts.
//     This over-approximates, which is the safe direction.
//  3. SCOPE PRESENCE, NOT SCOPE CORRECTNESS. Finding an
//     `UncontrolledProviderScope` in the builder clears the site. Whether the
//     container it is given is the ACTIVE TAB's container — rather than a
//     stale one, or the wrong tab's — is beyond a static scan. A site that
//     passes here can still be wrong; a site that fails here is definitely
//     wrong.
//  4. ROUTES DECLARED, NOT PUSHED. A `go_router` route table, a
//     `MaterialApp.routes` map, or any other declaration whose builder is
//     invoked by the framework rather than at a call site is not scanned. The
//     suite pushes its dialogs imperatively; if that changes, this is the
//     first thing to extend.
//  5. INDIRECT PUSH HELPERS. `myShowThing(context, …)` that internally calls
//     `showDialog` IS caught — at the `showDialog` call inside the helper,
//     which is where the builder is written. But a helper that takes the
//     WIDGET as a parameter (`pushIt(context, const FooDialog())`) is not: at
//     the `showDialog` call the widget is a variable, not a construction.
//  6. WIDGETS DECLARED OUTSIDE THE SOURCE ROOTS contribute no reads. A
//     framework `AlertDialog` is not the host repo's to fix; a widget in a
//     package that is not scanned is invisible.
//  7. NO CALL-GRAPH FOLLOWING OUT OF THE WIDGET. A read counts when it is
//     WRITTEN inside the widget class or its `State` — including in their own
//     private methods, since a class declaration contains its members. A read
//     inside a collaborator the widget merely calls is not attributed to it.
//     This is the sibling guard's one deliberate divergence, and it was
//     measured, not assumed: following the call graph out of a widget reported
//     `PcapToVcdDialog` and `GenerateTestVcdDialog` as reading FOURTEEN
//     per-tab providers each, when all either does is call the workspace API
//     to open a new tab — that API reads per-tab state because opening a tab
//     is its job. Attributing a collaborator's scoping to its caller made the
//     report unusable. The cost is real: a dialog that pushes its per-tab read
//     into a helper object escapes. `route_scope_shapes/shapes.dart` pins both
//     halves of that trade.
//
// ============================ SOURCE ROOTS ==================================
//
// This file scans crux-shared's own scope-owning packages, with the scope-key
// sentinels (`tabIdProvider` / `paneIdProvider`) as the per-tab seed set — the
// same seeds the sibling guard uses. Zero violations is the expected result
// and the point: shared route builders must not couple to a product-owned
// scope model.
//
// A PRODUCT tree runs the SAME rule, not a re-implementation of it. The rule
// is declared by `route_mounted_scope_leak_guard.dart`, which a product's own
// `test/static/route_mounted_scope_leak_test.dart` relative-imports across its
// `crux-shared/` submodule:
//
//   import '../../crux-shared/packages/crux_workspace/test/static/'
//       'route_mounted_scope_leak_guard.dart';
//
//   void main() => defineRouteMountedScopeLeakGuard(
//         sourceRoots: () => [Directory('lib')],
//         seedOverrideSpecs: const [
//           'lib/features/workspace/providers/tab_overrides.dart#fooTabOverrides',
//         ],
//       );
//
// In a product the per-tab set is "everything the product's per-tab override
// list re-binds", which is what `seedOverrideSpecs` names — a provider is
// per-tab iff something overrides it per tab. See the guard library's header
// for why this is a library instead of the eighth copy of a scanner.
//
// `CRUX_ROUTE_SCOPE_ROOTS` still overrides THIS file's roots, for pointing the
// crux-shared scan at an arbitrary tree by hand during an investigation.
//
// COST
// Resolving crux-shared's two source roots costs ~15 s, the same as the
// sibling guard; the route analysis itself is a few hundred milliseconds on
// top. A product `lib/` costs proportionally more (~1–2 min for the larger
// ones). It runs in the default `flutter test` suite.

@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'route_mounted_scope_leak_guard.dart';
import 'scope_leak_scanner.dart';

/// Route-mount sites that read per-tab state without a scope on the path and
/// are nonetheless correct, with the reason. Kept empty: crux-shared's shared
/// route builders read no scope-keyed state, and a real leak is fixed rather
/// than listed.
///
/// An entry is `<widget> @ <path>:<line>`, so moving the call site invalidates
/// the entry rather than silently covering a new one.
const Map<String, String> _allowlist = <String, String>{};

/// The library declaring the scope-key sentinel providers, as a path suffix.
/// Every provider declared there seeds the per-tab set in the default scan.
const String _scopeKeyLibrary = 'lib/src/id_providers.dart';

void main() {
  // The rule itself. Declared by the shared library in
  // `route_mounted_scope_leak_guard.dart` so this tree and every product tree
  // run ONE implementation — see that file's header for why the sibling
  // guard's copy-paste rollout is the thing being avoided.
  final seedSpecs = _seedOverrideSpecs();
  defineRouteMountedScopeLeakGuard(
    sourceRoots: _sourceRoots,
    seedOverrideSpecs: seedSpecs,
    // Env-var seeds (an ad-hoc foreign-tree scan) replace the sentinel seeds
    // rather than adding to them: a product's per-tab set is what its own
    // override list re-binds, and crux-shared's scope keys are not in it.
    scopeKeyLibrary: seedSpecs.isEmpty ? _scopeKeyLibrary : null,
    // Passed explicitly even while empty so the declaration above stays
    // wired: an exemption is added by editing `_allowlist`, not by
    // remembering to also thread it through here.
    // ignore: avoid_redundant_argument_values
    allowlist: _allowlist,
    bootstrapHint: 'run `melos bootstrap`',
  );

  setUpAll(() {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason: 'run this test from the crux_workspace package root',
    );
  });

  // The mutation verification of the rule, kept standing rather than performed
  // once by hand: `route_scope_shapes/shapes.dart` holds the NetCrux bug verbatim
  // next to its shipped fix, so a future simplification of the analysis that
  // stops flagging the bug fails here.
  group('route-mount analysis over the pinned shapes', () {
    late final ScopeGraph shapes;
    late final Set<String> shapePerTab;
    late final List<RouteScopeViolation> found;

    setUpAll(() async {
      shapes = await ScopeGraph.resolve(<Directory>[
        Directory('test/static/route_scope_shapes'),
      ]);
      expect(shapes.unresolved, isEmpty);
      final seed = shapes.keyOf('perTabProvider');
      expect(seed, isNotNull, reason: 'the shape corpus changed shape');
      shapePerTab = <String>{seed!};
      found = routeScopeViolations(shapes, shapePerTab);
    });

    Set<String> flagged() => <String>{for (final v in found) v.widget};

    test('flags the search-dialog bug: a showDialog builder over a per-tab '
        'reader', () {
      expect(flagged(), contains('LeakySearchDialog'));
    });

    test('clears its shipped fix: the builder wraps it in a scope', () {
      // Both shapes construct the SAME widget class, so a guard that keyed on
      // the widget rather than the call site would report one and not the
      // other. Exactly one of the two call sites must be flagged.
      final sites = <String>{
        for (final v in found)
          if (v.widget == 'LeakySearchDialog') v.callSite,
      };
      expect(sites, hasLength(1));
    });

    test('flags a read in the widget class body (no State)', () {
      expect(flagged(), contains('LeakyStatelessPanel'));
    });

    test('flags a read behind a private method on the State', () {
      expect(flagged(), contains('LeakyIndirectDialog'));
    });

    // The documented limitation (7), pinned so it stays a deliberate choice
    // rather than an accident somebody "fixes" back into a false-positive
    // generator.
    test("does not attribute a collaborator object's read to the widget", () {
      expect(flagged(), isNot(contains('CollaboratorReadingDialog')));
    });

    test('reaches the builder nested inside a MaterialPageRoute', () {
      final apis = <String>{
        for (final v in found)
          if (v.widget == 'LeakyStatelessPanel') v.routeApi,
      };
      expect(apis, contains('Navigator.push'));
      expect(apis, contains('showModalBottomSheet'));
    });

    test('clears a widget that installs its own scope', () {
      expect(flagged(), isNot(contains('SelfScopedDialog')));
    });

    test('clears a builder that installs the scope through a named helper', () {
      expect(flagged(), isNot(contains('HelperScopedPanel')));
    });

    test('does not flag a dialog reading only root-scoped state', () {
      expect(flagged(), isNot(contains('RootOnlyDialog')));
    });

    test('does not flag a per-tab reader that is never route-mounted', () {
      expect(flagged(), isNot(contains('InTreePanel')));
    });

    test('does not flag a dialog taking its data by constructor', () {
      expect(flagged(), isNot(contains('InertDialog')));
    });

    test('the corpus is actually being scanned', () {
      // Guards the guard: if resolution silently produced nothing, every
      // expectation above would pass vacuously.
      expect(
        shapes.routeMounts().map((m) => m.widget).toSet(),
        containsAll(<String>[
          'LeakySearchDialog',
          'LeakyStatelessPanel',
          'InertDialog',
        ]),
      );
    });
  });
}

/// Source roots contributing route builders and widget definitions.
///
/// `CRUX_ROUTE_SCOPE_ROOTS` (`:`-separated) overrides the default, which is
/// this package's `lib/` plus the sibling `crux_projects/lib/` — the same two
/// roots the sibling provider guard scans.
List<Directory> _sourceRoots() {
  final override = Platform.environment['CRUX_ROUTE_SCOPE_ROOTS'];
  if (override != null && override.trim().isNotEmpty) {
    return <Directory>[
      for (final path in override.split(':'))
        if (path.trim().isNotEmpty) Directory(path.trim()),
    ];
  }
  final roots = <Directory>[Directory('lib')];
  final projects = Directory('../crux_projects/lib');
  if (projects.existsSync()) roots.add(projects);
  return roots;
}

/// Per-tab seed sources for an ad-hoc scan of a foreign tree.
///
/// `CRUX_ROUTE_SCOPE_SEED_OVERRIDES` is a comma-separated list of
/// `path[#symbol]` entries naming a product's per-tab override list. Empty
/// (the normal case) falls back to [_scopeKeyLibrary], crux-shared's own
/// scope-key sentinels.
///
/// This is the investigation path, not the rollout path: a product enforces
/// the rule by declaring `defineRouteMountedScopeLeakGuard` in its own
/// `test/static/route_mounted_scope_leak_test.dart`. The env vars exist so
/// the rule can be pointed at any checkout on the machine without waiting on
/// a `crux-shared` submodule pin bump.
List<String> _seedOverrideSpecs() {
  final raw = Platform.environment['CRUX_ROUTE_SCOPE_SEED_OVERRIDES'];
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  return <String>[
    for (final entry in raw.split(','))
      if (entry.trim().isNotEmpty) entry.trim(),
  ];
}
