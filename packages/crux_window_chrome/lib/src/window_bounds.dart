// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Persisted top-level application **window** geometry — position, size, and
/// maximized state — restored on the next cold start so the app reopens where
/// the user left it (VS Code-style).
///
/// The host decides where to store it (typically the auto-managed workspace
/// document, alongside other product-level ambient flags) and feeds it back to
/// `initWindowChrome` via `restore`. It is *window*-level, not per-tab — a
/// window spans many tabs.
///
/// [left] / [top] are the logical-pixel screen coordinates of the window's
/// top-left corner, or null when the position is unknown / should be left to
/// the window manager (e.g. a first launch, or a restored position sanitized
/// away as off-screen — see [sanitizedForRestore]).
///
/// Only meaningful on the desktop platforms that drive `window_manager`
/// (Windows / Linux via `useCustomWindowChrome`). Pure Dart — no Flutter
/// imports — so it stays trivially unit-testable without a binding.
@immutable
class WindowBounds {
  /// Creates a window-bounds snapshot. [width] and [height] are required;
  /// [left] / [top] are optional (null ⇒ let the window manager place it).
  const WindowBounds({
    required this.width,
    required this.height,
    this.left,
    this.top,
    this.maximized = false,
  });

  /// Deserializes from a stored JSON map.
  ///
  /// Tolerant of missing/malformed fields: a non-finite or non-positive size
  /// yields null so the caller falls back to the layout default rather than
  /// restoring a degenerate window.
  static WindowBounds? fromJson(Map<String, Object?> json) {
    final width = _finiteDouble(json['width']);
    final height = _finiteDouble(json['height']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return WindowBounds(
      width: width,
      height: height,
      left: _finiteDouble(json['left']),
      top: _finiteDouble(json['top']),
      maximized: json['maximized'] == true,
    );
  }

  /// Logical x-coordinate of the window's left edge, or null if unknown.
  final double? left;

  /// Logical y-coordinate of the window's top edge, or null if unknown.
  final double? top;

  /// Logical window width.
  final double width;

  /// Logical window height.
  final double height;

  /// Whether the window was maximized. When true the restorer maximizes and
  /// ignores [left]/[top]/[width]/[height] (which hold the pre-maximize
  /// "restore" geometry the OS will return to on un-maximize).
  final bool maximized;

  /// Whether a concrete on-screen position is known.
  bool get hasPosition => left != null && top != null;

  /// Serializes to a JSON-compatible map. Null position fields are omitted.
  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    if (left != null) 'left': left,
    if (top != null) 'top': top,
    if (maximized) 'maximized': true,
  };

  /// Returns a copy clamped to a restorable geometry, or null if the snapshot
  /// is unusable.
  ///
  /// * Size is floored to [minWidth] × [minHeight] (matching the window's
  ///   enforced minimum) and capped to [maxExtent] to reject absurd values.
  /// * A position that lands the top-left corner implausibly far off-screen is
  ///   dropped (set to null) so the window manager centers a sane window
  ///   instead of restoring it invisibly off the desktop — the common failure
  ///   after a monitor is unplugged or the resolution changes. [left] may be
  ///   slightly negative (a window nudged past the left edge is still grabbable
  ///   by its title bar), bounded by [minLeft].
  WindowBounds? sanitizedForRestore({
    double minWidth = 800,
    double minHeight = 500,
    double maxExtent = 20000,
    double minLeft = -64,
  }) {
    if (!width.isFinite || !height.isFinite) return null;
    final w = width.clamp(minWidth, maxExtent);
    final h = height.clamp(minHeight, maxExtent);
    final keepPosition =
        hasPosition &&
        left! >= minLeft &&
        left! < maxExtent &&
        top! >= 0 &&
        top! < maxExtent;
    return WindowBounds(
      width: w,
      height: h,
      left: keepPosition ? left : null,
      top: keepPosition ? top : null,
      maximized: maximized,
    );
  }

  /// Returns a copy fitted to the connected [displays], so the restored
  /// window is entirely on one display's work area. When [displays] is empty
  /// (they could not be read), falls back to [sanitizedForRestore].
  ///
  /// * **Which display.** With a known position, the display whose work area
  ///   overlaps the saved window most. When none overlaps (the display it was
  ///   saved on is gone) or there is no position, the primary display (the
  ///   one flagged [DisplayWorkArea.primary], or else the first).
  /// * **Size.** Floored to [minWidth] × [minHeight] like
  ///   [sanitizedForRestore], then reduced to fit that display's work area.
  /// * **Position.** Moved the least distance that puts the whole window on
  ///   the work area. A window that had no position, or whose display is
  ///   gone, is centred on the primary display's work area instead.
  ///
  /// **Coordinates.** Each work area is in its own display's logical pixels,
  /// which [DisplayWorkArea.scaleFactor] turns into the physical pixels all
  /// displays share; [windowScale] does the same for this window's
  /// coordinates. That is how Windows reports both: each display in its own
  /// scale, and the window in the scale of the display it currently sits on.
  /// Where the desktop is already one logical space (GTK on Linux), every
  /// scale is 1. The fitted size stays in the target display's logical
  /// pixels, which is the size the window keeps once it has moved there.
  ///
  /// [maximized] is kept. The rectangle is still fitted, so a maximized
  /// window maximizes on the display it was saved on and un-maximizes on
  /// screen.
  ///
  /// A display with a non-finite or empty work area is ignored. Returns null
  /// only for a snapshot whose own size is unusable.
  WindowBounds? fittedToDisplays(
    List<DisplayWorkArea> displays, {
    double windowScale = 1,
    double minWidth = 800,
    double minHeight = 500,
  }) {
    final usable = [
      for (final d in displays)
        if (d.left.isFinite &&
            d.top.isFinite &&
            d.width.isFinite &&
            d.height.isFinite &&
            d.width > 0 &&
            d.height > 0)
          d,
    ];
    if (usable.isEmpty) return sanitizedForRestore();
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return null;
    }
    final scale = _validScale(windowScale);
    DisplayWorkArea? target;
    if (hasPosition) {
      final l = left! * scale;
      final t = top! * scale;
      final r = l + width * scale;
      final b = t + height * scale;
      var best = 0.0;
      for (final display in usable) {
        final overlap = display._physicalOverlap(l, t, r, b);
        if (overlap > best) {
          best = overlap;
          target = display;
        }
      }
    }
    final centre = target == null;
    final area =
        target ??
        usable.firstWhere((d) => d.primary, orElse: () => usable.first);
    final w = width < minWidth ? minWidth : width;
    final h = height < minHeight ? minHeight : height;
    final fittedWidth = w > area.width ? area.width : w;
    final fittedHeight = h > area.height ? area.height : h;
    final areaScale = _validScale(area.scaleFactor);
    final areaLeft = area.left * areaScale;
    final areaTop = area.top * areaScale;
    final physicalWidth = fittedWidth * areaScale;
    final physicalHeight = fittedHeight * areaScale;
    // Never below the near edge: a window exactly as wide as the work area
    // can round to a hair wider, and clamp() rejects an inverted range.
    final maxLeft = math.max(
      areaLeft,
      areaLeft + area.width * areaScale - physicalWidth,
    );
    final maxTop = math.max(
      areaTop,
      areaTop + area.height * areaScale - physicalHeight,
    );
    final double physicalLeft;
    final double physicalTop;
    if (centre) {
      physicalLeft = areaLeft + (maxLeft - areaLeft) / 2;
      physicalTop = areaTop + (maxTop - areaTop) / 2;
    } else {
      physicalLeft = (left! * scale).clamp(areaLeft, maxLeft);
      physicalTop = (top! * scale).clamp(areaTop, maxTop);
    }
    return WindowBounds(
      left: physicalLeft / scale,
      top: physicalTop / scale,
      width: fittedWidth,
      height: fittedHeight,
      maximized: maximized,
    );
  }

  /// Returns a copy with the given fields replaced.
  WindowBounds copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
    bool? maximized,
  }) => WindowBounds(
    left: left ?? this.left,
    top: top ?? this.top,
    width: width ?? this.width,
    height: height ?? this.height,
    maximized: maximized ?? this.maximized,
  );

  static double? _finiteDouble(Object? raw) {
    if (raw is num) {
      final d = raw.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowBounds &&
          runtimeType == other.runtimeType &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height &&
          maximized == other.maximized;

  @override
  int get hashCode => Object.hash(left, top, width, height, maximized);

  @override
  String toString() =>
      'WindowBounds(left: $left, top: $top, width: $width, height: $height, '
      'maximized: $maximized)';
}

/// One connected display's work area: the part of the screen a window may
/// cover, without the taskbar, dock or panels. The input to
/// [WindowBounds.fittedToDisplays].
///
/// [left], [top], [width] and [height] are in this display's logical pixels,
/// as the platform reports them; [scaleFactor] is the display's device pixel
/// ratio, which turns them into physical pixels. Pure Dart, so the fitting
/// logic is unit-testable without a binding or a real display.
@immutable
class DisplayWorkArea {
  /// Creates a work area. A non-positive or non-finite [scaleFactor] is
  /// treated as 1.
  const DisplayWorkArea({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.scaleFactor = 1,
    this.primary = false,
  });

  /// Logical x-coordinate of the work area's left edge.
  final double left;

  /// Logical y-coordinate of the work area's top edge.
  final double top;

  /// Logical width of the work area.
  final double width;

  /// Logical height of the work area.
  final double height;

  /// The display's device pixel ratio (1.75 at 175% scaling).
  final double scaleFactor;

  /// Whether this is the primary display, where a window with nowhere else
  /// to go is centred.
  final bool primary;

  /// The area, in physical pixels squared, that this work area shares with
  /// the physical rectangle [l], [t], [r], [b].
  double _physicalOverlap(double l, double t, double r, double b) {
    final s = _validScale(scaleFactor);
    final x0 = left * s;
    final y0 = top * s;
    final x1 = x0 + width * s;
    final y1 = y0 + height * s;
    final w = (r < x1 ? r : x1) - (l > x0 ? l : x0);
    final h = (b < y1 ? b : y1) - (t > y0 ? t : y0);
    return w > 0 && h > 0 ? w * h : 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayWorkArea &&
          left == other.left &&
          top == other.top &&
          width == other.width &&
          height == other.height &&
          scaleFactor == other.scaleFactor &&
          primary == other.primary;

  @override
  int get hashCode =>
      Object.hash(left, top, width, height, scaleFactor, primary);

  @override
  String toString() =>
      'DisplayWorkArea(left: $left, top: $top, width: $width, '
      'height: $height, scaleFactor: $scaleFactor, primary: $primary)';
}

double _validScale(double scale) => scale.isFinite && scale > 0 ? scale : 1;
