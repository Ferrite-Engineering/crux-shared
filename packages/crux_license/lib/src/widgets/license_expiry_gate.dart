// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart' show announceCrux;
import 'package:crux_license/src/license_expiry_notice.dart';
import 'package:crux_license/src/license_notice_memory.dart';
import 'package:crux_license/src/license_panel_providers.dart';
import 'package:crux_license/src/widgets/beta_expiry_banner.dart';
import 'package:crux_license/src/widgets/license_date_format.dart';
import 'package:crux_license/src/widgets/license_expiry_banner_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The strings the expiry banner renders, resolved from the context it is
/// built in.
///
/// Defaults to English. Each Pro overlay overrides it with an adapter over
/// its own ARB files, the way it hands `cruxLicenseSettingsCategory` the
/// panel's strings:
///
/// ```dart
/// licenseExpiryStringsProvider.overrideWithValue(
///   (context) => WaveCruxLicenseExpiryStrings(L10NPro.of(context)),
/// ),
/// ```
final licenseExpiryStringsProvider =
    Provider<CruxLicenseExpiryStrings Function(BuildContext context)>(
      (ref) =>
          (_) => const CruxLicenseExpiryStringsEn(),
      name: 'licenseExpiryStringsProvider',
    );

/// Which one-time licence notices this machine has shown.
///
/// Defaults to memory, which makes the drop-to-Open-Core notice once per
/// launch. Each Pro overlay overrides it with [FileLicenseNoticeMemory], the
/// file every product on the machine shares, which makes it once.
final licenseNoticeMemoryProvider = Provider<LicenseNoticeMemory>(
  (ref) => InMemoryLicenseNoticeMemory(),
  name: 'licenseNoticeMemoryProvider',
);

/// What a licence's term looks like from the main window: a non-blocking
/// strip above the app, wrapping [child].
///
/// Reads `licenseStatusProvider`, so it can be mounted in the open-core app
/// shell, where it shows nothing (Open Core has no licence), and lights up in
/// the Pro overlay build, which overrides the status:
///
/// - **Before expiry**, from [warningDays] before (an evaluation:
///   [evaluationWarningDays]): "Your Pro license expires on `date`".
/// - **During grace**: the same strip, worded as overdue, with the days of
///   grace left.
/// - **After grace**, or at an evaluation's end: one notice that the app now
///   runs as Open Core, why, and that importing a licence restores the tier
///   at once. Shown on the launch it happens and remembered through
///   [licenseNoticeMemoryProvider], so it is not repeated every launch.
/// - **Policy-deployed licences** (`licenseManagedByOrganizationProvider`)
///   point at the administrator instead of the purchase page.
///
/// Each strip has a button that opens Settings → License, through
/// [onOpenLicenseSettings], and can be dismissed for the session; a dismissed
/// strip comes back at the next launch. It never blocks work, never takes
/// focus, and is never modal. It is announced to a screen reader once, when
/// it appears, and not on every rebuild.
///
/// The day counts use `licenseClockProvider` and
/// `CruxLicenseStatus.graceDaysRemainingAt`, the same clock and computation
/// as the licence panel, so the two always agree. The notice is re-read when
/// the app resumes, so a countdown left open overnight moves on.
class CruxLicenseExpiryGate extends ConsumerStatefulWidget {
  /// Wraps [child] in the expiry strip.
  const CruxLicenseExpiryGate({
    required this.child,
    required this.onOpenLicenseSettings,
    this.warningDays = kLicenseExpiryWarningDays,
    this.evaluationWarningDays = kEvaluationExpiryWarningDays,
    this.sizing = const CruxBetaExpirySizing(),
    super.key,
  });

  /// The app content the strip sits above.
  final Widget child;

  /// Opens Settings at the License category. The host owns how Settings
  /// opens (a dialog on desktop, a route on a phone), so it supplies this,
  /// typically through `openCruxSettings(initialCategoryId:
  /// kCruxLicenseCategoryId)`.
  final VoidCallback onOpenLicenseSettings;

  /// Days before a paid licence's expiry at which the strip appears.
  final int warningDays;

  /// Days before an evaluation's end at which the strip appears.
  final int evaluationWarningDays;

  /// Icon, hit-area and text sizing, shared with the beta-expiry strip.
  final CruxBetaExpirySizing sizing;

  @override
  ConsumerState<CruxLicenseExpiryGate> createState() =>
      _CruxLicenseExpiryGateState();
}

class _CruxLicenseExpiryGateState extends ConsumerState<CruxLicenseExpiryGate>
    with WidgetsBindingObserver {
  /// Notices dismissed this session, by identity.
  final Set<String> _dismissed = <String>{};

  /// One-time notices decided this session: `true` shows it, `false` means it
  /// was shown on an earlier launch.
  final Map<String, bool> _oneTime = <String, bool>{};

  /// One-time notices whose memory lookup is in flight.
  final Set<String> _deciding = <String>{};

  /// The identity of the notice last announced, so a rebuild of the same
  /// notice is silent.
  String? _announced;

  static const Key _childKey = ValueKey<String>('cruxLicenseExpiryGateChild');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read the clock: a countdown left open overnight should move on.
    // Dismissals stand until the next launch, as the strip promises.
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _decideOneTime(String identity) {
    if (!_deciding.add(identity)) return;
    final memory = ref.read(licenseNoticeMemoryProvider);
    unawaited(() async {
      var shown = false;
      try {
        shown = await memory.wasShown(identity);
      } on Object {
        shown = false;
      }
      if (!shown) {
        try {
          await memory.markShown(identity);
        } on Object {
          // A notice not remembered is shown once more; see the memory.
        }
      }
      if (!mounted) return;
      setState(() {
        _deciding.remove(identity);
        _oneTime[identity] = !shown;
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseStatusProvider);
    final managed = ref.watch(licenseManagedByOrganizationProvider);
    final now = ref.watch(licenseClockProvider)();
    final notice = cruxLicenseExpiryNoticeFor(
      status,
      now: now,
      warningDays: widget.warningDays,
      evaluationWarningDays: widget.evaluationWarningDays,
    );

    var visible = notice != null && !_dismissed.contains(notice.identity);
    if (visible && notice.kind == CruxLicenseNoticeKind.ended) {
      final decided = _oneTime[notice.identity];
      if (decided == null) {
        _decideOneTime(notice.identity);
        visible = false;
      } else {
        visible = decided;
      }
    }

    Widget? banner;
    if (visible) {
      final strings = ref.watch(licenseExpiryStringsProvider)(context);
      final shown = notice!;
      final message = _message(shown, strings, managed: managed);
      final actions = ref.watch(licenseActionsProvider);
      final offerPurchase =
          !managed &&
          shown.evaluation &&
          shown.kind == CruxLicenseNoticeKind.ended &&
          actions.supportsPurchaseLinks;
      if (_announced != shown.identity) {
        _announced = shown.identity;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) announceCrux(context, message);
        });
      }
      banner = CruxLicenseExpiryBanner(
        message: message,
        urgent: shown.kind != CruxLicenseNoticeKind.expiringSoon,
        openSettingsLabel: strings.openSettingsAction,
        onOpenSettings: widget.onOpenLicenseSettings,
        buyLabel: offerPurchase ? strings.buyAction : null,
        onBuy: offerPurchase
            ? () => unawaited(actions.openPurchasePage())
            : null,
        dismissLabel: strings.dismissLabel,
        onDismiss: () => setState(() => _dismissed.add(shown.identity)),
        sizing: widget.sizing,
      );
    }

    // The child keeps its place whether or not the strip shows, so the
    // routed app underneath never loses its state when the strip comes or
    // goes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?banner,
        Expanded(key: _childKey, child: widget.child),
      ],
    );
  }

  static String _message(
    CruxLicenseExpiryNotice notice,
    CruxLicenseExpiryStrings strings, {
    required bool managed,
  }) {
    final tier = strings.tierName(notice.tier);
    final date = formatLicenseDate(notice.expiry);
    final days = notice.graceDaysRemaining ?? 0;
    if (managed) {
      return switch (notice.kind) {
        CruxLicenseNoticeKind.expiringSoon => strings.managedExpiringMessage(
          tier,
          date,
        ),
        CruxLicenseNoticeKind.inGrace => strings.managedGraceMessage(
          tier,
          date,
          days,
        ),
        CruxLicenseNoticeKind.ended => strings.managedEndedMessage(tier, date),
      };
    }
    if (notice.clockSetBack) return strings.evaluationClockMessage(tier);
    return switch (notice.kind) {
      CruxLicenseNoticeKind.expiringSoon =>
        notice.evaluation
            ? strings.evaluationEndingMessage(tier, date)
            : strings.expiringMessage(tier, date),
      CruxLicenseNoticeKind.inGrace => strings.graceMessage(tier, date, days),
      CruxLicenseNoticeKind.ended =>
        notice.evaluation
            ? strings.evaluationEndedMessage(tier, date)
            : strings.endedMessage(tier, date),
    };
  }
}

/// The strip itself: a message, an action that opens Settings → License, an
/// optional purchase action, and a dismiss button.
///
/// A dumb leaf, like `CruxBetaExpiryBanner`: [CruxLicenseExpiryGate] decides
/// what it says and when it shows. Nothing in it takes focus on its own.
class CruxLicenseExpiryBanner extends StatelessWidget {
  /// Creates the strip.
  const CruxLicenseExpiryBanner({
    required this.message,
    required this.openSettingsLabel,
    required this.onOpenSettings,
    required this.dismissLabel,
    required this.onDismiss,
    this.urgent = false,
    this.buyLabel,
    this.onBuy,
    this.sizing = const CruxBetaExpirySizing(),
    super.key,
  });

  /// Key of the action that opens Settings → License.
  static const Key openSettingsButtonKey = Key(
    'cruxLicenseExpiryBannerOpenSettings',
  );

  /// Key of the purchase action.
  static const Key buyButtonKey = Key('cruxLicenseExpiryBannerBuy');

  /// Key of the dismiss button.
  static const Key dismissButtonKey = Key('cruxLicenseExpiryBannerDismiss');

  /// Width below which the actions wrap under the message.
  static const double compactWidth = 600;

  /// The already-localized message.
  final String message;

  /// Whether the licence is past its expiry: the strip takes the error
  /// colours then, and the tertiary ones before.
  final bool urgent;

  /// Label of the settings action.
  final String openSettingsLabel;

  /// Opens Settings → License.
  final VoidCallback onOpenSettings;

  /// Label of the purchase action, or `null` for none.
  final String? buyLabel;

  /// Opens the purchase page; shown only with [buyLabel].
  final VoidCallback? onBuy;

  /// Screen-reader name of the dismiss button.
  final String dismissLabel;

  /// Dismisses the strip for the session.
  final VoidCallback onDismiss;

  /// Icon, hit-area and text sizing.
  final CruxBetaExpirySizing sizing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = urgent
        ? scheme.errorContainer
        : scheme.tertiaryContainer;
    final foreground = urgent
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: foreground,
      minimumSize: Size(sizing.touchTarget, sizing.touchTarget),
    );
    final actions = <Widget>[
      TextButton(
        key: openSettingsButtonKey,
        onPressed: onOpenSettings,
        style: buttonStyle,
        child: Text(openSettingsLabel),
      ),
      if (buyLabel != null && onBuy != null)
        TextButton(
          key: buyButtonKey,
          onPressed: onBuy,
          style: buttonStyle,
          child: Text(buyLabel!),
        ),
    ];
    // No Tooltip on the dismiss button: this strip renders above the app's
    // Navigator, so its Overlay is not an ancestor and a Tooltip would throw.
    // The glyph's semantic label names the button instead, on the node that
    // takes focus, so a screen reader says "Dismiss, button" when Tab lands.
    final dismiss = IconButton(
      key: dismissButtonKey,
      onPressed: onDismiss,
      iconSize: sizing.iconSize,
      color: foreground,
      constraints: BoxConstraints(
        minWidth: sizing.touchTarget,
        minHeight: sizing.touchTarget,
      ),
      icon: Icon(Icons.close, semanticLabel: dismissLabel),
    );
    final icon = Icon(
      urgent ? Icons.warning_amber_rounded : Icons.event_outlined,
      size: sizing.iconSize,
      color: foreground,
    );
    final text = Text(
      message,
      style: TextStyle(fontSize: sizing.bodyTextSize, color: foreground),
    );

    // Its own semantics container, so the message is announced as the
    // strip's name when focus enters it rather than merging into whatever
    // node lies above the Navigator (the window's, in a product).
    return Semantics(
      container: true,
      child: Material(
        color: background,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= compactWidth) {
                  return Row(
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Expanded(child: text),
                      const SizedBox(width: 8),
                      ...actions,
                      dismiss,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: icon,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: text,
                          ),
                          Wrap(children: actions),
                        ],
                      ),
                    ),
                    dismiss,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
