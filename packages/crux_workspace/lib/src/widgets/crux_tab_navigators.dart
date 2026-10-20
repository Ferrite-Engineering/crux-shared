// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/tab_id.dart';
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
class CruxTabNavigators {
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
/// The navigator's single page has no transition. The navigator's own focus
/// scope is set to hand Tab on to the enclosing scope at its edge, as a
/// route does, so the tab's content does not become a Tab trap that the
/// pane's tab bar cannot be reached from.
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _releaseEdges());
  }

  @override
  void didUpdateWidget(CruxTabNavigatorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.navigatorKey, widget.navigatorKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _releaseEdges());
    }
  }

  void _releaseEdges() {
    if (!mounted) return;
    final node = widget.navigatorKey.currentState?.focusNode;
    if (node is FocusScopeNode) {
      node.traversalEdgeBehavior = TraversalEdgeBehavior.parentScope;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TabNavigatorMarker(
      navigatorKey: widget.navigatorKey,
      child: _TabContentBuilder(
        builder: widget.builder,
        child: Navigator(
          key: widget.navigatorKey,
          onGenerateInitialRoutes: (_, _) => <Route<void>>[
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (pageContext, _, _) => Builder(
                builder: (inner) => inner
                    .dependOnInheritedWidgetOfExactType<_TabContentBuilder>()!
                    .builder(inner),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
