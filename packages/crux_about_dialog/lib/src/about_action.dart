// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// A single action button rendered in the `CruxAboutDialog` action row.
///
/// The host builds the ordered list of actions it wants (Visit Website,
/// Documentation, Report Issue, Copy Version Info, Acknowledgments, …) so the
/// dialog stays agnostic about which buttons a given product shows.
///
/// [onTap] receives the dialog's own [BuildContext] when invoked, not a
/// context captured at construction time. This matters for actions that show a
/// snackbar or push a route (Copy Version Info, Acknowledgments): they attach
/// to the live dialog subtree's `ScaffoldMessenger` / `Navigator` rather than
/// a stale ancestor. A null [onTap] renders the button disabled.
@immutable
class AboutAction {
  /// Creates an action button. Pass a null [onTap] to render it disabled
  /// (e.g. Copy Version Info while build info is still loading).
  const AboutAction({
    required this.label,
    required this.icon,
    this.onTap,
  });

  /// Localized button label.
  final String label;

  /// Leading icon shown before the label.
  final IconData icon;

  /// Invoked with the dialog's live [BuildContext] on tap. Null = disabled.
  final void Function(BuildContext context)? onTap;

  /// Whether the button is interactive.
  bool get enabled => onTap != null;
}
