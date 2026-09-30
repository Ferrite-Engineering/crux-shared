// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Moves keyboard focus to the next [CruxFocusRegion].
class CruxNextRegionIntent extends Intent {
  /// Creates the intent.
  const CruxNextRegionIntent();
}

/// Moves keyboard focus to the previous [CruxFocusRegion].
class CruxPreviousRegionIntent extends Intent {
  /// Creates the intent.
  const CruxPreviousRegionIntent();
}

/// The keys [CruxFocusRegionScope] binds by default: F6 and Shift+F6, the
/// region-cycling keys of desktop IDEs, browsers and chat clients.
const Map<ShortcutActivator, Intent> kCruxRegionShortcuts =
    <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.f6): CruxNextRegionIntent(),
      SingleActivator(LogicalKeyboardKey.f6, shift: true):
          CruxPreviousRegionIntent(),
    };

/// Groups the [CruxFocusRegion]s of one screen so the keyboard can jump
/// between them.
///
/// A dense IDE window is dozens of Tab stops long. F6 moves focus to the next
/// region that holds a focusable control and Shift+F6 to the previous one.
/// Returning to a region restores the control that was focused when F6 left
/// it.
///
/// Regions are visited in reading order, the same order Flutter's default
/// traversal policy gives Tab across region groups, so F6 and Tab agree on
/// which region comes next.
///
/// The keys also work while nothing on the screen has focus — the state a
/// window is in before the first click, when a desktop screen reader has
/// nothing to read — as long as no other route is on top of the screen.
///
/// **Lost focus.** When focus falls out of the screen onto a bare focus
/// scope — the focused control was rebuilt away (a toolbar swapped between
/// two layouts, a closed tab's content), or the window came back from a
/// native file dialog — the scope puts it back: on the control last focused
/// inside it if that still exists, otherwise in the [CruxFocusRegion.primary]
/// region, otherwise in the first region. A bare scope announces nothing and
/// sits above every screen-level shortcut handler, so a window left in that
/// state is both silent and deaf to its own keyboard shortcuts. Controlled
/// by [restoreLostFocus]; on by default on desktop platforms only, where a
/// restored text field cannot raise a soft keyboard.
class CruxFocusRegionScope extends StatefulWidget {
  /// Creates the scope.
  const CruxFocusRegionScope({
    required this.child,
    this.shortcuts = kCruxRegionShortcuts,
    this.restoreLostFocus,
    super.key,
  });

  /// The screen.
  final Widget child;

  /// Keys bound to [CruxNextRegionIntent] and [CruxPreviousRegionIntent].
  /// Pass an empty map when the host binds the intents in its own keymap.
  final Map<ShortcutActivator, Intent> shortcuts;

  /// Whether focus that falls out of the screen is put back. Null means on
  /// for macOS, Windows and Linux and off elsewhere.
  final bool? restoreLostFocus;

  /// The nearest scope, or null.
  static CruxFocusRegionScopeState? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_CruxFocusRegionScopeMarker>()
      ?.state;

  @override
  State<CruxFocusRegionScope> createState() => CruxFocusRegionScopeState();
}

/// State of a [CruxFocusRegionScope]; drives region-to-region movement.
class CruxFocusRegionScopeState extends State<CruxFocusRegionScope> {
  final List<CruxFocusRegionState> _regions = <CruxFocusRegionState>[];
  final FocusNode _scopeNode = FocusNode(
    debugLabel: 'CruxFocusRegionScope',
    skipTraversal: true,
    canRequestFocus: false,
  );

  FocusNode? _lastInside;
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleUnfocusedKey);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleUnfocusedKey);
    FocusManager.instance.removeListener(_onFocusChanged);
    _scopeNode.dispose();
    super.dispose();
  }

  bool get _restores {
    final explicit = widget.restoreLostFocus;
    if (explicit != null) return explicit;
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };
  }

  bool _isInside(FocusNode node) => _isUnder(node, _scopeNode);

  void _onFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && _isInside(primary)) {
      if (primary is! FocusScopeNode) _lastInside = primary;
      return;
    }
    // A real control outside the screen (a menu bar, a dialog's button)
    // holds focus on purpose.
    if (primary != null && primary is! FocusScopeNode) return;
    if (_restoreScheduled || !mounted || !_restores) return;
    _restoreScheduled = true;
    // After the frame that dropped focus has finished building, so a
    // control that is about to claim focus in that frame is not overridden.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(_restoreLostFocus),
    );
  }

  void _restoreLostFocus() {
    _restoreScheduled = false;
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && (primary is! FocusScopeNode || _isInside(primary))) {
      return;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final last = _lastInside;
    if (last != null &&
        _isLive(last) &&
        last.canRequestFocus &&
        _isInside(last)) {
      last.requestFocus();
      return;
    }
    for (final region in _regions) {
      if (region.widget.primary && region.enter()) return;
    }
    focusNext();
  }

  void _register(CruxFocusRegionState region) {
    if (!_regions.contains(region)) _regions.add(region);
  }

  void _unregister(CruxFocusRegionState region) => _regions.remove(region);

  /// Moves focus to the next region with a focusable control. Returns
  /// whether focus moved.
  bool focusNext() => _move(forward: true);

  /// Moves focus to the previous region with a focusable control. Returns
  /// whether focus moved.
  bool focusPrevious() => _move(forward: false);

  bool _move({required bool forward}) {
    final attached = <FocusNode, CruxFocusRegionState>{
      for (final r in _regions)
        if (r._node.context != null && !r._node.rect.isEmpty) r._node: r,
    };
    if (attached.isEmpty) return false;
    final regions = ReadingOrderTraversalPolicy()
        .sortDescendants(attached.keys, attached.keys.first)
        .map((node) => attached[node]!)
        .toList();
    final primary = FocusManager.instance.primaryFocus;
    final current = regions.indexWhere((r) => r.contains(primary));
    if (current != -1) regions[current]._remember(primary);
    final n = regions.length;
    for (var step = 1; step <= n; step++) {
      final int index;
      if (current == -1) {
        index = forward ? step - 1 : n - step;
      } else {
        index = (current + (forward ? step : -step)) % n;
        if (index == current) continue;
      }
      if (regions[index].enter()) return true;
    }
    return false;
  }

  bool _handleUnfocusedKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && _isUnder(primary, _scopeNode)) {
      // Focus is inside the screen; the Shortcuts below handle the key.
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    for (final entry in widget.shortcuts.entries) {
      if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
      return switch (entry.value) {
        CruxNextRegionIntent() => focusNext(),
        CruxPreviousRegionIntent() => focusPrevious(),
        _ => false,
      };
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _CruxFocusRegionScopeMarker(
      state: this,
      child: Focus(
        focusNode: _scopeNode,
        includeSemantics: false,
        child: widget.child,
      ),
    );
    if (widget.shortcuts.isNotEmpty) {
      child = Shortcuts(shortcuts: widget.shortcuts, child: child);
    }
    return Actions(
      actions: <Type, Action<Intent>>{
        CruxNextRegionIntent: CallbackAction<CruxNextRegionIntent>(
          onInvoke: (_) => focusNext(),
        ),
        CruxPreviousRegionIntent: CallbackAction<CruxPreviousRegionIntent>(
          onInvoke: (_) => focusPrevious(),
        ),
      },
      child: child,
    );
  }
}

class _CruxFocusRegionScopeMarker extends InheritedWidget {
  const _CruxFocusRegionScopeMarker({
    required this.state,
    required super.child,
  });

  final CruxFocusRegionScopeState state;

  @override
  bool updateShouldNotify(_CruxFocusRegionScopeMarker oldWidget) =>
      state != oldWidget.state;
}

/// One keyboard region of a screen: a toolbar, a dock, the main surface, a
/// status bar.
///
/// Tab order stays inside the region until its controls are exhausted
/// rather than being sorted across the whole window by position, which is
/// what otherwise interleaves a sidebar's controls with the pane beside it.
/// Under a [CruxFocusRegionScope] the region is also an F6 stop.
///
/// [semanticLabel] names the region for a screen reader, which announces it
/// when focus enters. Leave it null when the child already carries a region
/// label, or the name is announced twice.
class CruxFocusRegion extends StatefulWidget {
  /// Creates a region.
  const CruxFocusRegion({
    required this.child,
    this.semanticLabel,
    this.primary = false,
    super.key,
  });

  /// The region's content.
  final Widget child;

  /// The region's accessible name, or null when the child names itself.
  final String? semanticLabel;

  /// Whether this is the screen's main surface, where
  /// [CruxFocusRegionScope] puts focus back when it is lost and the control
  /// that last had it is gone.
  final bool primary;

  @override
  State<CruxFocusRegion> createState() => CruxFocusRegionState();
}

/// State of a [CruxFocusRegion].
class CruxFocusRegionState extends State<CruxFocusRegion> {
  final FocusNode _node = FocusNode(
    debugLabel: 'CruxFocusRegion',
    skipTraversal: true,
    canRequestFocus: false,
  );
  CruxFocusRegionScopeState? _scope;
  FocusNode? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = CruxFocusRegionScope.maybeOf(context);
    if (scope != _scope) {
      _scope?._unregister(this);
      _scope = scope?.._register(this);
    }
  }

  @override
  void dispose() {
    _scope?._unregister(this);
    _node.dispose();
    super.dispose();
  }

  /// Whether [node] is inside this region.
  bool contains(FocusNode? node) =>
      node != null && (node == _node || _isUnder(node, _node));

  void _remember(FocusNode? node) {
    if (node != _node && contains(node)) _last = node;
  }

  /// Focuses the control last focused here, or the first focusable control
  /// in reading order. Returns false when the region has nothing to focus.
  bool enter() {
    final last = _last;
    if (last != null &&
        _isLive(last) &&
        last.canRequestFocus &&
        !last.skipTraversal &&
        contains(last)) {
      last.requestFocus();
      return true;
    }
    final candidates = _node.traversalDescendants
        .where((node) => node.context != null)
        .toList();
    if (candidates.isEmpty) return false;
    ReadingOrderTraversalPolicy()
        .sortDescendants(candidates, candidates.first)
        .first
        .requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    Widget child = FocusTraversalGroup(
      child: Focus(
        focusNode: _node,
        includeSemantics: false,
        child: widget.child,
      ),
    );
    final label = widget.semanticLabel;
    if (label != null) {
      child = Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        child: child,
      );
    }
    return child;
  }
}

/// Whether [node] is still attached to the focus tree under a mounted
/// element.
///
/// A detached node keeps its `context` and its cached `ancestors`, so neither
/// says whether it is still on screen; its `parent` is cleared on detach.
/// Requesting focus on a detached node silently does nothing, which is how a
/// screen whose focused button was removed ended up with focus nowhere.
bool _isLive(FocusNode node) {
  final context = node.context;
  return node.parent != null && context is Element && context.mounted;
}

/// Whether [ancestor] is above [node] in the live focus tree, walking
/// `parent` links rather than the cached `ancestors` list.
bool _isUnder(FocusNode node, FocusNode ancestor) {
  for (var parent = node.parent; parent != null; parent = parent.parent) {
    if (identical(parent, ancestor)) return true;
  }
  return false;
}
