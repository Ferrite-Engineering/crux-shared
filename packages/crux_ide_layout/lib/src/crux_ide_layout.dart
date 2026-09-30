// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_ide_layout/src/crux_ide_layout_theme.dart';
import 'package:crux_ide_layout/src/focus_regions.dart';
import 'package:crux_ide_layout/src/ide_panel_layout.dart';
import 'package:crux_theme/crux_theme.dart' show CruxChromeColors;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panes/panes.dart';
// `Resizer` is not exported, and the traversal policy below has to recognise
// it. The guard test pins the behaviour, so a `panes` upgrade that moves the
// class fails there rather than silently restoring the bare "text" stops.
// ignore: implementation_imports
import 'package:panes/src/resizer.dart' show Resizer;

/// `panes`' own show/hide + resize animation duration, re-declared here so a
/// fit clamp can suppress it for the frame that applies one.
const Duration _paneAnimationDuration = Duration(milliseconds: 250);

/// Sizes within this many logical pixels are treated as equal, so a fit clamp
/// does not re-notify the controller over sub-pixel drift.
const double _sizeEpsilon = 0.5;

/// The cross-suite dockable IDE-layout shell.
///
/// One implementation of the four-region (`left | center | right` over
/// `center / bottom`) `panes` `IdeLayout` rendered by every product in the
/// suite. It owns the `IdeController`, the `PaneTheme`, and the
/// build-controller / visibility-sync / `onPaneStateChanged` / `onSizeChanged`
/// wiring, so each product supplies only its four region builders and its
/// layout adapters.
///
/// The widget is provider-agnostic: the host watches its own
/// `PanelLayoutState`, wraps it in an [IdePanelLayout] (read) + an
/// [IdePanelLayoutSink] (write), and rebuilds `CruxIdeLayout` with a fresh
/// [layout] whenever the state changes. On each rebuild the widget diffs the
/// new visibility against the last value it applied and pushes only the deltas
/// onto the controller, so a View-menu toggle, a drag-to-collapse, and a
/// device-class force-hide all converge through one path.
///
/// Sizing is unit-agnostic: [IdePanelLayout] returns `PaneSize?`, so an app
/// that stores pixels and one that stores fractions both flow through the same
/// widget. The optional per-region min sizes and [centerMinSize] cover the
/// per-app constraints (e.g. WaveCrux's 120dp center floor).
///
/// Pixel-sized regions are also clamped to the window: shrinking the window
/// past what the regions + resizers + [centerMinSize] need shrinks the regions
/// rather than starving the center region and overflowing `panes`' `RenderFlex`
/// (see `_applyFitClamps`). The clamp is transient — it is never persisted, and
/// the regions grow back to their stored sizes as the window does.
class CruxIdeLayout extends StatefulWidget {
  /// Creates the shared IDE layout. The four region builders are required;
  /// min sizes and [theme] are optional.
  const CruxIdeLayout({
    required this.layout,
    required this.sink,
    required this.leftBuilder,
    required this.centerBuilder,
    required this.rightBuilder,
    required this.bottomBuilder,
    this.leftMinSize,
    this.rightMinSize,
    this.bottomMinSize,
    this.centerMinSize,
    this.theme = const CruxIdeLayoutTheme(),
    super.key,
  });

  /// Current visibility + size of each region (host-watched snapshot).
  final IdePanelLayout layout;

  /// Where drag-to-collapse / drag-to-resize gestures are persisted.
  final IdePanelLayoutSink sink;

  /// Builds the left region's content.
  final IdePaneBuilder leftBuilder;

  /// Builds the center region's content.
  final IdePaneBuilder centerBuilder;

  /// Builds the right region's content.
  final IdePaneBuilder rightBuilder;

  /// Builds the bottom region's content.
  final IdePaneBuilder bottomBuilder;

  /// Optional minimum size for the left region.
  final PaneSize? leftMinSize;

  /// Optional minimum size for the right region.
  final PaneSize? rightMinSize;

  /// Optional minimum size for the bottom region.
  final PaneSize? bottomMinSize;

  /// Optional minimum size for the center region. When set, the center pane is
  /// re-declared with this floor so the splitter cannot shrink it past it
  /// (WaveCrux pins this to 120dp per its layout spec).
  final PaneSize? centerMinSize;

  /// Resizer styling.
  final CruxIdeLayoutTheme theme;

  @override
  State<CruxIdeLayout> createState() => _CruxIdeLayoutState();
}

class _CruxIdeLayoutState extends State<CruxIdeLayout> {
  late IdeController _controller;
  late bool _leftVisible;
  late bool _rightVisible;
  late bool _bottomVisible;

  // Last pane sizes applied to the controller. Tracked so [didUpdateWidget]
  // reconciles only genuine host-driven size changes (e.g. a session restore
  // that updates [IdePanelLayout.leftSize] after the controller was built),
  // not the synchronous echo of a user drag — [_onSizeChanged] records the
  // dragged size here so the host's mirror-rebuild is seen as a no-op delta.
  PaneSize? _leftSize;
  PaneSize? _rightSize;
  PaneSize? _bottomSize;

  // True while this widget — not the user — is driving the controller: a
  // host-driven visibility/size delta from [didUpdateWidget], or a fit clamp
  // from [_applyFitClamps]. `panes` fires [onPaneStateChanged] synchronously
  // from `show`/`hide`, so without this guard a View-menu toggle would echo
  // back into the sink *during the build phase* (the host's provider is
  // mid-rebuild) — a "modified a provider while building" error for synchronous
  // notifiers. The echo is also redundant: the host already holds that
  // visibility value. User drag gestures fire [onPaneStateChanged] outside this
  // window and pass through to the sink normally.
  bool _applyingHostDelta = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    final layout = widget.layout;
    _leftVisible = layout.leftVisible;
    _rightVisible = layout.rightVisible;
    _bottomVisible = layout.bottomVisible;
    _leftSize = layout.leftSize;
    _rightSize = layout.rightSize;
    _bottomSize = layout.bottomSize;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IdeController _buildController() {
    final layout = widget.layout;
    final controller = IdeController(
      leftVisible: layout.leftVisible,
      leftSize: layout.leftSize,
      leftMinSize: widget.leftMinSize,
      rightVisible: layout.rightVisible,
      rightSize: layout.rightSize,
      rightMinSize: widget.rightMinSize,
      bottomVisible: layout.bottomVisible,
      bottomSize: layout.bottomSize,
      bottomMinSize: widget.bottomMinSize,
    );
    final centerMinSize = widget.centerMinSize;
    if (centerMinSize != null) {
      // IdeController has no center-min parameter, so re-declare the center
      // pane with the floor (preserving its fraction(1) initial size).
      controller.centerController.updatePane(
        PaneEntry(
          id: IdePane.center.id,
          initialSize: PaneSize.fraction(1),
          minSize: centerMinSize,
        ),
      );
    }
    return controller;
  }

  @override
  void didUpdateWidget(CruxIdeLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Apply only the visibility deltas the host pushed since the last build.
    // The guard suppresses the synchronous sink echo `panes` emits from
    // `show`/`hide` (see [_applyingHostDelta]).
    final layout = widget.layout;
    _applyingHostDelta = true;
    try {
      if (layout.leftVisible != _leftVisible) {
        _leftVisible = layout.leftVisible;
        _applyVisibility(
          _controller.rootController,
          IdePane.left,
          _leftVisible,
        );
      }
      if (layout.rightVisible != _rightVisible) {
        _rightVisible = layout.rightVisible;
        _applyVisibility(
          _controller.rootController,
          IdePane.right,
          _rightVisible,
        );
      }
      if (layout.bottomVisible != _bottomVisible) {
        _bottomVisible = layout.bottomVisible;
        _applyVisibility(
          _controller.centerController,
          IdePane.bottom,
          _bottomVisible,
        );
      }
      // Reconcile host-driven size deltas onto the live controller. The
      // controller is built once in [initState], so a size that changes after
      // construction (a session restore writing a persisted pane size into the
      // host's layout) would otherwise never reach the controller. Visibility
      // is reconciled the same way above. Guarded by [_applyingHostDelta] so
      // the `updateSize` → `notifyListeners` → [_onSizeChanged] echo is
      // suppressed.
      if (layout.leftSize != _leftSize) {
        _leftSize = layout.leftSize;
        if (_leftSize != null) {
          _controller.rootController.updateSize(IdePane.left.id, _leftSize!);
        }
      }
      if (layout.rightSize != _rightSize) {
        _rightSize = layout.rightSize;
        if (_rightSize != null) {
          _controller.rootController.updateSize(IdePane.right.id, _rightSize!);
        }
      }
      if (layout.bottomSize != _bottomSize) {
        _bottomSize = layout.bottomSize;
        if (_bottomSize != null) {
          _controller.centerController.updateSize(
            IdePane.bottom.id,
            _bottomSize!,
          );
        }
      }
    } finally {
      _applyingHostDelta = false;
    }
  }

  void _applyVisibility(PaneController controller, IdePane pane, bool visible) {
    if (visible) {
      controller.show(pane.id);
    } else {
      controller.hide(pane.id);
    }
  }

  void _onPaneStateChanged(IdePane pane, bool isVisible) {
    // Ignore the synchronous echo of a host-driven programmatic show/hide; only
    // genuine user drag gestures should write back to the sink.
    if (_applyingHostDelta) return;
    switch (pane) {
      case IdePane.left:
        _leftVisible = isVisible;
        widget.sink.setLeftVisible(visible: isVisible);
      case IdePane.right:
        _rightVisible = isVisible;
        widget.sink.setRightVisible(visible: isVisible);
      case IdePane.bottom:
        _bottomVisible = isVisible;
        widget.sink.setBottomVisible(visible: isVisible);
      case IdePane.center:
      case IdePane.centerContainer:
        // The center pane is always visible; nothing to mirror.
        break;
    }
  }

  void _onSizeChanged(IdePane pane, double size) {
    // Ignore the synchronous echo of a host-driven programmatic resize (the
    // size reconciliation in [didUpdateWidget]); only genuine user drag
    // gestures should write back to the sink. Mirrors [_onPaneStateChanged].
    if (_applyingHostDelta) return;
    switch (pane) {
      case IdePane.left:
        _leftSize = PaneSize.pixel(size);
        widget.sink.setLeftSize(size);
      case IdePane.right:
        _rightSize = PaneSize.pixel(size);
        widget.sink.setRightSize(size);
      case IdePane.bottom:
        _bottomSize = PaneSize.pixel(size);
        widget.sink.setBottomSize(size);
      case IdePane.center:
      case IdePane.centerContainer:
        // The center container's size is derived from its siblings.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Fit clamp
  // ---------------------------------------------------------------------------

  /// Shrinks the pixel-sized regions so the pane stacks fit [constraints],
  /// returning true if any region was resized.
  ///
  /// `panes` lays a pixel-sized region out as a hard `SizedBox` and gives the
  /// center region whatever flex space is left over. Nothing clamps those pixel
  /// sizes against the container, so a window small enough that
  /// `regions + resizers` exceeds it first starves the center to zero and then
  /// overflows the `RenderFlex` — a clipped panel plus a debug-mode overflow
  /// assert. Shrinking the regions instead keeps the center alive at
  /// [CruxIdeLayout.centerMinSize] and is reversible: the un-clamped
  /// ("preferred") size stays in [_leftSize] / [_rightSize] / [_bottomSize] and
  /// is restored as the window grows back.
  ///
  /// Runs from the layout callback of the [LayoutBuilder] in [build] — the
  /// available extent is not known any earlier. Writing to the controller from
  /// there marks the `panes` `MultiPane`s dirty, which is legal because they
  /// are descendants of that `LayoutBuilder` and so rebuild inside the same
  /// build scope.
  ///
  /// Writes are guarded by [_applyingHostDelta] so a clamp never reaches the
  /// sink: it is a transient fit correction, not a user resize, and persisting
  /// it would destroy the user's chosen size the moment they shrink the window.
  bool _applyFitClamps(BoxConstraints constraints) {
    _applyingHostDelta = true;
    try {
      final bottom = _clampBottom(constraints.maxHeight);
      final sides = _clampSides(constraints.maxWidth);
      return bottom || sides;
    } finally {
      _applyingHostDelta = false;
    }
  }

  /// Clamps the bottom region against the height available to the vertical
  /// (center / bottom) stack.
  bool _clampBottom(double maxHeight) {
    if (!maxHeight.isFinite) return false;
    final controller = _controller.centerController;
    if (!controller.isVisible(IdePane.bottom.id)) return false;
    final preferred = _preferredPixels(
      controller,
      IdePane.bottom.id,
      _bottomSize,
    );
    // A fraction-sized region is flex, not a fixed box, so it cannot overflow.
    if (preferred == null) return false;
    final room = math.max<double>(
      0,
      maxHeight -
          widget.theme.resizerThickness -
          _floorPixels(widget.centerMinSize, maxHeight),
    );
    return _resizeTo(controller, IdePane.bottom.id, math.min(preferred, room));
  }

  /// Clamps the left and right regions against the width available to the
  /// horizontal (left / center / right) stack.
  bool _clampSides(double maxWidth) {
    if (!maxWidth.isFinite) return false;
    final controller = _controller.rootController;
    final leftShown = controller.isVisible(IdePane.left.id);
    final rightShown = controller.isVisible(IdePane.right.id);
    if (!leftShown && !rightShown) return false;
    final left = leftShown
        ? _preferredPixels(controller, IdePane.left.id, _leftSize)
        : 0.0;
    final right = rightShown
        ? _preferredPixels(controller, IdePane.right.id, _rightSize)
        : 0.0;
    if (left == null || right == null) return false;
    final resizers = (leftShown ? 1 : 0) + (rightShown ? 1 : 0);
    final room = math.max<double>(
      0,
      maxWidth -
          resizers * widget.theme.resizerThickness -
          _floorPixels(widget.centerMinSize, maxWidth),
    );
    final wanted = left + right;
    // Shrink both sides in proportion rather than draining one first: the
    // left/right ratio the user chose survives the clamp, and the scale
    // inverts cleanly on the way back out.
    final scale = wanted > room && wanted > 0 ? room / wanted : 1.0;
    var changed = false;
    if (leftShown) {
      changed = _resizeTo(controller, IdePane.left.id, left * scale);
    }
    if (rightShown) {
      changed =
          _resizeTo(controller, IdePane.right.id, right * scale) || changed;
    }
    return changed;
  }

  /// Pushes [target] onto region [id] unless it already effectively holds that
  /// size. The equality check is what stops a clamp from notifying — and so
  /// rebuilding — on every layout pass.
  bool _resizeTo(PaneController controller, String id, double target) {
    final current = _currentPixels(controller, id);
    if (current != null && (current - target).abs() < _sizeEpsilon) {
      return false;
    }
    controller.updateSize(id, PaneSize.pixel(target));
    return true;
  }

  /// The size region [id] would hold with no clamp applied: the host's value
  /// (which [_onSizeChanged] keeps in step with user drags) falling back to the
  /// entry's initial size. Null when the region is fraction-sized.
  double? _preferredPixels(
    PaneController controller,
    String id,
    PaneSize? hostSize,
  ) => _pixelsOrNull(hostSize ?? _entry(controller, id).initialSize);

  /// The size region [id] currently renders at.
  double? _currentPixels(PaneController controller, String id) =>
      controller.getVisualPixelSize(id) ??
      _pixelsOrNull(_entry(controller, id).initialSize);

  PaneEntry _entry(PaneController controller, String id) =>
      controller.entries.firstWhere((e) => e.id == id);

  double? _pixelsOrNull(PaneSize size) => switch (size) {
    PaneSizePixel(:final pixels) => pixels,
    PaneSizeFraction() => null,
  };

  /// A min size in pixels, resolving a fractional one against [extent]. A null
  /// min means the center may be squeezed to nothing.
  double _floorPixels(PaneSize? size, double extent) => switch (size) {
    PaneSizePixel(:final pixels) => pixels,
    PaneSizeFraction(:final fraction) => fraction * extent,
    null => 0,
  };

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final colorScheme = Theme.of(context).colorScheme;
    // The theme's `splitter` / `splitter.hover` chrome tokens, when it sets
    // them; an explicit [CruxIdeLayoutTheme] colour still outranks them.
    final chrome = CruxChromeColors.of(context);
    final active = chrome?.splitterHover ?? colorScheme.primary;
    return PaneTheme(
      data: PaneThemeData(
        resizerThickness: theme.resizerThickness,
        resizerHitTestThickness: theme.resizerHitTestThickness,
        resizerColor:
            theme.resizerColor ??
            chrome?.splitter ??
            colorScheme.outlineVariant,
        resizerHoverColor: theme.resizerHoverColor ?? active,
        resizerFocusedColor: theme.resizerFocusedColor ?? active,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final clamped = _applyFitClamps(constraints);
          return FocusTraversalGroup(
            policy: _RegionOrderTraversalPolicy(),
            child: IdeLayout(
              controller: _controller,
              // An animated clamp would keep rendering the pre-clamp (too
              // large) size for a few frames — exactly the overflow the clamp
              // exists to prevent — so the frame that applies one lands
              // instantly. Frames that don't clamp keep the normal show/hide
              // animation.
              animationDuration: clamped
                  ? Duration.zero
                  : _paneAnimationDuration,
              onPaneStateChanged: _onPaneStateChanged,
              onSizeChanged: _onSizeChanged,
              leftPanelBuilder: (context, progress) => _region(
                widget.leftBuilder(context, progress),
                visible: widget.layout.leftVisible,
                resizes: IdePane.left,
              ),
              centerBuilder: (context, progress) => _region(
                widget.centerBuilder(context, progress),
                primary: true,
              ),
              rightPanelBuilder: (context, progress) => _region(
                widget.rightBuilder(context, progress),
                visible: widget.layout.rightVisible,
                resizes: IdePane.right,
              ),
              bottomPanelBuilder: (context, progress) => _region(
                widget.bottomBuilder(context, progress),
                visible: widget.layout.bottomVisible,
                resizes: IdePane.bottom,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Makes a region one keyboard unit (see [CruxFocusRegion]).
  ///
  /// A hidden pixel-sized region is still built, at its full size, inside a
  /// zero-width clip. Its controls lose their semantics but not their focus
  /// nodes, so without [ExcludeFocus] Tab would land on invisible controls
  /// that a screen reader cannot announce.
  ///
  /// A side or bottom region also takes the keyboard resize keys (see
  /// [kCruxPaneResizeStep]): with focus anywhere inside it, Ctrl+Shift+Arrow
  /// (Cmd+Shift+Arrow on Apple platforms) grows or shrinks it. This replaces
  /// the arrow-key resizing the `panes` resizers offered only while they held
  /// focus, which they no longer can (see [_RegionOrderTraversalPolicy]).
  Widget _region(
    Widget child, {
    bool visible = true,
    bool primary = false,
    IdePane? resizes,
  }) {
    Widget content = ExcludeFocus(excluding: !visible, child: child);
    if (resizes != null) {
      final apple =
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS;
      SingleActivator key(LogicalKeyboardKey arrow) => SingleActivator(
        arrow,
        shift: true,
        control: !apple,
        meta: apple,
      );
      final (grow, shrink) = switch (resizes) {
        IdePane.left => (
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowLeft,
        ),
        IdePane.right => (
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ),
        _ => (LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown),
      };
      final bindings = <ShortcutActivator, double>{
        key(grow): kCruxPaneResizeStep,
        key(shrink): -kCruxPaneResizeStep,
      };
      // Not `CallbackShortcuts`: its `Focus` keeps its semantics, and that
      // annotation merges loose content across the region into one node (a
      // search field and the line below it became "Search… 644 rules").
      content = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (node, event) {
          for (final MapEntry(key: activator, value: delta)
              in bindings.entries) {
            if (activator.accepts(event, HardwareKeyboard.instance)) {
              _resizeByKeyboard(resizes, delta);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: content,
      );
    }
    return CruxFocusRegion(primary: primary, child: content);
  }

  /// Grows [pane] by [delta] logical pixels (shrinks when negative), within
  /// its minimum and maximum, and persists the result through the sink the
  /// same way a drag does.
  void _resizeByKeyboard(IdePane pane, double delta) {
    final controller = pane == IdePane.bottom
        ? _controller.centerController
        : _controller.rootController;
    if (!controller.isVisible(pane.id)) return;
    final current = _currentPixels(controller, pane.id);
    if (current == null) return;
    final entry = _entry(controller, pane.id);
    final min = _pixelsOrNull(entry.minSize ?? PaneSize.pixel(0)) ?? 0;
    final max = entry.maxSize == null
        ? double.infinity
        : (_pixelsOrNull(entry.maxSize!) ?? double.infinity);
    final target = (current + delta).clamp(min, max);
    if ((target - current).abs() < _sizeEpsilon) return;
    // The controller reports the change through `onSizeChanged`, which
    // persists it to the sink exactly as a drag would.
    controller.updateSize(pane.id, PaneSize.pixel(target));
  }
}

/// How far one keyboard resize press moves a region's edge, in logical
/// pixels.
const double kCruxPaneResizeStep = 20;

/// Orders the four regions in reading order and keeps the `panes` resizers
/// out of the Tab order.
///
/// A resizer is a full-height focusable strip with no semantics of its own,
/// so a screen reader announces it as bare "text". Its full height also puts
/// it in the same reading-order band as every control beside it, which is
/// what interleaves one dock's buttons with another's. `panes` offers no way
/// to label or unfocus it, so it is skipped here; dragging still resizes.
///
/// Reading order over whole regions matches the order
/// [CruxFocusRegionScope] gives F6.
class _RegionOrderTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) => super.sortDescendants(
    descendants.where((node) => node == currentNode || !_isPaneResizer(node)),
    currentNode,
  );

  static bool _isPaneResizer(FocusNode node) =>
      node.context?.findAncestorWidgetOfExactType<Resizer>() != null;
}
