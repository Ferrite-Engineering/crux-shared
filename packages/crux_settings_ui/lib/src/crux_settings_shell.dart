// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Opens the suite's Settings surface with the shared chrome: a modal
/// dialog on desktop, a pushed full-screen route on mobile.
///
/// Every Crux app used to hand-roll this shell — three different dialog
/// size clamps (860×620 / 680×600 / 880×640), a fourth app on a generic
/// dialog helper with no clamp at all, and two different mobile close
/// affordances. This is the one implementation: the WaveCrux-canonical
/// 860×620 clamp with a 48 dp viewport gutter, a `titleLarge` header row
/// with a close ×, a non-dismissible barrier (closing Settings must be a
/// deliberate act — a stray scrim click discarding an open pane surprised
/// users in live testing), and an `arrow_back`-leading app bar on mobile.
///
/// [bodyBuilder] returns the app's settings body (typically a
/// `CruxSettingsMasterDetail` over its category list). All user-visible
/// strings arrive localized from the host ([title], [closeTooltip]).
/// [wrap] optionally wraps the shell widget (LintCrux re-parents it into
/// the active tab's provider scope).
Future<void> openCruxSettings(
  BuildContext context, {
  required String title,
  required String closeTooltip,
  required WidgetBuilder bodyBuilder,
  required bool asDialog,
  Widget Function(BuildContext context, Widget shell)? wrap,
}) async {
  Widget shellOf(BuildContext ctx, Widget shell) =>
      wrap == null ? shell : wrap(ctx, shell);

  if (asDialog) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => shellOf(
        ctx,
        CruxSettingsDialogShell(
          title: title,
          closeTooltip: closeTooltip,
          body: bodyBuilder(ctx),
        ),
      ),
    );
  } else {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => shellOf(
          ctx,
          CruxSettingsRouteShell(
            title: title,
            closeTooltip: closeTooltip,
            body: bodyBuilder(ctx),
          ),
        ),
      ),
    );
  }
}

/// The desktop presentation: a size-clamped [Dialog] with a title row,
/// close ×, divider, and the settings [body] below.
class CruxSettingsDialogShell extends StatelessWidget {
  /// Creates the dialog shell.
  const CruxSettingsDialogShell({
    required this.title,
    required this.closeTooltip,
    required this.body,
    super.key,
  });

  /// Localized dialog title.
  final String title;

  /// Localized tooltip for the close button.
  final String closeTooltip;

  /// The settings body (typically a `CruxSettingsMasterDetail`).
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The dialog shrinks to fit the available viewport with a 48 dp gutter
    // on every side (iPad split view, narrow desktop windows), and is wide
    // enough for the category rail + detail pane to sit side by side.
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = math.min<double>(860, screen.width - 48);
    final dialogHeight = math.min<double>(620, screen.height - 48);

    // Escape closes Settings even though the barrier is not dismissible.
    // The route's own dismiss action is disabled whenever the barrier is,
    // and a disabled action found first ends the Escape lookup, so this
    // enabled one has to sit between the route and the focused control.
    return Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) => Navigator.of(context).maybePop(),
        ),
      },
      child: Dialog(
        // The desktop bridges have no dialog role, so the title is the only
        // way a screen reader can say where focus went when Settings opens.
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: title,
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Text(title, style: theme.textTheme.titleLarge),
                      ),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey('cruxSettingsClose'),
                        icon: const Icon(Icons.close),
                        tooltip: closeTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mobile presentation: a full-screen scaffold with an
/// `arrow_back`-leading app bar.
class CruxSettingsRouteShell extends StatelessWidget {
  /// Creates the route shell.
  const CruxSettingsRouteShell({
    required this.title,
    required this.closeTooltip,
    required this.body,
    super.key,
  });

  /// Localized page title.
  final String title;

  /// Localized tooltip for the back button.
  final String closeTooltip;

  /// The settings body (typically a `CruxSettingsMasterDetail`).
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: closeTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: body,
    );
  }
}
