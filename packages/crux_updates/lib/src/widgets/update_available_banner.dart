// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/crux_update_strings.dart';
import 'package:crux_updates/src/widgets/update_banner_metrics.dart';
import 'package:flutter/material.dart';

/// Non-intrusive "an update is available" strip rendered above the routed app
/// content when `updateStatusProvider` reports an available version.
///
/// A dumb leaf widget: it takes the version string, the mandatory flag, the
/// localized [strings], the host [metrics], and the action callbacks, and
/// renders the strip. The hosting `UpdateBanner` owns the status provider, the
/// dismissal state, and the URL launches — so this widget stays trivially
/// testable without providers or platform channels.
///
/// When [mandatory] is `true` the [onDismiss] affordance is omitted, making the
/// strip non-dismissible (a forced update for a critical fix, or a build below
/// the manifest's min-supported floor). [onViewChanges] is omitted (the button
/// hidden) when no changelog URL is available.
class UpdateAvailableBanner extends StatelessWidget {
  /// Creates the update-available strip.
  const UpdateAvailableBanner({
    required this.version,
    required this.mandatory,
    required this.strings,
    required this.onUpdateNow,
    this.metrics = const CruxUpdateBannerMetrics(),
    this.onViewChanges,
    this.onDismiss,
    super.key,
  });

  /// The available version string, rendered into the banner message.
  final String version;

  /// Whether the update is forced (no dismiss affordance is shown).
  final bool mandatory;

  /// Localized labels for the message and the three actions.
  final CruxUpdateStrings strings;

  /// Host-supplied touch-target, icon and font sizing.
  final CruxUpdateBannerMetrics metrics;

  /// Invoked when the user taps the "Update Now" action.
  final VoidCallback onUpdateNow;

  /// Invoked when the user taps the "View Changes" action. When `null` the
  /// button is hidden (no changelog URL was supplied).
  final VoidCallback? onViewChanges;

  /// Invoked when the user dismisses the strip. When `null` (including whenever
  /// [mandatory] is `true`) no dismiss affordance is shown.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showDismiss = !mandatory && onDismiss != null;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: scheme.onSecondaryContainer,
      minimumSize: Size(metrics.touchTarget, metrics.touchTarget),
    );

    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_outlined,
                size: metrics.iconSize,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.bannerMessage(version),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: metrics.bodyFontSize,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (onViewChanges != null)
                TextButton(
                  onPressed: onViewChanges,
                  style: buttonStyle,
                  child: Text(strings.viewChangesAction),
                ),
              TextButton(
                onPressed: onUpdateNow,
                style: buttonStyle,
                child: Text(strings.updateNowAction),
              ),
              // No Tooltip here: this strip renders *above* the app's Navigator
              // (a sibling of the routed content in `MaterialApp.builder`), so
              // the Navigator's Overlay is not an ancestor and a Tooltip would
              // throw "No Overlay widget found". The accessible name is carried
              // by Semantics instead.
              if (showDismiss)
                Semantics(
                  label: strings.dismissLabel,
                  button: true,
                  child: IconButton(
                    onPressed: onDismiss,
                    iconSize: metrics.iconSize,
                    color: scheme.onSecondaryContainer,
                    constraints: BoxConstraints(
                      minWidth: metrics.touchTarget,
                      minHeight: metrics.touchTarget,
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
