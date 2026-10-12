// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_license/src/widgets/beta_expiry_banner.dart';
import 'package:flutter/material.dart';

/// Localized strings consumed by [CruxBetaExpiredOverlay].
///
/// Every product already owns ARB keys for all four (they were the strings
/// of each product's own copy of this overlay), so adopting this is a
/// re-binding, not a translation job. [CruxBetaExpiredStringsEn] exists for
/// tests and demos.
@immutable
abstract class CruxBetaExpiredStrings {
  /// Const constructor for subclasses.
  const CruxBetaExpiredStrings();

  /// The dialog's title, and its accessible name.
  String get title;

  /// The explanation under the title.
  String get body;

  /// Label of the primary action, which opens the download page.
  String get downloadLabel;

  /// Label of the action that quits the application.
  String get quitLabel;
}

/// English-only [CruxBetaExpiredStrings] for tests, demos and prototypes.
@immutable
class CruxBetaExpiredStringsEn extends CruxBetaExpiredStrings {
  /// Creates the English default strings.
  const CruxBetaExpiredStringsEn();

  @override
  String get title => 'This beta build has expired';

  @override
  String get body => 'Download the latest build to continue.';

  @override
  String get downloadLabel => 'Download latest build';

  @override
  String get quitLabel => 'Quit';
}

/// The blocking modal shown over the routed app content once a public-beta
/// build has reached its hard expiry date (`BetaExpiryStatus.expired`).
///
/// While [blocking] is true the app behind is covered by a non-dismissable
/// barrier and taken out of focus and semantics through `crux_a11y`'s
/// [CruxModalGate], and the dialog sits in a [CruxModalSurface]: announced by
/// its title, Tab and Shift+Tab kept inside it, Escape consumed. The download
/// action takes focus when the dialog opens, so a keyboard or screen-reader
/// user starts on it. A bare `Stack` and `ModalBarrier`, which each product
/// had, stopped only the pointer: focus stayed on the hidden app, Tab walked
/// controls nobody could see, and Enter could press one.
///
/// The system back gesture cannot dismiss it either. The quit action is
/// load-bearing on Windows and Linux: those platforms draw custom window
/// chrome, so the in-app close button sits behind the barrier, and without
/// it the modal would leave no visible way out.
///
/// A dumb leaf widget: the hosting product's beta-expiry gate owns the status
/// provider, the URL launch and the app exit. With [blocking] false it
/// renders [child] untouched, and [child] keeps its element and state across
/// both transitions, so a gate can keep this widget mounted and flip the
/// flag.
class CruxBetaExpiredOverlay extends StatelessWidget {
  /// Creates the blocking beta-expiry modal over [child].
  const CruxBetaExpiredOverlay({
    required this.child,
    required this.onDownload,
    required this.onQuit,
    this.blocking = true,
    this.strings = const CruxBetaExpiredStringsEn(),
    this.sizing = const CruxBetaExpirySizing(),
    super.key,
  });

  /// Widget key of the download action.
  static const Key downloadButtonKey = Key('cruxBetaExpiredDownload');

  /// Widget key of the quit action.
  static const Key quitButtonKey = Key('cruxBetaExpiredQuit');

  /// Widget key of the dialog card.
  static const Key dialogKey = Key('cruxBetaExpiredDialog');

  /// The routed app content, dimmed and unreachable behind the modal.
  final Widget child;

  /// Invoked when the user activates the download action.
  final VoidCallback onDownload;

  /// Invoked when the user activates the quit action.
  final VoidCallback onQuit;

  /// Whether the modal is shown. False renders [child] alone.
  final bool blocking;

  /// Localized strings. Defaults to English for tests and demos.
  final CruxBetaExpiredStrings strings;

  /// Sizing overrides, shared with `CruxBetaExpiryBanner` so the two
  /// beta-expiry surfaces cannot drift apart. Defaults to the desktop values.
  final CruxBetaExpirySizing sizing;

  @override
  Widget build(BuildContext context) => CruxModalGate(
    modal: blocking ? _modal(context) : null,
    child: child,
  );

  Widget _modal(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          CruxModalSurface(
            label: strings.title,
            child: Center(
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    key: dialogKey,
                    // The surface names the dialog; a semantic container here
                    // would gather the prose into one unnamed node around
                    // both buttons.
                    semanticContainer: false,
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              Icons.hourglass_disabled_outlined,
                              size: sizing.iconSize * 2,
                              color: scheme.error,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            strings.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: sizing.bodyTextSize,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: sizing.touchTarget,
                            child: FilledButton.icon(
                              key: downloadButtonKey,
                              autofocus: true,
                              onPressed: onDownload,
                              icon: const Icon(Icons.download_outlined),
                              label: Text(strings.downloadLabel),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: sizing.touchTarget,
                            child: TextButton(
                              key: quitButtonKey,
                              onPressed: onQuit,
                              child: Text(strings.quitLabel),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
