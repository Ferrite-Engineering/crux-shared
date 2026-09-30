// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:panes/panes.dart' show PaneSize;

/// Read side of the IDE-layout adapter: the visibility + size of each dockable
/// region, as `CruxIdeLayout` needs them to build and sync the underlying
/// `IdeController`.
///
/// Each app supplies an implementation that projects its own
/// `PanelLayoutState` onto these three regions (left / right / bottom). The
/// center pane is always present and has no visibility flag. Sizes are
/// returned as [PaneSize] so the app — not the shared widget — decides pixel
/// vs. fraction units (WaveCrux uses pixels; other consumers may use
/// fractions). A null size lets `IdeController` fall back to its default
/// initial size for that region.
///
/// WaveCrux's adapter additionally folds in its phone-width force-hide here
/// (returning `preference && !isPhone`), keeping that device-class policy in
/// the app rather than the shared widget.
abstract class IdePanelLayout {
  /// Whether the left region is currently visible.
  bool get leftVisible;

  /// Initial/persisted size of the left region, or null for the default.
  PaneSize? get leftSize;

  /// Whether the right region is currently visible.
  bool get rightVisible;

  /// Initial/persisted size of the right region, or null for the default.
  PaneSize? get rightSize;

  /// Whether the bottom region is currently visible.
  bool get bottomVisible;

  /// Initial/persisted size of the bottom region, or null for the default.
  PaneSize? get bottomSize;
}

/// Write side of the IDE-layout adapter: where `CruxIdeLayout` feeds
/// drag-to-collapse and drag-to-resize gestures back so the app can persist
/// them.
///
/// Visibility setters mirror the user dragging a pane closed/open. Size
/// setters receive the new pixel extent from the `panes` resize gesture; an
/// app that stores fractions converts in its implementation, and an app that
/// does not persist drag-resize at all leaves the size
/// setters as no-ops.
abstract class IdePanelLayoutSink {
  /// Persists the left region's visibility.
  void setLeftVisible({required bool visible});

  /// Persists the right region's visibility.
  void setRightVisible({required bool visible});

  /// Persists the bottom region's visibility.
  void setBottomVisible({required bool visible});

  /// Persists the left region's new size, in pixels.
  void setLeftSize(double pixels);

  /// Persists the right region's new size, in pixels.
  void setRightSize(double pixels);

  /// Persists the bottom region's new size, in pixels.
  void setBottomSize(double pixels);
}
