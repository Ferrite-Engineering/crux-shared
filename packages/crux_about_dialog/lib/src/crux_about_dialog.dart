// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_about_dialog/src/about_action.dart';
import 'package:crux_about_dialog/src/about_attribution_section.dart';
import 'package:crux_about_dialog/src/about_strings.dart';
import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The cross-suite About dialog / screen.
///
/// One implementation rendered by every product in the suite. The product
/// supplies its branding, build
/// metadata, edition label, localized chrome strings, an app icon, optional
/// third-party [AboutAttributionSection]s, and the ordered list of
/// [AboutAction] buttons. Tier and beta-period state are read from
/// `crux_license` providers internally, so the embedded EDU badge and the
/// "Public Beta" chip stay consistent across the suite without per-app wiring.
///
/// Call [show] from any context — it presents as a modal dialog on desktop and
/// as a pushed full-screen route on mobile.
class CruxAboutDialog extends StatelessWidget {
  /// Creates the About dialog content. Prefer [show] over constructing and
  /// presenting this manually so the adaptive desktop/mobile branch is applied.
  const CruxAboutDialog({
    required this.title,
    required this.tagline,
    required this.companyTagline,
    required this.appIcon,
    required this.branding,
    required this.buildInfo,
    required this.editionLabel,
    required this.strings,
    required this.actions,
    this.attributions = const [],
    this.betaChipVisible,
    super.key,
  });

  /// Dialog title (e.g. "About WaveCrux"). Shown in the app bar / header row.
  final String title;

  /// One-line product tagline shown under the app name in the header.
  final String tagline;

  /// Company tagline shown on the first line of the branding banner (typically
  /// the company name as a localized string).
  final String companyTagline;

  /// The product's app icon widget, rendered ~80dp at the top of the header.
  final Widget appIcon;

  /// Company branding (name, logo asset, copyright year, website URL).
  final ApplicationBranding branding;

  /// Build metadata, kept as an [AsyncValue] so the version section shows a
  /// spinner while it resolves and hides on error, matching the host provider.
  final AsyncValue<ApplicationBuildInfo> buildInfo;

  /// User-visible edition label (e.g. "Pro", "Enterprise"). Pass an empty
  /// string to hide the edition chip (e.g. for the open-core edition).
  final String editionLabel;

  /// Localized chrome strings (section headers, info-row labels, beta chip).
  final CruxAboutStrings strings;

  /// Ordered action buttons rendered below the body. The host builds these.
  final List<AboutAction> actions;

  /// Optional third-party attribution sections rendered between the version
  /// section and the action buttons.
  final List<AboutAttributionSection> attributions;

  /// Overrides whether the "Public Beta" chip renders.
  ///
  /// `null` (the default) keeps the suite-wide behavior: the chip follows
  /// `betaPeriodProvider`, so every product in public beta advertises it.
  ///
  /// A host passes `false` when the build is in the beta period but is not
  /// *distributed* as a beta. That is not hypothetical: consumer app stores
  /// forbid shipping trial or pre-release software, and Apple rejected
  /// WaveCrux 0.1.0 (2) under App Store Review Guideline 2.2 with the About
  /// screen's "Public Beta" chip among the signals. The desktop build of the
  /// same product is a genuine public beta and keeps the chip, so this is a
  /// per-distribution-channel decision the host owns — not something
  /// `crux_license` can infer.
  final bool? betaChipVisible;

  /// Whether the session is desktop-shaped (drives dialog vs pushed route).
  ///
  /// Includes web on a desktop browser: `defaultTargetPlatform` reports the
  /// HOST OS on web, so a desktop-browser session presents as a modal dialog
  /// (matching every other desktop modal in the suite — the old `!kIsWeb`
  /// exclusion gave wide desktop browsers the mobile full-screen slide-in),
  /// while a phone/tablet browser (iOS/Android host) keeps the pushed route.
  static bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  /// Presents the About box: a modal dialog on desktop, a pushed full-screen
  /// route on mobile.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String tagline,
    required String companyTagline,
    required Widget appIcon,
    required ApplicationBranding branding,
    required AsyncValue<ApplicationBuildInfo> buildInfo,
    required String editionLabel,
    required CruxAboutStrings strings,
    required List<AboutAction> actions,
    List<AboutAttributionSection> attributions = const [],
    bool? betaChipVisible,
  }) async {
    final dialog = CruxAboutDialog(
      title: title,
      tagline: tagline,
      companyTagline: companyTagline,
      appIcon: appIcon,
      branding: branding,
      buildInfo: buildInfo,
      editionLabel: editionLabel,
      strings: strings,
      actions: actions,
      attributions: attributions,
      betaChipVisible: betaChipVisible,
    );
    if (_isDesktopPlatform) {
      await showDialog<void>(
        context: context,
        builder: (_) => _AboutDialogShell(dialog: dialog),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => dialog),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mobile route form: full-screen scaffold.
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).closeButtonLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _AboutScrollBody(dialog: this)),
          _AboutBrandingBanner(dialog: this),
        ],
      ),
    );
  }
}

// ── Desktop dialog shell ─────────────────────────────────────────────────────

class _AboutDialogShell extends StatelessWidget {
  const _AboutDialogShell({required this.dialog});

  final CruxAboutDialog dialog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        height: 660,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Text(dialog.title, style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _AboutScrollBody(dialog: dialog)),
            _AboutBrandingBanner(dialog: dialog),
          ],
        ),
      ),
    );
  }
}

// ── Main scrollable body ─────────────────────────────────────────────────────

class _AboutScrollBody extends StatefulWidget {
  const _AboutScrollBody({required this.dialog});

  final CruxAboutDialog dialog;

  @override
  State<_AboutScrollBody> createState() => _AboutScrollBodyState();
}

class _AboutScrollBodyState extends State<_AboutScrollBody> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialog = widget.dialog;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              _AboutHeader(dialog: dialog),
              const SizedBox(height: 24),
              _AboutVersionSection(dialog: dialog),
              const SizedBox(height: 16),
              for (final attribution in dialog.attributions) ...[
                attribution,
                const SizedBox(height: 16),
              ],
              _AboutActionButtons(actions: dialog.actions),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _AboutHeader extends ConsumerWidget {
  const _AboutHeader({required this.dialog});

  final CruxAboutDialog dialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The host may suppress the chip for a distribution channel that forbids
    // pre-release software (app stores) while the product is still in beta
    // elsewhere — see [CruxAboutDialog.betaChipVisible].
    final betaOverride = dialog.betaChipVisible;
    // Deliberately `?:` and not `??`. With `betaOverride ?? ref.watch(...)`,
    // the left operand's `bool?` becomes the context type for the right, so
    // `ref.watch<T>` infers `T = bool?` (ProviderListenable is covariant) and
    // the whole expression is `bool?` rather than `bool`. The conditional
    // keeps each branch inferring independently.
    // ignore: prefer_if_null_operators
    final betaActive = betaOverride == null
        ? ref.watch(betaPeriodProvider)
        : betaOverride;

    return Column(
      children: [
        dialog.appIcon,
        const SizedBox(height: 12),
        Text(
          dialog.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          dialog.tagline,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            if (betaActive) _BetaChip(label: dialog.strings.betaChip),
            if (dialog.editionLabel.isNotEmpty)
              _EditionChip(label: dialog.editionLabel),
            // States the edition in force: EDU, PRO or ENT, and nothing at
            // open core. It reads licenseTierProvider itself, which is why no
            // tier is passed.
            EditionBadge(strings: dialog.strings.licenseBadgeStrings),
          ],
        ),
      ],
    );
  }
}

class _BetaChip extends StatelessWidget {
  const _BetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onErrorContainer,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EditionChip extends StatelessWidget {
  const _EditionChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Version / build info section ─────────────────────────────────────────────

class _AboutVersionSection extends StatelessWidget {
  const _AboutVersionSection({required this.dialog});

  final CruxAboutDialog dialog;

  @override
  Widget build(BuildContext context) {
    final strings = dialog.strings;
    return Align(
      alignment: Alignment.centerLeft,
      child: dialog.buildInfo.when(
        data: (info) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AboutSectionHeader(label: strings.sectionVersion),
            const SizedBox(height: 6),
            _InfoRow(label: strings.sectionVersion, value: info.version),
            _InfoRow(label: strings.buildNumberLabel, value: info.buildNumber),
            _InfoRow(label: strings.gitShaLabel, value: info.gitShortSha),
            const SizedBox(height: 10),
            AboutSectionHeader(label: strings.sectionPlatform),
            const SizedBox(height: 6),
            _InfoRow(label: strings.operatingSystemLabel, value: info.os),
            _InfoRow(
              label: strings.architectureLabel,
              value: info.architecture,
            ),
            _InfoRow(
              label: strings.flutterVersionLabel,
              value: info.flutterSdkVersion,
            ),
            _InfoRow(
              label: strings.dartVersionLabel,
              value: info.dartSdkVersion,
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action buttons ───────────────────────────────────────────────────────────

class _AboutActionButtons extends StatelessWidget {
  const _AboutActionButtons({required this.actions});

  final List<AboutAction> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final action in actions)
          OutlinedButton.icon(
            onPressed: action.onTap == null
                ? null
                : () => action.onTap!(context),
            icon: Icon(action.icon, size: 16),
            label: Text(action.label),
            style: OutlinedButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
      ],
    );
  }
}

// ── Branding banner ──────────────────────────────────────────────────────────

class _AboutBrandingBanner extends StatelessWidget {
  const _AboutBrandingBanner({required this.dialog});

  final CruxAboutDialog dialog;

  @override
  Widget build(BuildContext context) {
    final branding = dialog.branding;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: const Color(0xFF0A1220),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            branding.squareLogoAssetPath,
            height: 40,
            errorBuilder: (_, _, _) => const SizedBox(width: 40, height: 40),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dialog.companyTagline,
                  style: const TextStyle(
                    color: Color(0xFFE0E8FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '© ${branding.copyrightYear} ${branding.companyName}',
                  style: const TextStyle(
                    color: Color(0xFF8898BB),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds the structured, copy-to-clipboard version paragraph shown in bug
/// reports. Hosts wire this into their "Copy Version Info" [AboutAction].
///
/// The line format is stable across releases and identical in every product,
/// so bug-report tooling can parse it.
String aboutVersionInfoText({
  required String appName,
  required String editionLabel,
  required ApplicationBuildInfo info,
}) {
  return [
    '$appName ${info.version} (build ${info.buildNumber})',
    if (editionLabel.isNotEmpty) 'Edition: $editionLabel',
    'Git SHA: ${info.gitShortSha}',
    'OS: ${info.os}',
    'Architecture: ${info.architecture}',
    'Flutter: ${info.flutterSdkVersion}',
    'Dart: ${info.dartSdkVersion}',
  ].join('\n');
}
