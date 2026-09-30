# Changelog

## Unreleased

- **The screenshot reveal is `crux_io`'s `revealInFileManager`.** The service
  carried its own copy, which spawned `open`, `explorer` and `xdg-open` by bare
  name and passed Explorer's `/select,` switch and the path as two arguments,
  so on Windows Explorer opened the temp folder without selecting the
  screenshot. The shared reveal resolves each command to an absolute path,
  selects the file on Windows, and on Linux selects it through the
  FileManager1 D-Bus interface before falling back to opening the folder.
  `crux_io` is a new dependency.

- **`captureFlutterErrors` also counts each uncaught error for telemetry.**
  Both handlers report to `TelemetryUncaughtErrorCounter` (from
  `crux_telemetry`, now a dependency), which records the error's class bucket,
  the framework library and the `silent` flag as `app.uncaught_error` — never
  the message or the stack. A GUI-launched release build has no stderr, so
  without this a crash left no durable trace. Sending is decided by the
  telemetry consent gate. The optional `errorCounter` parameter is a test
  seam; the default is the process-wide counter.
- **The SEVERE records `captureFlutterErrors` logs carry the error and its
  stack trace.** They carried only a one-line message, so a listener that
  prints them (a product's stderr sink) could not say where an error came
  from. The buffer still stores the one-line message.

## 0.1.0

Initial extraction of the beta issue reporter from WaveCrux into a
product-agnostic shared package.

- `CruxIssueReporterConfig` + `cruxIssueReporterConfigProvider` — per-product
  product name, GitHub `owner/repo` slug, issue template, default labels, host,
  screenshot filename prefix and new-issue URL length cap. The package default
  throws `CruxIssueReporterUnconfiguredError` so an unwired product fails
  loudly instead of filing reports at the wrong repository.
- `cruxIssueSessionContextProvider` — the product seam. Each product
  contributes its own privacy-scrubbed `CruxIssueSessionContext`
  (`CruxIssueField` label/value pairs plus free-form `attributes`); the package
  composes the Session State category from it. Omitted entirely when unwired.
- `CruxIssueReporterDataProvider` + `cruxIssueReporterDataProviderProvider` —
  the overlay seam, unchanged in spirit from the WaveCrux original: a Pro
  build contributes whole extra categories from the same snapshot.
- `CruxIssueReporterStrings` + `CruxIssueReporterStringsEn` — caller-supplied
  localization surface, following the `LicenseBadgeStrings` / `CruxAboutStrings`
  convention. No ARB files ship in crux-shared.
- `CruxIssueReporterLogBuffer` + `CruxIssueLogEntry` — the 500-entry circular
  `package:logging` listener, with `FlutterError` / `PlatformDispatcher` error
  capture and the `recentEntries(count, {minLevel})` query.
- `CruxIssueReporterService` + `CruxIssueSubmission` — category builders,
  markdown assembly, new-issue URL construction with the over-long-body
  clipboard fallback, `RepaintBoundary` screenshot capture, clipboard write,
  launch and desktop file-manager reveal.
- `CruxIssueReporterDialog` — the adaptive reporter UI (modal on desktop,
  pushed route on mobile) with locked App & Environment, toggleable Session
  State / Diagnostic Log / Screenshot / overlay tiles, live markdown preview,
  and stable widget keys for product-side tests.
- `cruxIssueReporterBuildInfoProvider` sources App & Environment from
  `crux_app_info`'s `ApplicationBuildInfo` rather than re-deriving build
  metadata.
- `cruxIssueDiagnosticsReportProvider` folds a product's existing structured
  diagnostics snapshot into the Diagnostic Log category.

Deviations from the WaveCrux original are documented in the README's
"Behavioral notes"; the substantive ones are that the repository slug and
product name are configuration rather than constants, that Session State is an
injectable contributor rather than a hardcoded reach into workspace providers,
and that category tiles carry an optional description line and a 48 dp minimum
height.
