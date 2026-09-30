// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show PlatformDispatcher;

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_issue_reporter/src/crux_issue_reporter_strings.dart';
import 'package:crux_issue_reporter/src/interfaces/crux_issue_reporter_data_provider.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_reporter_config.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_session_context.dart';
import 'package:crux_issue_reporter/src/services/crux_issue_reporter_log_buffer.dart';
import 'package:crux_issue_reporter/src/services/crux_issue_reporter_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thrown by the package default of [cruxIssueReporterConfigProvider] when a
/// product opens the reporter without supplying a configuration.
///
/// Failing loudly is deliberate: the alternative is a plausible-looking
/// default that files a user's bug report against the wrong repository.
class CruxIssueReporterUnconfiguredError extends StateError {
  /// Creates the unconfigured error with the standard remediation message.
  CruxIssueReporterUnconfiguredError()
    : super(
        'cruxIssueReporterConfigProvider has no value. Override it with a '
        'CruxIssueReporterConfig naming this product and its GitHub '
        'owner/repo slug before opening CruxIssueReporterDialog.',
      );
}

/// Per-product reporter configuration. **Must be overridden** by every
/// consuming product — the package default throws
/// [CruxIssueReporterUnconfiguredError].
final cruxIssueReporterConfigProvider = Provider<CruxIssueReporterConfig>(
  (_) => throw CruxIssueReporterUnconfiguredError(),
);

/// Localized strings for the reporter UI. Defaults to the English-only
/// [CruxIssueReporterStringsEn]; each product overrides it with an adapter
/// over its own generated `AppLocalizations`.
final cruxIssueReporterStringsProvider = Provider<CruxIssueReporterStrings>(
  (_) => const CruxIssueReporterStringsEn(),
);

/// The [GlobalKey] attached to the root `RepaintBoundary` that wraps the
/// `MaterialApp`'s content child. The reporter resolves it to a
/// `RenderRepaintBoundary` to capture a Flutter-layer screenshot.
///
/// A plain [GlobalKey] (not a typed `GlobalKey<State>`): `RepaintBoundary` is
/// not a `StatefulWidget`, so callers read its render object via
/// `key.currentContext?.findRenderObject() as RenderRepaintBoundary?`.
final cruxAppScreenshotBoundaryKeyProvider = Provider<GlobalKey>(
  (_) => GlobalKey(debugLabel: 'cruxAppScreenshotBoundary'),
);

/// The process-wide diagnostic-log ring buffer. Each product's `bootstrap()`
/// attaches the shared [CruxIssueReporterLogBuffer.instance] to the logging
/// system before any provider is constructed; this provider exposes that same
/// instance so the reporter can read recent entries. Overridable in tests.
final cruxIssueReporterLogBufferProvider = Provider<CruxIssueReporterLogBuffer>(
  (_) => CruxIssueReporterLogBuffer.instance,
);

/// **Product seam.** The privacy-scrubbed Session State snapshot.
///
/// The package knows nothing about the host product's domain, so the default
/// contributes [CruxIssueSessionContext.empty] and the Session State category
/// is omitted entirely. Each product overrides this provider with a body that
/// watches its own state and returns the counts, format names and display
/// names it wants in the report — never file paths or file contents.
///
/// The dialog invalidates this provider each time it is opened
/// (see `CruxIssueReporterDialog.openAdaptive`), so a contributor built from
/// `ref.read` of per-tab or per-pane containers still produces a fresh
/// snapshot per report.
final cruxIssueSessionContextProvider = Provider<CruxIssueSessionContext>(
  (_) => CruxIssueSessionContext.empty,
);

/// **Overlay seam.** Extension point for overlay-contributed categories.
///
/// The open-core default contributes nothing; a Pro overlay replaces this
/// with a provider returning a data provider that adds e.g. a "Pro State"
/// category. Distinct from [cruxIssueSessionContextProvider], which is the
/// *product's* own session snapshot.
final cruxIssueReporterDataProviderProvider =
    Provider<CruxIssueReporterDataProvider>(
      (_) => const NoopCruxIssueReporterDataProvider(),
    );

/// The application build metadata rendered in the App & Environment category.
///
/// Defaults to `null`, which omits the category. Each product overrides this
/// with a synchronous view of its own `applicationBuildInfoProvider`, e.g.
/// `Provider((ref) => ref.watch(applicationBuildInfoProvider).value)`.
final cruxIssueReporterBuildInfoProvider = Provider<ApplicationBuildInfo?>(
  (_) => null,
);

/// Optional structured diagnostics-report snapshot folded into the Diagnostic
/// Log category, ahead of the captured session log.
///
/// When `null` (the default) the category contains the session log only. A
/// product that already has a "Copy Full Diagnostics Report" action overrides
/// this to reuse the same text.
final cruxIssueDiagnosticsReportProvider = Provider<String?>((_) => null);

/// The [CruxIssueReporterService] used by the reporter dialog, built from
/// [cruxIssueReporterConfigProvider]. Overridable in tests to inject clipboard
/// and url-launcher fakes.
final cruxIssueReporterServiceProvider = Provider<CruxIssueReporterService>(
  (ref) => CruxIssueReporterService(
    config: ref.watch(cruxIssueReporterConfigProvider),
  ),
);

/// The OS locale tag, used as a fallback when no `Localizations` locale is in
/// scope. Returns the tag the suite uses elsewhere (`en`, `zh_CN`, `ja`,
/// `ko`).
String cruxPlatformLocaleTag() =>
    cruxLocaleTag(PlatformDispatcher.instance.locale);

/// Renders [locale] as the underscore-joined tag the suite uses
/// (`zh_CN`, `en`, `ja`, `ko`).
String cruxLocaleTag(Locale locale) {
  final country = locale.countryCode;
  if (country != null && country.isNotEmpty) {
    return '${locale.languageCode}_$country';
  }
  return locale.languageCode;
}
