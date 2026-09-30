// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite beta issue reporter for the EDACrux suite.
///
/// A first-party in-app bug-report flow that collects structured diagnostic
/// data, lets the user review and opt out of individual categories, and
/// constructs a pre-filled GitHub new-issue URL that opens in the browser.
/// Designed for the public-beta period; it stays available in production as a
/// low-friction issue path for all tiers (no tier badge, no feature gate).
///
/// Lifted from the shipped WaveCrux implementation and made product-agnostic.
/// Everything product-specific is configuration or a seam:
///
/// - `CruxIssueReporterConfig` + `cruxIssueReporterConfigProvider` — product
///   name, GitHub `owner/repo` slug, issue template, default labels, URL
///   length cap. The package default throws, so an unwired product fails
///   loudly rather than filing reports against the wrong repository.
/// - `cruxIssueSessionContextProvider` — the **product seam**. Each product
///   contributes the privacy-scrubbed Session State snapshot (counts, format
///   names, display names — never file paths or file contents).
/// - `CruxIssueReporterDataProvider` +
///   `cruxIssueReporterDataProviderProvider` — the **overlay seam**. A Pro
///   overlay contributes whole extra categories (e.g. "Pro State").
/// - `CruxIssueReporterStrings` + `CruxIssueReporterStringsEn` — the
///   caller-supplied localization surface. crux-shared packages carry no ARB
///   files; each product supplies an adapter over its own generated
///   `AppLocalizations`.
/// - `cruxIssueReporterBuildInfoProvider` — the product's
///   `ApplicationBuildInfo` (from `crux_app_info`) for the App & Environment
///   category.
/// - `cruxIssueDiagnosticsReportProvider` — optional structured diagnostics
///   snapshot folded into the Diagnostic Log category.
/// - `cruxAppScreenshotBoundaryKeyProvider` — the `GlobalKey` the product
///   attaches to the `RepaintBoundary` wrapping its `MaterialApp` content
///   child, so the reporter can capture a Flutter-layer screenshot.
///
/// The moving parts:
///
/// - `CruxIssueReporterLogBuffer` — a 500-entry circular buffer registered as
///   a `package:logging` listener in `bootstrap()` before any provider is
///   constructed, so early-startup warnings are captured. Also chains
///   `FlutterError.onError` / `PlatformDispatcher.onError` into the ring.
/// - `CruxIssueReporterService` — category builders, markdown assembly,
///   new-issue URL construction (with the over-long-body fallback),
///   screenshot capture, clipboard write, launch and desktop reveal.
/// - `CruxIssueReporterDialog` — the adaptive reporter UI: modal on desktop,
///   pushed route on mobile, with toggleable category tiles and a live
///   markdown preview.
library;

export 'src/crux_issue_reporter_strings.dart';
export 'src/interfaces/crux_issue_reporter_data_provider.dart';
export 'src/models/crux_issue_category.dart';
export 'src/models/crux_issue_reporter_config.dart';
export 'src/models/crux_issue_session_context.dart';
export 'src/models/crux_issue_session_context_builder.dart';
export 'src/platform_utils.dart';
export 'src/providers/crux_issue_reporter_providers.dart';
export 'src/services/crux_issue_reporter_log_buffer.dart';
export 'src/services/crux_issue_reporter_service.dart';
export 'src/widgets/crux_issue_reporter_dialog.dart';
