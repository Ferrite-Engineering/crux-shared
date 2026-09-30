// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_issue_reporter/src/crux_issue_reporter_strings.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_category.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_session_context.dart';
import 'package:crux_issue_reporter/src/platform_utils.dart';
import 'package:crux_issue_reporter/src/providers/crux_issue_reporter_providers.dart';
import 'package:crux_issue_reporter/src/services/crux_issue_reporter_log_buffer.dart';
import 'package:crux_issue_reporter/src/services/crux_issue_reporter_service.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimum hit area for every interactive row in the reporter.
///
/// The suite's mobile standard is a 44 dp minimum touch target; 48 dp is the
/// Material default row height and clears it on every device class, so the
/// reporter uses one constant rather than a device-class lookup (this package
/// is domain-neutral and has no `MobileMetrics` equivalent).
const double kCruxIssueReporterMinTouchTarget = 48;

/// Key of the collapsible markdown preview body.
const Key kCruxIssuePreviewBodyKey = Key('cruxIssuePreviewBody');

/// Key of the disclosure control that expands the markdown preview.
const Key kCruxIssuePreviewToggleKey = Key('cruxIssuePreviewToggle');

/// Key of the free-text issue-summary field.
const Key kCruxIssueTitleFieldKey = Key('cruxIssueTitleField');

/// Returns the widget key of the category tile for [categoryId]. Tiles for
/// overlay-contributed categories use their own id, so a Pro overlay test can
/// find its "Pro State" tile the same way.
Key cruxIssueTileKey(String categoryId) => Key('cruxIssueTile_$categoryId');

/// Stable id of the (non-markdown) Screenshot attachment category.
const String kCruxIssueScreenshotCategoryId = 'screenshot';

/// In-app beta issue reporter dialog.
///
/// Lets the user describe a bug, review the diagnostic data that will be
/// attached (toggling off any category they'd rather not share), preview the
/// exact GitHub issue body, then Submit — which copies the body to the
/// clipboard and opens the pre-filled GitHub new-issue page in the browser.
///
/// Open to all tiers: no tier badge, no feature gate. Presents as a modal
/// dialog on desktop and a pushed route on mobile via [openAdaptive], matching
/// the suite's desktop-modal-dialog rule.
class CruxIssueReporterDialog extends ConsumerStatefulWidget {
  /// Creates the dialog body. [screenshotPng] is the pre-captured app
  /// screenshot (desktop only); `null` on mobile/web or when capture failed.
  const CruxIssueReporterDialog({this.screenshotPng, super.key});

  /// The screenshot captured before the dialog opened, so the capture shows
  /// the clean app state rather than the dialog itself.
  final Uint8List? screenshotPng;

  /// Width of the desktop modal presentation.
  static const double desktopWidth = 560;

  /// Height of the desktop modal presentation.
  static const double desktopHeight = 680;

  /// Opens the reporter. On desktop captures a screenshot of the live app
  /// first, then shows a modal dialog; on mobile pushes a full-screen route
  /// (no screenshot — the GitHub mobile new-issue form has no drag-attach).
  ///
  /// Invalidates `cruxIssueSessionContextProvider` first so the product's
  /// session contributor recomputes for this report.
  static Future<void> openAdaptive(BuildContext context) async {
    final container = ProviderScope.containerOf(context)
      ..invalidate(cruxIssueSessionContextProvider);

    Uint8List? screenshot;
    if (isCruxDesktopPlatform && !kIsWeb) {
      final service = container.read(cruxIssueReporterServiceProvider);
      final boundaryKey = container.read(cruxAppScreenshotBoundaryKeyProvider);
      final renderObject = boundaryKey.currentContext?.findRenderObject();
      screenshot = await service.captureScreenshot(
        renderObject is RenderRepaintBoundary ? renderObject : null,
      );
    }
    if (!context.mounted) return;

    if (isCruxDesktopPlatform) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: desktopWidth,
            height: desktopHeight,
            child: CruxIssueReporterDialog(screenshotPng: screenshot),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const CruxIssueReporterDialog(),
        ),
      );
    }
  }

  @override
  ConsumerState<CruxIssueReporterDialog> createState() =>
      _CruxIssueReporterDialogState();
}

/// The provider values the dialog needs, gathered in one place so the build
/// path (watching) and the submit path (reading) cannot drift apart.
@immutable
class _Inputs {
  const _Inputs({
    required this.strings,
    required this.service,
    required this.session,
    required this.buildInfo,
    required this.diagnosticsReport,
    required this.logBuffer,
    required this.extras,
  });

  final CruxIssueReporterStrings strings;
  final CruxIssueReporterService service;
  final CruxIssueSessionContext session;
  final ApplicationBuildInfo? buildInfo;
  final String? diagnosticsReport;
  final CruxIssueReporterLogBuffer logBuffer;
  final List<CruxIssueCategory> extras;
}

class _CruxIssueReporterDialogState
    extends ConsumerState<CruxIssueReporterDialog> {
  final _titleController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sessionOn = true;
  bool _logOn = true;
  bool _screenshotOn = true;
  bool _previewExpanded = false;
  bool _submitting = false;

  /// On/off state for overlay-contributed categories, keyed by category id.
  /// Absent ids default to on, matching the built-in categories.
  final Map<String, bool> _extraEnabled = {};

  /// The screenshot category tile is hidden on iOS/Android (no file-attach on
  /// the GitHub mobile new-issue form) and on web (no temp-dir reveal).
  bool get _screenshotSupported =>
      isCruxDesktopPlatform && !kIsWeb && widget.screenshotPng != null;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTitleChanged);
  }

  void _onTitleChanged() => setState(() {});

  @override
  void dispose() {
    _titleController
      ..removeListener(_onTitleChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Reads (or watches) every provider the dialog depends on.
  ///
  /// `watch: true` is used from `build` so the dialog rebuilds when a
  /// dependency changes; `watch: false` from the submit handler, where
  /// watching is not permitted.
  _Inputs _inputs({required bool watch}) {
    T get<T>(Provider<T> provider) =>
        watch ? ref.watch(provider) : ref.read(provider);

    final localeTag = cruxLocaleTag(Localizations.localeOf(context));
    final session = get(
      cruxIssueSessionContextProvider,
    ).copyWith(localeTag: localeTag);

    return _Inputs(
      strings: get(cruxIssueReporterStringsProvider),
      service: get(cruxIssueReporterServiceProvider),
      session: session,
      buildInfo: get(cruxIssueReporterBuildInfoProvider),
      diagnosticsReport: get(cruxIssueDiagnosticsReportProvider),
      logBuffer: get(cruxIssueReporterLogBufferProvider),
      extras: get(
        cruxIssueReporterDataProviderProvider,
      ).extraCategories(session),
    );
  }

  /// Builds the enabled markdown categories for the current toggle state. The
  /// App & Environment category is always present (when build info is wired);
  /// Session State and Diagnostic Log follow their toggles;
  /// overlay-contributed categories are appended after the built-ins.
  List<CruxIssueCategory> _enabledCategories(_Inputs inputs) {
    final strings = inputs.strings;
    final service = inputs.service;
    final categories = <CruxIssueCategory>[];

    final info = inputs.buildInfo;
    if (info != null) {
      categories.add(
        service.buildAppEnvCategory(
          title: strings.categoryAppEnv,
          description: strings.categoryAppEnvDescription,
          info: info,
          localeTag: inputs.session.localeTag,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
      );
    }

    if (_sessionOn && inputs.session.isNotEmpty) {
      categories.add(
        service.buildSessionCategory(
          title: strings.categorySession,
          description: strings.categorySessionDescription,
          context: inputs.session,
        ),
      );
    }

    if (_logOn) {
      final report = inputs.diagnosticsReport;
      categories.add(
        report == null
            ? service.buildLogCategory(
                title: strings.categoryLog,
                description: strings.categoryLogDescription,
                buffer: inputs.logBuffer,
                emptyPlaceholder: strings.emptyLogPlaceholder,
              )
            : service.buildDiagnosticsCategory(
                title: strings.categoryLog,
                description: strings.categoryLogDescription,
                report: report,
                buffer: inputs.logBuffer,
                logEmptyPlaceholder: strings.emptySessionLogPlaceholder,
              ),
      );
    }

    for (final extra in inputs.extras) {
      if (_extraEnabled[extra.id] ?? true) categories.add(extra);
    }

    return categories;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final inputs = _inputs(watch: false);
    final strings = inputs.strings;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    final typed = _titleController.text.trim();
    final title = typed.isEmpty ? strings.dialogTitle : typed;
    final body = inputs.service.buildMarkdownBody(_enabledCategories(inputs));

    CruxIssueSubmission? result;
    try {
      result = await inputs.service.submit(
        title: title,
        body: body,
        screenshotPng: _screenshotSupported && _screenshotOn
            ? widget.screenshotPng
            : null,
      );
    } finally {
      // Always dismiss once the submission attempt returns: by the time
      // control reaches here the browser has been launched and the body copied
      // to the clipboard, so a thrown post-launch error (e.g. the screenshot
      // reveal) must not leave the dialog stuck open. The captured
      // messenger/navigator survive the pop, so the toast still shows.
      if (mounted) {
        setState(() => _submitting = false);
        if (navigator.canPop()) navigator.pop();
        if (result != null) {
          messenger?.showSnackBar(
            SnackBar(content: Text(_toastFor(result, strings))),
          );
        }
      }
    }
  }

  /// The submission toast: whether the body was pre-filled into the URL or
  /// left on the clipboard, plus where the screenshot landed when one was
  /// saved.
  String _toastFor(
    CruxIssueSubmission result,
    CruxIssueReporterStrings strings,
  ) {
    final headline = result.bodyPrefilled
        ? strings.openedToastPrefilled
        : strings.openedToast;
    final path = result.screenshotPath;
    if (path == null) return headline;
    return '$headline\n${strings.screenshotSaved(path)}';
  }

  @override
  Widget build(BuildContext context) {
    final inputs = _inputs(watch: true);
    final strings = inputs.strings;
    final previewBody = inputs.service.buildMarkdownBody(
      _enabledCategories(inputs),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: strings.dialogTitle),
        const Divider(height: 1),
        // Wrapped in a ScrollConfiguration whose behaviour enables
        // drag-to-scroll for every pointer kind (trackpad, touch, mouse,
        // stylus) so a two-finger trackpad drag scrolls the body — not just
        // the mouse wheel — and the expanded preview is always reachable. A
        // visible Scrollbar is pinned so there's an obvious affordance when
        // the content overflows.
        Expanded(
          child: ScrollConfiguration(
            behavior: const _DragAnywhereScrollBehavior(),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: kCruxIssueTitleFieldKey,
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: strings.titleFieldLabel,
                        hintText: strings.titleFieldHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 16),
                    _PrivacyCallout(text: strings.privacyNotice),
                    const SizedBox(height: 8),
                    _CategoryTile(
                      title: strings.categoryAppEnv,
                      subtitle: strings.categoryAppEnvDescription,
                      lockedSemantics: strings.lockedCategorySemantics,
                      value: true,
                      locked: true,
                      onChanged: null,
                    ),
                    if (inputs.session.isNotEmpty)
                      _CategoryTile(
                        key: cruxIssueTileKey(
                          CruxIssueReporterService.sessionCategoryId,
                        ),
                        title: strings.categorySession,
                        subtitle: strings.categorySessionDescription,
                        value: _sessionOn,
                        onChanged: (v) => setState(() => _sessionOn = v),
                      ),
                    _CategoryTile(
                      key: cruxIssueTileKey(
                        CruxIssueReporterService.logCategoryId,
                      ),
                      title: strings.categoryLog,
                      subtitle: strings.categoryLogDescription,
                      value: _logOn,
                      onChanged: (v) => setState(() => _logOn = v),
                    ),
                    // Overlay-contributed tiles (e.g. a Pro overlay's "Pro
                    // State"). Each defaults on and toggles independently.
                    for (final extra in inputs.extras)
                      _CategoryTile(
                        key: cruxIssueTileKey(extra.id),
                        title: extra.title,
                        subtitle: extra.description,
                        value: _extraEnabled[extra.id] ?? true,
                        onChanged: (v) =>
                            setState(() => _extraEnabled[extra.id] = v),
                      ),
                    if (_screenshotSupported) ...[
                      _CategoryTile(
                        key: cruxIssueTileKey(kCruxIssueScreenshotCategoryId),
                        title: strings.categoryScreenshot,
                        subtitle: strings.categoryScreenshotDescription,
                        value: _screenshotOn,
                        onChanged: (v) => setState(() => _screenshotOn = v),
                      ),
                      if (_screenshotOn)
                        _ScreenshotThumbnail(png: widget.screenshotPng!),
                    ],
                    const SizedBox(height: 8),
                    _PreviewPane(
                      expanded: _previewExpanded,
                      header: strings.previewHeader,
                      body: previewBody,
                      onToggle: () =>
                          setState(() => _previewExpanded = !_previewExpanded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: Text(strings.cancelButton),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(strings.submitButton),
              ),
            ],
          ),
        ),
      ],
    );

    if (isCruxDesktopPlatform) return content;
    return Scaffold(
      appBar: AppBar(title: Text(strings.dialogTitle)),
      body: SafeArea(child: content),
    );
  }
}

/// Title row with the bug icon and a close button.
class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Icon(Icons.bug_report_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The privacy callout above the category tiles.
class _PrivacyCallout extends StatelessWidget {
  const _PrivacyCallout({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// One category row: a localized title with a trailing switch. When [locked],
/// the switch is fixed on and disabled (App & Environment).
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.locked = false,
    this.lockedSemantics,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool locked;
  final String? lockedSemantics;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = subtitle;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: kCruxIssueReporterMinTouchTarget,
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: description == null
          ? null
          : Text(description, style: theme.textTheme.bodySmall),
      secondary: locked
          ? Tooltip(
              message: lockedSemantics ?? '',
              triggerMode: TooltipTriggerMode.manual,
              child: Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.disabledColor,
                semanticLabel: lockedSemantics,
              ),
            )
          : null,
      value: value,
      onChanged: locked ? null : onChanged,
    );
  }
}

/// Bounded preview of the captured screenshot.
class _ScreenshotThumbnail extends StatelessWidget {
  const _ScreenshotThumbnail({required this.png});

  final Uint8List png;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 160),
        child: Image.memory(
          png,
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
        ),
      ),
    ),
  );
}

/// Collapsible markdown preview of the exact issue body.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.expanded,
    required this.header,
    required this.body,
    required this.onToggle,
  });

  final bool expanded;
  final String header;
  final String body;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: kCruxIssuePreviewToggleKey,
          onTap: onToggle,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kCruxIssueReporterMinTouchTarget,
            ),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    header,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              body,
              key: kCruxIssuePreviewBodyKey,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

/// Scroll behaviour that enables click/drag-to-scroll for every pointer kind —
/// trackpad and touch included, not just the mouse wheel. The default desktop
/// [MaterialScrollBehavior] omits trackpad/touch from [dragDevices], so a
/// two-finger trackpad drag over the reporter body would not scroll it.
class _DragAnywhereScrollBehavior extends MaterialScrollBehavior {
  const _DragAnywhereScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
