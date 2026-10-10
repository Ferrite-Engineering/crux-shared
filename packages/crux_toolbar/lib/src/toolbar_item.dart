// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// One entry in a `CruxToolbar` strip.
///
/// Generic over the product's action enum so a product supplies its own
/// `ShortcutAction` / `NetcruxAction` / … without this package knowing them.
/// Rendered by `CruxToolbar`.
@immutable
sealed class CruxToolbarItem<A extends Object> {
  const CruxToolbarItem();
}

/// A plain icon button bound to one action.
@immutable
final class CruxToolbarButtonItem<A extends Object> extends CruxToolbarItem<A> {
  /// Creates a toolbar button.
  const CruxToolbarButtonItem({
    required this.action,
    required this.icon,
    required this.tooltip,
    this.selectedIcon,
    this.isSelected = false,
    this.tintWhenSelected = true,
    this.badgeCount = 0,
  });

  /// The action this button dispatches. Also becomes the button's `ValueKey`
  /// so conformance tests can find it by action rather than by glyph.
  final A action;

  /// The glyph shown in the unselected (or only) state.
  final IconData icon;

  /// The button's label. Rendered as its tooltip, with the user's live
  /// binding appended by `cruxToolbarTooltip`.
  final String tooltip;

  /// The glyph shown while [isSelected]. When null, [icon] is used for both.
  ///
  /// Toggle buttons across the suite use the filled/outlined pair — e.g.
  /// `Icons.sensors` when a panel is open, `Icons.sensors_outlined` when it
  /// is closed.
  final IconData? selectedIcon;

  /// Whether the button is in its "on" state.
  final bool isSelected;

  /// Whether the selected state also tints the glyph: with the theme's
  /// `toolbar.iconActive` chrome token when it sets one, otherwise with the
  /// primary colour.
  ///
  /// Defaults to true so a toggled-on button is legible at a glance. Three of
  /// the four products previously disagreed about this for the very same
  /// cross-probe button.
  final bool tintWhenSelected;

  /// A count rendered as a `Badge` on the button. Zero hides the badge.
  ///
  /// Used for the cross-probe peer count and the violation / failing-test
  /// counts, so the number is legible without opening the panel.
  final int badgeCount;
}

/// A Photoshop-style grouped tool button: one face, several related actions.
///
/// Tapping fires the currently-faced variant; long-press (or right-click, or
/// tapping the corner triangle) opens the sibling menu, and the chosen variant
/// becomes the new face.
@immutable
final class CruxToolbarSplitItem<A extends Object> extends CruxToolbarItem<A> {
  /// Creates a split button over [variants], which must be non-empty.
  const CruxToolbarSplitItem({
    required this.id,
    required this.variants,
    required this.tooltip,
    this.faceTooltip,
  });

  /// Stable identifier for this cluster, used as the widget key and as the
  /// key under which the host persists the last-used variant.
  final String id;

  /// The related actions, in menu order. The first is the initial face.
  final List<CruxToolbarButtonItem<A>> variants;

  /// Tooltip for the cluster as a whole, shown on the corner affordance.
  final String tooltip;

  /// The button's hover tooltip, given the action currently on its face.
  ///
  /// The face stands for the whole cluster, so the tooltip should name the
  /// cluster, and say what a plain click does: it runs the faced action,
  /// which changes when the user picks another variant from the menu. For
  /// example "Export Violations… (SARIF is default)", then
  /// "(JSON is default)" after JSON was picked. The faced action's shortcut
  /// is appended as for any toolbar button.
  ///
  /// Null keeps the faced variant's own tooltip.
  final String Function(A facedAction)? faceTooltip;
}

/// A host-supplied widget dropped into the strip verbatim.
///
/// For things that are not action buttons — WaveCrux's LIVE streaming badge,
/// the Pro extension contributions, a morphing run/stop control.
@immutable
final class CruxToolbarWidgetItem<A extends Object> extends CruxToolbarItem<A> {
  /// Creates a passthrough item.
  const CruxToolbarWidgetItem({required this.child, this.id});

  /// The widget to render.
  final Widget child;

  /// Optional stable id, used as the widget key.
  final String? id;
}

/// A logical separator between two groups of items.
@immutable
final class CruxToolbarSeparatorItem<A extends Object>
    extends CruxToolbarItem<A> {
  /// Creates a separator.
  const CruxToolbarSeparatorItem();
}
