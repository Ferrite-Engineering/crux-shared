// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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
