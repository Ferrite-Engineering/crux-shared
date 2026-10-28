// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_ide_layout/crux_ide_layout.dart' show showCruxDialog;
import 'package:crux_settings_ui/src/crux_settings_master_detail.dart';
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
/// [wrap] optionally wraps the shell widget.
///
/// [navigator], when given, is the navigator Settings is pushed on instead of
/// the root one: a product whose settings body reads a tab's providers passes
/// that tab's own nested navigator (crux_workspace's `CruxTabNavigators`), so
/// the body is built under the tab's provider scope and no second scope over
/// the tab's container is needed. The dialog then sizes itself to that
/// navigator's area.
///
/// [initialCategoryId], when given, is the category the body's
/// `CruxSettingsMasterDetail` opens on (through a
/// `CruxSettingsInitialCategory` above the shell) instead of the first.
Future<void> openCruxSettings(
  BuildContext context, {
  required String title,
  required String closeTooltip,
  required WidgetBuilder bodyBuilder,
  required bool asDialog,
  Widget Function(BuildContext context, Widget shell)? wrap,
  NavigatorState? navigator,
  String? initialCategoryId,
}) async {
  Widget shellOf(BuildContext ctx, Widget shell) {
    final opened = initialCategoryId == null
        ? shell
        : CruxSettingsInitialCategory(id: initialCategoryId, child: shell);
    return wrap == null ? opened : wrap(ctx, opened);
  }

  if (asDialog) {
    await showCruxDialog<void>(
      context: context,
      barrierDismissible: false,
      navigator: navigator,
      builder: (ctx) => shellOf(
        ctx,
        _CruxSettingsDialogShell(
          title: title,
          closeTooltip: closeTooltip,
          body: bodyBuilder(ctx),
        ),
      ),
    );
  } else {
    await (navigator ?? Navigator.of(context)).push<void>(
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
class _CruxSettingsDialogShell extends StatelessWidget {
  const _CruxSettingsDialogShell({
    required this.title,
    required this.closeTooltip,
    required this.body,
  });

  /// Localized dialog title.
  final String title;

  /// Localized tooltip for the close button.
  final String closeTooltip;

  /// The settings body (typically a `CruxSettingsMasterDetail`).
  final Widget body;

  @override
  Widget build(BuildContext context) {
    // The dialog shrinks to fit the space its route has with a 48 dp gutter
    // on every side (iPad split view, narrow desktop windows, a tab's area
    // when shown on a tab's navigator), and is wide enough for the category
    // rail + detail pane to sit side by side.
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : screen.width;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : screen.height;
        return _dialog(
          context,
          dialogWidth: math.min<double>(860, width - 48),
          dialogHeight: math.min<double>(620, height - 48),
        );
      },
    );
  }

  Widget _dialog(
    BuildContext context, {
    required double dialogWidth,
    required double dialogHeight,
  }) {
    final theme = Theme.of(context);

    // Escape closes Settings even though the barrier is not dismissible:
    // showCruxDialog puts an enabled dismiss action between the route and
    // the focused control.
    return Dialog(
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
