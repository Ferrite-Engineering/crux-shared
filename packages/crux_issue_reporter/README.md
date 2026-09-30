# crux_issue_reporter

The EDACrux suite's in-app beta issue reporter, as one shared package —
diagnostic-log ring buffer, structured category collection, screenshot
capture, markdown report builder, and the pre-filled GitHub new-issue
submission dialog.

Lifted from the shipped WaveCrux implementation and made product-agnostic so
NetCrux, LintCrux and SimCrux get the identical flow. Open to all tiers: no
tier badge, no feature gate. Designed for the public-beta period, and it stays
useful afterwards as a low-friction issue path.

**WaveCrux is not migrated onto this package yet** — it still carries its own
copy. This package is the extraction target, not the current WaveCrux code
path.

## What the user sees

1. A "Submit Issue" action opens the reporter — a modal dialog on desktop, a
   pushed full-screen route on mobile.
2. A free-text **issue summary** field, a privacy callout, and a set of
   toggleable **category tiles**:

   | Category | Default | Content |
   |---|---|---|
   | **App & Environment** | always on (locked) | Product name, app version, build SHA, platform, OS, architecture, screen DPI, locale, Flutter/Dart SDK versions |
   | **Session State** | on | Whatever the product's session contributor supplied — counts and format names only, never paths |
   | **Diagnostic Log** | on | Last 100 WARNING+ ring-buffer entries plus the last 20 at any level, de-duplicated by timestamp, as a fenced code block; optionally preceded by the product's structured diagnostics snapshot |
   | **Screenshot** | on, desktop only | Flutter-layer `RepaintBoundary` capture, previewed as a thumbnail. Hidden on iOS/Android/web |
   | *overlay categories* | on | Whatever the Pro overlay contributes (e.g. "Pro State") |

3. A collapsible **markdown preview** showing the exact issue body, updating
   live as categories are toggled.
4. **Submit** copies the body to the clipboard, opens the pre-filled GitHub
   new-issue URL via `url_launcher`, and on desktop writes the screenshot PNG
   to the OS temp directory and reveals it in Finder / Explorer / the file
   manager.

## Privacy contract

The report carries **no private file contents, no signal or design values, and
no file paths** — only counts, format names, display names and environment
metadata. That is a contract, not a convention: `crux_issue_reporter`'s own
suite asserts that a rendered Session State body contains no path separators,
and every consuming product should repeat that assertion over its *real*
contributor, because the package cannot see what a product chooses to put in a
`CruxIssueField`.

## Surface

| Symbol | Purpose |
|---|---|
| `CruxIssueReporterConfig` | Product name, GitHub `owner/repo` slug, issue template, default labels, host, screenshot filename prefix, URL length cap. |
| `cruxIssueReporterConfigProvider` | **Must be overridden.** The package default throws `CruxIssueReporterUnconfiguredError` so an unwired product fails loudly rather than filing reports at the wrong repository. |
| `cruxIssueSessionContextProvider` | **Product seam.** Returns the privacy-scrubbed `CruxIssueSessionContext` (a list of `CruxIssueField`s plus free-form `attributes`). Default: `CruxIssueSessionContext.empty`, which omits the Session State category entirely. |
| `CruxIssueReporterDataProvider` / `cruxIssueReporterDataProviderProvider` | **Overlay seam.** A Pro build contributes whole extra categories from the same snapshot. Default: `NoopCruxIssueReporterDataProvider`. |
| `CruxIssueReporterStrings` / `CruxIssueReporterStringsEn` | Caller-supplied localization surface. crux-shared packages ship no ARB files. |
| `cruxIssueReporterStringsProvider` | The active string bundle. Defaults to English. |
| `cruxIssueReporterBuildInfoProvider` | The product's `ApplicationBuildInfo` (from `crux_app_info`) for the App & Environment category. `null` omits the category. |
| `cruxIssueDiagnosticsReportProvider` | Optional structured diagnostics snapshot folded into the Diagnostic Log category ahead of the session log. |
| `cruxAppScreenshotBoundaryKeyProvider` | The `GlobalKey` the product attaches to the root `RepaintBoundary`. |
| `cruxIssueReporterLogBufferProvider` | The process-wide `CruxIssueReporterLogBuffer`. |
| `CruxIssueReporterLogBuffer` / `CruxIssueLogEntry` | 500-entry circular buffer over `package:logging`, with `FlutterError` / `PlatformDispatcher` error capture and a `recentEntries(count, {minLevel})` query. The capture also reports each error to `crux_telemetry`'s `TelemetryUncaughtErrorCounter` as `app.uncaught_error` — class bucket, framework library and `silent` flag only, never the message or stack — which is sent only if the telemetry consent gate allows. |
| `CruxIssueReporterService` / `CruxIssueSubmission` | Category builders, markdown assembly, new-issue URL construction, screenshot capture, clipboard + launch + desktop reveal. |
| `cruxIssueReporterServiceProvider` | The service, built from the config. Override in tests to inject clipboard/launcher fakes. |
| `CruxIssueReporterDialog` | The adaptive reporter UI, with `openAdaptive(context)`. |
| `cruxIssueTileKey`, `kCruxIssuePreviewBodyKey`, `kCruxIssuePreviewToggleKey`, `kCruxIssueTitleFieldKey` | Stable widget keys, so a product's (and an overlay's) own widget tests can drive the dialog. |
| `isCruxDesktopPlatform` / `isCruxMobilePlatform` | Host-platform predicates the reporter uses for presentation and screenshot availability. |

## Wiring it in (per product)

### 1. Capture logs before anything else

```dart
// bootstrap(), before the first provider is constructed, so early-startup
// warnings land in the ring.
CruxIssueReporterLogBuffer.instance
  ..attachToLogging()
  ..captureFlutterErrors();
```

`captureFlutterErrors` is also where the telemetry crash counter gets its
input, so it needs no wiring of its own: list `app.uncaught_error` in the
product's event catalog and the rest is `crux_telemetry`'s.

### 2. Wrap the app content in the screenshot boundary

```dart
class NetCruxApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    routerConfig: router,
    builder: (context, child) => RepaintBoundary(
      key: ref.watch(cruxAppScreenshotBoundaryKeyProvider),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
```

### 3. Adapt the strings to the product's ARB

```dart
class NetCruxIssueReporterStrings extends CruxIssueReporterStrings {
  const NetCruxIssueReporterStrings(this._l10n);
  final L10N _l10n;

  @override String get dialogTitle => _l10n.issueReporterTitle;
  @override String get titleFieldLabel => _l10n.issueReporterTitleFieldLabel;
  // ...one line per getter; see CruxIssueReporterStringsEn for the full list.
}
```

### 4. Register the config and both seams

```dart
// Open-core overrides.
final coreOverrides = <Override>[
  // Config — the repository slug is per product, and it is the repo a user's
  // issue should actually land in.
  cruxIssueReporterConfigProvider.overrideWithValue(
    CruxIssueReporterConfig(
      productName: 'NetCrux',
      repositorySlug: 'Ferrite-Engineering/netcrux',
    ),
  ),

  // Build info, sourced from the product's own async provider.
  cruxIssueReporterBuildInfoProvider.overrideWith(
    (ref) => ref.watch(applicationBuildInfoProvider).value,
  ),

  // PRODUCT SEAM — the privacy-scrubbed session snapshot. Counts, format
  // names and display names only: never a path, never file contents.
  cruxIssueSessionContextProvider.overrideWith((ref) {
    final projects = ref.watch(projectListProvider);
    final active = ref.watch(activeDesignProvider);
    return CruxIssueSessionContext(
      fields: [
        CruxIssueField(label: 'Open projects', value: '${projects.length}'),
        CruxIssueField(
          label: 'Active design format',
          value: active?.formatName ?? '(none loaded)',
        ),
        CruxIssueField(label: 'Nets', value: '${active?.netCount ?? 0}'),
      ],
      // Structured extras the Pro overlay may read; same privacy rules.
      attributes: {'proFeatureCount': ref.watch(activeProFeatureCount)},
    );
  }),

  // Optional: reuse the product's "Copy Full Diagnostics Report" text.
  cruxIssueDiagnosticsReportProvider.overrideWith(
    (ref) => ref.watch(diagnosticsReportProvider),
  ),
];
```

```dart
// OVERLAY SEAM — in the Pro overlay's proOverrides list, after the
// open-core overrides (later overrides win).
final proOverrides = <Override>[
  cruxIssueReporterDataProviderProvider.overrideWithValue(
    const NetCruxProIssueDataProvider(),
  ),
];

class NetCruxProIssueDataProvider implements CruxIssueReporterDataProvider {
  const NetCruxProIssueDataProvider();

  @override
  List<CruxIssueCategory> extraCategories(CruxIssueSessionContext context) {
    final proCount = context.attributes['proFeatureCount'];
    if (proCount is! int || proCount == 0) return const [];
    return [
      CruxIssueCategory(
        id: 'proState',
        // Localized from context.localeTag — no BuildContext here.
        title: lookupL10N(context.localeTag).issueReporterCategoryProState,
        markdownBody: '- **Active Pro features:** $proCount',
      ),
    ];
  }
}
```

The strings provider is normally overridden from the widget layer, where a
`BuildContext` is available:

```dart
ProviderScope(
  overrides: [
    cruxIssueReporterStringsProvider.overrideWithValue(
      NetCruxIssueReporterStrings(L10N.of(context)),
    ),
  ],
  child: child,
)
```

### 5. Open it

```dart
await CruxIssueReporterDialog.openAdaptive(context);
```

`openAdaptive` invalidates `cruxIssueSessionContextProvider` first, so a
contributor that reads per-tab or per-pane containers still produces a fresh
snapshot for every report.

## Localization

crux-shared packages contain no ARB files — the host product owns
localization. This package only defines the `CruxIssueReporterStrings`
interface and an English default.

Consequently **the per-locale sweep is the consuming product's
responsibility.** The tests here sweep by injecting different
`CruxIssueReporterStrings` bundles (including long CJK strings) across
phone/tablet/desktop widths, both `Directionality` values and the clamped
1.0x–1.5x text-scale range. That proves the layout survives arbitrary string
lengths; it does not prove that *your* `en`/`zh_CN`/`ja`/`ko` ARB entries all
exist and render. Add the usual four-locale widget sweep over your own
adapter in the product's suite.

## Behavioral notes

- **Over-long bodies.** The body is embedded in the GitHub new-issue URL when
  the total URL fits under `CruxIssueReporterConfig.maxIssueUrlLength` (6000 by
  default); beyond that GitHub truncates or rejects it, so the body is dropped
  from the URL and only the clipboard copy carries it.
  `CruxIssueSubmission.bodyPrefilled` reports which happened, and the dialog
  picks the matching toast.
- **The issue body is not localized.** The markdown field labels
  (`**App version:**`, `**Build SHA:**`, …) are deliberately English: the body
  is read by maintainers in the GitHub repository, and a mixed-language body
  makes triage harder. Only the UI chrome and the category titles come from
  `CruxIssueReporterStrings`.
- **The Session State tile disappears when unwired.** A product that has not
  overridden `cruxIssueSessionContextProvider` gets no Session State category
  and no tile, rather than an empty section.
- **Screenshot on desktop only.** The tile is hidden on iOS, Android and web —
  the GitHub mobile new-issue form has no drag-attach and web has no temp-dir
  reveal.
- **Touch targets.** Every category tile and the preview disclosure are at
  least `kCruxIssueReporterMinTouchTarget` (48 dp) tall, clearing the suite's
  44 dp minimum. The package is domain-neutral, so it uses one constant rather
  than a `MobileMetrics`-style device-class lookup.

## Testing

```bash
cd packages/crux_issue_reporter
flutter test
```
