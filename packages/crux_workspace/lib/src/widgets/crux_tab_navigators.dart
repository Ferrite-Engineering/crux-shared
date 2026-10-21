// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/workspace_scopes.dart';
import 'package:flutter/material.dart';

/// One nested [Navigator] per tab, inside that tab's provider scope.
///
/// A dialog pushed on the root navigator mounts outside the active tab's
/// `UncontrolledProviderScope`, so a dialog that reads per-tab state has had
/// to wrap its builder in a second scope over the tab's container. Riverpod
/// flushes a container's pending rebuilds from inside each scope that mounts
/// it, so the second scope can mark the tab's own widgets dirty in the
/// middle of a build. A dialog pushed on the tab's own navigator needs no
/// second scope: it is built under the one the pane host already mounted.
///
/// A product opts in by handing one instance to `PaneHost.tabNavigators`
/// and keeping it for the life of the workspace (a provider or a field of
/// the root widget). Then:
///
/// - inside a tab, [cruxTabNavigatorOf] finds that tab's navigator;
/// - from outside every tab (a menu bar, the command palette), pass the
///   active tab's id to [navigatorFor].
///
/// Hand the result to `showCruxDialog(navigator: ...)` (crux_ide_layout).
/// The dialog then covers the tab's area, not the window: the pane's tab bar
/// and the docks beside it stay usable while it is open.
///
/// Register the instance with `WorkspaceNotifier.addScopeReconciler` too.
/// A closing tab's navigator is disposed with the tab, and a disposed
/// navigator never completes the futures of the routes still on it, so a
/// dialog open on a tab as it closes would leave its opener waiting forever
/// (and a `ModalGuard` key taken for it held for the rest of the process).
/// As a reconciler, this pops every route above the tab's content first, so
/// each of those futures completes with null.
class CruxTabNavigators implements WorkspaceScopeReconciler {
  final Map<TabId, GlobalKey<NavigatorState>> _keys =
      <TabId, GlobalKey<NavigatorState>>{};

  /// The key of [tab]'s navigator, created on first use.
  GlobalKey<NavigatorState> keyFor(TabId tab) => _keys.putIfAbsent(
    tab,
    () => GlobalKey<NavigatorState>(debugLabel: 'tabNavigator ${tab.value}'),
  );

  /// [tab]'s navigator, or null when that tab's content has not been built
  /// (a tab never activated) or the tab is gone.
  NavigatorState? navigatorFor(TabId tab) => _keys[tab]?.currentState;

  /// Forgets every tab not in [tabs]. The pane host calls this as tabs
  /// close.
  void retainOnly(Iterable<TabId> tabs) {
    final keep = tabs.toSet();
    _keys.removeWhere((id, _) => !keep.contains(id));
  }

  /// Closes what is open on the navigator of every tab not in [live] (its
  /// dialogs resolve null) and forgets that tab, so a later tab that reuses
  /// the id gets a navigator of its own.
  @override
  void reconcileScopes(WorkspaceScopeSnapshot live) {
    final gone = [
      for (final id in _keys.keys)
        if (!live.tabIds.contains(id)) id,
    ];
    for (final id in gone) {
      final navigator = _keys.remove(id)?.currentState;
      if (navigator != null && navigator.mounted) {
        navigator.popUntil((route) => route.isFirst);
      }
    }
  }
}

/// The navigator of the tab [context] is inside, when the pane host built
/// that tab with `tabNavigators`; null outside every tab, or when the host
/// did not opt in.
NavigatorState? cruxTabNavigatorOf(BuildContext context) => context
    .getInheritedWidgetOfExactType<_TabNavigatorMarker>()
    ?.navigatorKey
    .currentState;

class _TabNavigatorMarker extends InheritedWidget {
  const _TabNavigatorMarker({required this.navigatorKey, required super.child});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  bool updateShouldNotify(_TabNavigatorMarker oldWidget) =>
      !identical(oldWidget.navigatorKey, navigatorKey);
}

/// Carries the latest content builder down to the navigator's one page, so
/// the page rebuilds with the pane host instead of keeping the closure it
/// was first built with.
class _TabContentBuilder extends InheritedWidget {
  const _TabContentBuilder({required this.builder, required super.child});

  final WidgetBuilder builder;

  @override
  bool updateShouldNotify(_TabContentBuilder oldWidget) =>
      !identical(oldWidget.builder, builder);
}

/// A tab's content on its own navigator.
///
/// `PaneHost` builds one per tab when given `tabNavigators`. Exported so a
/// product's widget test can build the same shape around a single tab's
/// content without a whole pane host.
///
/// What the host does so a tab-modal dialog behaves like a dialog without
/// taking the window with it:
///
/// - **Semantics.** The navigator is its own semantics container. A route's
///   modal barrier hides from screen readers everything painted before it,
///   up to the nearest semantics container; without one here, the tab's
///   page (or a dialog over it) hid the window's toolbar and tab bar.
///   Within the tab, a dialog still hides the content behind it.
/// - **Focus, the tab's content.** The page does not take focus when the
///   tab is built: focus stays where the window put it, and a
///   `CruxFocusRegionScope` above puts it in the screen's primary region
///   when it was lost. Tab and Shift+Tab leave the content at its edges for
///   the rest of the window (the tab bar, the toolbar, the docks), so the
///   content is not a Tab trap.
/// - **Focus, a pushed route.** A dialog or sheet pushed on the navigator
///   takes focus when it opens and keeps Tab and Shift+Tab inside itself.
///   The pointer and window-level shortcuts still reach the rest of the
///   window. When it closes, focus returns to the control in the tab that
///   had it before. Window-level key handlers that should stay quiet while
///   a dialog is up check `cruxFocusIsInPushedRoute` (crux_ide_layout).
///
/// The page has no transition.
class CruxTabNavigatorHost extends StatefulWidget {
  /// Creates the host for one tab.
  const CruxTabNavigatorHost({
    required this.navigatorKey,
    required this.builder,
    super.key,
  });

  /// The tab's navigator key, from [CruxTabNavigators.keyFor].
  final GlobalKey<NavigatorState> navigatorKey;

  /// Builds the tab's content.
  final WidgetBuilder builder;

  @override
  State<CruxTabNavigatorHost> createState() => _CruxTabNavigatorHostState();
}

class _CruxTabNavigatorHostState extends State<CruxTabNavigatorHost> {
  @override
  Widget build(BuildContext context) {
    return _TabNavigatorMarker(
      navigatorKey: widget.navigatorKey,
      child: _TabContentBuilder(
        builder: widget.builder,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Navigator(
            key: widget.navigatorKey,
            // Every route pushed above the page keeps Tab inside itself; the
            // page overrides this for itself.
            routeTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
            onGenerateInitialRoutes: (_, _) => <Route<void>>[
              _TabContentRoute(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tab's content as its navigator's first page: no transition, no
/// focus request of its own, and Tab handed on to the window at its edges.
class _TabContentRoute extends PageRoute<void> {
  _TabContentRoute()
    : super(
        requestFocus: false,
        traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
      );

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Builder(
    builder: (inner) => inner
        .dependOnInheritedWidgetOfExactType<_TabContentBuilder>()!
        .builder(inner),
  );
}
