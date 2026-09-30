// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/license_actions.dart';
import 'package:crux_license/src/license_panel_providers.dart';
import 'package:crux_license/src/license_status.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/license_validation.dart';
import 'package:crux_license/src/policy_binding.dart';
import 'package:crux_license/src/widgets/edition_badge.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:crux_license/src/widgets/license_panel_strings.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable settings-category id for the licence panel.
///
/// Fixed here rather than at each of the four call sites so a deep link, a
/// conformance test, or a support instruction means the same thing in every
/// product.
const String kCruxLicenseCategoryId = 'pro.license';

/// Settings → License, once, for all four products.
///
/// ### This category is never tier-gated
///
/// It is not wrapped in `FeatureGate.isAvailable`, it is not hidden when
/// `licenseTierProvider` resolves to [LicenseTier.openCore], and it must not
/// be "made consistent" with the other `pro.*` categories by adding a tier
/// check. **It is how a user enters their first key**, so gating it on having
/// a key is a deadlock.
///
/// The seam it arrives through is build-time, not tier-time, and the existing
/// code already shows this: `pro.collaboration` is contributed as a static
/// list with no tier check anywhere. A category appears because the running
/// binary is the Pro overlay. Since the distributed binary *is* that
/// overlay build, every downloader gets this panel — including at Open Core,
/// which is exactly the state they are in when they need it.
///
/// ### One widget, four products
///
/// The panel was first planned for each product's Pro overlay, i.e. four
/// implementations of one surface — and four copies of a cross-product surface
/// drift apart, which is why the suite keeps exactly one. The resolution:
/// **the widget is shared, the service is not.** Everything product-specific
/// arrives through `licenseStatusProvider` and `licenseActionsProvider`, both
/// of which each Pro overlay overrides from its own `LicenseService`.
///
/// ### With no licence
///
/// Renders as a complete, calm panel. Open Core is the absence of a licence,
/// not an error state, and nothing here is coloured or worded as a failure.
class CruxLicensePanel extends ConsumerStatefulWidget {
  /// Create the panel.
  ///
  /// [product] is the app this build is, used only to label which product a
  /// suite licence covers. [strings] defaults to English so the widget renders
  /// in tests and prototypes without l10n wiring.
  const CruxLicensePanel({
    required this.product,
    this.strings = const CruxLicensePanelStringsEn(),
    this.badgeStrings = const LicenseBadgeStringsEn(),
    this.onPickCredentialFile,
    super.key,
  });

  /// The product this build is.
  final CruxProduct product;

  /// Localized strings.
  final CruxLicensePanelStrings strings;

  /// Localized strings for the EDU chip.
  final LicenseBadgeStrings badgeStrings;

  /// Loads a licence file from disk and returns its contents, or `null` if
  /// the user cancelled.
  ///
  /// Optional because file picking is a platform concern each app already
  /// solves its own way, and because the panel is fully usable without it —
  /// a licence file is text, and pasting it works. When omitted the "Load
  /// file…" button is not rendered at all rather than rendered dead.
  final Future<String?> Function(BuildContext context)? onPickCredentialFile;

  @override
  ConsumerState<CruxLicensePanel> createState() => _CruxLicensePanelState();
}

class _CruxLicensePanelState extends ConsumerState<CruxLicensePanel> {
  final _controller = TextEditingController();
  final _eduController = TextEditingController();
  String? _error;
  String? _eduError;
  bool _eduSubmitted = false;
  bool _eduUnderReview = false;

  @override
  void dispose() {
    _controller.dispose();
    _eduController.dispose();
    super.dispose();
  }

  CruxLicensePanelStrings get _s => widget.strings;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(licenseStatusProvider);
    final actions = ref.watch(licenseActionsProvider);
    // Locked, NOT hidden. Support needs the engineer on the phone to read their
    // own tier, expiry and seat state; a hidden panel turns every licence
    // question into a blind ticket.
    final managed = ref.watch(licenseManagedByOrganizationProvider);
    // A refused policy file. This panel is the one place a refusal is shown
    // rather than logged (see `PolicyReportDestination`): the sentence depends
    // on the rejection itself, and the report line is derived from the same
    // result.
    final policy = ref.watch(cruxPolicyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (policy.wasRejected) ...[
          _refusedNotice(policy),
          const SizedBox(height: 12),
        ],
        _StatusSection(
          status: status,
          strings: _s,
          badgeStrings: widget.badgeStrings,
          product: widget.product,
        ),
        if (managed) ...[
          const SizedBox(height: 12),
          _managedNotice(status),
        ] else ...[
          const SizedBox(height: 12),
          _sectionTitle(context, _s.licenseKeySectionTitle),
          _keyEntry(status, actions),
        ],
        if (status.hasCredential) ...[
          const SizedBox(height: 12),
          _sectionTitle(context, _s.licenseMachineSectionTitle),
          _machineSection(status, actions, managed: managed),
        ],
        if (!managed &&
            actions.supportsEducationalRequest &&
            status.activation == CruxLicenseActivation.openCore) ...[
          const SizedBox(height: 12),
          _sectionTitle(context, _s.licenseEduSectionTitle),
          _educationalSection(status, actions),
        ],
        if (!managed && actions.supportsOfflineActivation) ...[
          const SizedBox(height: 12),
          _sectionTitle(context, _s.licenseOfflineSectionTitle),
          _offlineSection(status, actions),
        ],
      ],
    );
  }

  /// The one line a managed installation gets in place of key entry, plus the
  /// state nobody will have looked at before a customer finds it: a policy
  /// licence that expired on a machine which cannot phone home.
  ///
  /// It deliberately does not tell the user to do anything. On a managed
  /// deployment they cannot, and an instruction they cannot follow is worse
  /// than none — so it names the grace window and points at their
  /// administrator.
  Widget _managedNotice(CruxLicenseStatus status) {
    final theme = Theme.of(context);
    final expired =
        status.activation == CruxLicenseActivation.grace ||
        status.activation == CruxLicenseActivation.expired;
    return CruxSettingsSectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _s.licenseManagedByOrganization,
                style: theme.textTheme.bodyMedium,
              ),
              if (expired) ...[
                const SizedBox(height: 8),
                Text(
                  _s.licenseManagedExpired,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The refusal an administrator otherwise finds only in the process log.
  ///
  /// A refused policy on a machine whose administrator deployed one is a
  /// support incident, and until this existed it was a stderr line nobody
  /// reads: the app ran ungoverned, which from the keyboard looks identical to
  /// a machine where no file was ever deployed. It lives in the licence panel
  /// because that is the surface an administrator checks on a seat, and
  /// because a refused policy is exactly what makes a managed seat look
  /// unmanaged — the licence key entry below reappears the moment the file
  /// carrying the organization's licence is refused.
  ///
  /// Two lines and a diagnostic: what happened, why (one sentence per reason,
  /// because the fixes differ), and the same `policy.rejected` line the
  /// process log carries, so a screenshot and a support bundle say the same
  /// thing. The line never names the file's path; see `PolicyLoadReport`.
  Widget _refusedNotice(PolicyLoadResult policy) {
    final theme = Theme.of(context);
    final why = switch (policy.rejection!) {
      PolicyRejection.noPublicKey => _s.licensePolicyRefusedNoPublicKey,
      PolicyRejection.badSignature => _s.licensePolicyRefusedBadSignature,
      PolicyRejection.untrustedUnsigned =>
        _s.licensePolicyRefusedUntrustedUnsigned,
      PolicyRejection.malformedSignature =>
        _s.licensePolicyRefusedMalformedSignature,
      PolicyRejection.insecurePath => _s.licensePolicyRefusedInsecurePath,
    };
    final report = PolicyLoadReport.of(policy);
    return CruxSettingsSectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s.licensePolicyRefused,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(why, style: theme.textTheme.bodyMedium),
                    if (report != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        report.line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  // --- Key entry ---------------------------------------------------------

  Widget _keyEntry(CruxLicenseStatus status, CruxLicenseActions actions) {
    final theme = Theme.of(context);
    return CruxSettingsSectionCard(
      children: [
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          enabled: !status.busy,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: _s.licenseKeyFieldLabel,
            // Without this the label is centred against the whole multi-line
            // box, which lands it right on top of the pasted key. A licence
            // key is 700 characters of base64 and needs every bit of
            // legibility it can get.
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            helperText: status.hasCredential
                ? _s.licenseKeyFieldHelperActive
                : _s.licenseKeyFieldHelper,
            helperMaxLines: 3,
            errorText: _error,
            errorMaxLines: 4,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (widget.onPickCredentialFile != null)
              TextButton.icon(
                onPressed: status.busy ? null : _pickFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(_s.licenseChooseFileButton),
              ),
            FilledButton(
              onPressed: status.busy ? null : () => _activate(actions),
              child: status.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_s.licenseActivateButton),
            ),
          ],
        ),
        if (actions.supportsPurchaseLinks) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: status.busy
                      ? null
                      : () => _run(actions.openPurchasePage),
                  child: Text(_s.licenseBuyButton),
                ),
                if (status.hasCredential && actions.supportsManageLink)
                  TextButton(
                    onPressed: status.busy
                        ? null
                        : () => _run(actions.openManagePage),
                    child: Text(_s.licenseManageButton),
                  ),
              ],
            ),
          ),
        ],
        if (status.activation == CruxLicenseActivation.invalid &&
            status.rejection != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _messageForRejection(status.rejection!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final pick = widget.onPickCredentialFile;
    if (pick == null) return;
    final contents = await pick(context);
    if (contents == null || !mounted) return;
    setState(() {
      _controller.text = contents;
      _error = null;
    });
  }

  Future<void> _activate(CruxLicenseActions actions) async {
    final credential = _controller.text.trim();
    if (credential.isEmpty) {
      setState(() => _error = _s.licenseErrorMalformed);
      return;
    }
    final result = await actions.activate(credential);
    if (!mounted) return;
    if (result.isOk) {
      setState(() {
        _controller.clear();
        _error = null;
      });
      _announce(_s.licenseActivatedMessage);
    } else {
      setState(() => _error = _messageFor(result as LicenseActionFailed));
    }
  }

  // --- This machine ------------------------------------------------------

  Widget _machineSection(
    CruxLicenseStatus status,
    CruxLicenseActions actions, {
    required bool managed,
  }) {
    final theme = Theme.of(context);
    final machine = status.machineLabel;
    return CruxSettingsSectionCard(
      children: [
        if (machine != null)
          _row(context, _s.licenseMachineLabel, machine)
        else
          const SizedBox.shrink(),
        _row(
          context,
          '',
          status.lastCheckedAt == null
              ? _s.licenseNeverChecked
              : _s.licenseLastChecked(
                  _formatDateTime(status.lastCheckedAt!.toLocal()),
                ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: status.busy ? null : () => _run(actions.refresh),
              icon: const Icon(Icons.refresh),
              label: Text(_s.licenseRefreshButton),
            ),
            // Deactivation is the organization's to perform, not the
            // engineer's — releasing the seat of a machine the org licensed
            // would leave it unlicensed with no way to fix it from here.
            // Refresh stays: it is read-only and it is what support asks for.
            if (actions.supportsDeactivation && !managed)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: status.busy ? null : () => _deactivate(actions),
                child: Text(_s.licenseDeactivateButton),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _deactivate(CruxLicenseActions actions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // A destructive confirm is a deliberate act, and default focus stays on
      // the safe action.
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.licenseDeactivateConfirmTitle),
        content: Text(_s.licenseDeactivateConfirmBody),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_s.licenseCancelAction),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_s.licenseDeactivateConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await actions.deactivateThisMachine();
    if (!mounted) return;
    if (result.isOk) {
      _announce(_s.licenseDeactivatedMessage);
    } else {
      _announce(_messageFor(result as LicenseActionFailed));
    }
  }

  // --- Educational licence -------------------------------------------------

  /// Only rendered at Open Core: a user who already holds a licence has no
  /// use for it, and offering it anyway invites them to end up with two.
  Widget _educationalSection(
    CruxLicenseStatus status,
    CruxLicenseActions actions,
  ) {
    final theme = Theme.of(context);
    return CruxSettingsSectionCard(
      children: [
        Text(
          _s.licenseEduBody,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_eduSubmitted)
          // The licence does not arrive here; it arrives by email. Saying so
          // plainly is the whole job of this state — a user who waits for the
          // panel to change is a user who files a support ticket.
          //
          // Which sentence depends on which path the backend took: an
          // unrecognised domain gets a human and no confirmation link, so the
          // automatic path's instructions would send that applicant looking
          // for mail that was never sent.
          Text(
            _eduUnderReview
                ? _s.licenseEduUnderReview
                : _s.licenseEduCheckYourEmail,
            style: theme.textTheme.bodyMedium,
          )
        else ...[
          TextField(
            controller: _eduController,
            enabled: !status.busy,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: _s.licenseEduEmailLabel,
              errorText: _eduError,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_eduError != null) setState(() => _eduError = null);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonal(
              onPressed: status.busy ? null : () => _requestEdu(actions),
              child: Text(_s.licenseEduRequestButton),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _requestEdu(CruxLicenseActions actions) async {
    final result = await actions.requestEducationalLicense(
      _eduController.text,
    );
    if (!mounted) return;
    if (result.isOk) {
      setState(() {
        _eduSubmitted = true;
        _eduUnderReview = (result as LicenseActionSucceeded).underReview;
        _eduError = null;
      });
    } else {
      setState(() => _eduError = _messageFor(result as LicenseActionFailed));
    }
  }

  // --- Offline activation ------------------------------------------------

  Widget _offlineSection(
    CruxLicenseStatus status,
    CruxLicenseActions actions,
  ) {
    final theme = Theme.of(context);
    return CruxSettingsSectionCard(
      children: [
        Text(
          _s.licenseOfflineBody,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(_s.licenseOfflineSteps, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: status.busy ? null : () => _exportRequest(actions),
              icon: const Icon(Icons.upload_outlined),
              label: Text(_s.licenseExportRequestButton),
            ),
            TextButton.icon(
              onPressed: status.busy ? null : () => _importToken(actions),
              icon: const Icon(Icons.download_outlined),
              label: Text(_s.licenseImportTokenButton),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportRequest(CruxLicenseActions actions) async {
    final result = await actions.exportOfflineRequest();
    if (!mounted) return;
    if (result is LicenseActionFailed) {
      _announce(_messageFor(result));
      return;
    }
    final payload = (result as LicenseActionSucceeded).payload ?? '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_s.licenseExportRequestTitle),
        content: SelectableText(
          payload,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Close first, and never let the clipboard decide whether the
              // dialog goes away: a platform that refuses the write would
              // otherwise strand the user in a modal with no feedback. The
              // request is on screen and selectable either way.
              Navigator.of(context).pop();
              unawaited(_copyRequest(payload));
            },
            child: Text(_s.licenseCopyAction),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_s.licenseCloseAction),
          ),
        ],
      ),
    );
  }

  /// Copies the exported request, and says so.
  ///
  /// `licenseCopiedMessage` existed but was never shown — a copy button that
  /// gives no feedback is one a user presses twice and then pastes wrong.
  Future<void> _copyRequest(String payload) async {
    try {
      await Clipboard.setData(ClipboardData(text: payload));
    } on Object {
      // A refused clipboard is not worth an error surface: the request is
      // still on screen and selectable.
      return;
    }
    if (!mounted) return;
    _announce(_s.licenseCopiedMessage);
  }

  Future<void> _importToken(CruxLicenseActions actions) async {
    // The token goes in the same field the key does — one place to paste
    // something, rather than two that look the same and behave differently.
    final token = _controller.text.trim();
    if (token.isEmpty) {
      setState(() => _error = _s.licenseErrorMalformed);
      return;
    }
    final result = await actions.importOfflineToken(token);
    if (!mounted) return;
    if (result.isOk) {
      setState(() {
        _controller.clear();
        _error = null;
      });
      _announce(_s.licenseActivatedMessage);
    } else {
      setState(() => _error = _messageFor(result as LicenseActionFailed));
    }
  }

  // --- Shared plumbing ---------------------------------------------------

  Future<void> _run(
    Future<CruxLicenseActionResult> Function() action,
  ) async {
    final result = await action();
    if (!mounted || result.isOk) return;
    _announce(_messageFor(result as LicenseActionFailed));
  }

  void _announce(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(LicenseActionFailed failed) => switch (failed.failure) {
    CruxLicenseActionFailure.rejected =>
      failed.rejection == null
          ? _s.licenseErrorUnknown
          : _messageForRejection(failed.rejection!),
    CruxLicenseActionFailure.offline => _s.licenseErrorOffline,
    CruxLicenseActionFailure.noSeatAvailable => _s.licenseErrorNoSeat,
    CruxLicenseActionFailure.refusedByIssuer => _s.licenseErrorRefused,
    CruxLicenseActionFailure.invalidEmail => _s.licenseErrorInvalidEmail,
    CruxLicenseActionFailure.alreadyRequested =>
      _s.licenseErrorAlreadyRequested,
    CruxLicenseActionFailure.notSupported => _s.licenseErrorNotSupported,
    CruxLicenseActionFailure.unknown => _s.licenseErrorUnknown,
  };

  String _messageForRejection(LicenseRejection rejection) =>
      switch (rejection) {
        LicenseRejection.malformed ||
        LicenseRejection.undecodablePayload => _s.licenseErrorMalformed,
        LicenseRejection.unsupportedAlgorithm => _s.licenseErrorEncryptedFile,
        LicenseRejection.untrustedIssuer => _s.licenseErrorSignature,
        LicenseRejection.wrongAccount => _s.licenseErrorAccount,
        LicenseRejection.unknownPolicy => _s.licenseErrorUnknownPolicy,
        LicenseRejection.productNotEntitled => _s.licenseErrorProduct,
        LicenseRejection.wrongMachine => _s.licenseErrorWrongMachine,
      };
}

/// The status card: tier, state, and the facts support will ask for.
class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.status,
    required this.strings,
    required this.badgeStrings,
    required this.product,
  });

  final CruxLicenseStatus status;
  final CruxLicensePanelStrings strings;
  final LicenseBadgeStrings badgeStrings;
  final CruxProduct product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grant = status.grant;
    final tier = status.tier;
    return CruxSettingsSectionCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _tierLabel(tier),
                style: theme.textTheme.titleMedium,
              ),
            ),
            // Passes `tier` explicitly — see EditionBadge.tier. This widget
            // holds status.tier, which licenseTierProvider is DERIVED from, so
            // reading the provider here could render a chip disagreeing with
            // the label immediately to its left.
            if (tier != LicenseTier.openCore) ...[
              const SizedBox(width: 8),
              EditionBadge(tier: tier, strings: badgeStrings),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _stateLine(context),
          style: theme.textTheme.bodyMedium?.copyWith(
            color:
                status.activation == CruxLicenseActivation.grace ||
                    status.activation == CruxLicenseActivation.noSeat
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (status.activation == CruxLicenseActivation.openCore)
          const SizedBox.shrink()
        else ...[
          const SizedBox(height: 12),
          if (grant?.skuLookupKey != null)
            _row(context, strings.licenseSkuLabel, grant!.skuLookupKey!),
          if (grant?.email != null)
            _row(context, strings.licenseEmailLabel, grant!.email!),
          if (grant?.licenseId != null)
            _row(context, strings.licenseIdLabel, grant!.licenseId!),
          if (status.seatsUsed != null && status.seatsTotal != null)
            _row(
              context,
              '',
              strings.licenseSeatsInUse(
                status.seatsUsed!,
                status.seatsTotal!,
              ),
            ),
        ],
      ],
    );
  }

  String _tierLabel(LicenseTier tier) => switch (tier) {
    LicenseTier.openCore => strings.licenseTierOpenCore,
    LicenseTier.edu => strings.licenseTierEdu,
    LicenseTier.pro => strings.licenseTierPro,
    LicenseTier.enterprise => strings.licenseTierEnterprise,
  };

  String _stateLine(BuildContext context) {
    final grant = status.grant;
    switch (status.activation) {
      case CruxLicenseActivation.openCore:
        return strings.licenseStateOpenCoreBody;
      case CruxLicenseActivation.notActivatedOnThisMachine:
        return strings.licenseStateNotActivated;
      case CruxLicenseActivation.grace:
        return strings.licenseStateGrace(
          status.graceDaysRemainingAt(DateTime.now()) ?? 0,
        );
      case CruxLicenseActivation.expired:
        return strings.licenseStateExpired;
      case CruxLicenseActivation.noSeat:
        return strings.licenseErrorNoSeat;
      case CruxLicenseActivation.invalid:
        return strings.licenseStateInvalid;
      case CruxLicenseActivation.active:
        final expiry = grant?.expiry;
        return expiry == null
            ? strings.licenseStatePerpetual
            : strings.licenseStateActive(_formatDate(expiry.toLocal()));
    }
  }
}

/// A label/value row. An empty [label] renders the value alone, which is how
/// the seat count and the last-checked line read best.
Widget _row(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  final muted = theme.textTheme.bodySmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
  if (label.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(value, style: muted),
    );
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label, style: muted)),
        Expanded(
          child: SelectableText(value, style: theme.textTheme.bodySmall),
        ),
      ],
    ),
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

/// `yyyy-MM-dd`. Deliberately not localized through `intl`: the package is
/// dependency-light on purpose, and an ISO date is unambiguous in every
/// locale the suite ships — which a numeric locale-specific format is not.
String _formatDate(DateTime at) =>
    '${at.year}-${_two(at.month)}-${_two(at.day)}';

String _formatDateTime(DateTime at) =>
    '${_formatDate(at)} ${_two(at.hour)}:${_two(at.minute)}';
