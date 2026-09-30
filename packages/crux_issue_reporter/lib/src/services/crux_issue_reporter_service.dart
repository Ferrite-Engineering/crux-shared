// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_io/crux_io.dart' show revealInFileManager;
import 'package:crux_issue_reporter/src/models/crux_issue_category.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_reporter_config.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_session_context.dart';
import 'package:crux_issue_reporter/src/services/crux_issue_reporter_log_buffer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart' show Level;
import 'package:url_launcher/url_launcher.dart';

/// Signature for opening a URL; injectable so tests can capture the launch
/// without a platform channel. Defaults to `url_launcher`'s [launchUrl].
typedef CruxUrlLauncherFn = Future<bool> Function(Uri url);

/// Signature for writing plain text to the clipboard; injectable for tests.
typedef CruxClipboardWriter = Future<void> Function(String text);

/// Result of a [CruxIssueReporterService.submit] call, for the dialog's
/// snackbar and for assertions in tests.
@immutable
class CruxIssueSubmission {
  /// Creates a submission result.
  const CruxIssueSubmission({
    required this.issueUrl,
    required this.clipboardBody,
    this.screenshotPath,
    this.bodyPrefilled = false,
  });

  /// The GitHub new-issue URL that was opened.
  final Uri issueUrl;

  /// The markdown body copied to the clipboard.
  final String clipboardBody;

  /// Where the screenshot PNG was written, or `null` when no screenshot was
  /// included (toggle off, mobile, or capture failed).
  final String? screenshotPath;

  /// Whether the diagnostic body was pre-filled into the GitHub new-issue URL
  /// (true) or left on the clipboard for the user to paste (false, the
  /// fallback used when the body would push the URL past the safe length cap).
  final bool bodyPrefilled;

  @override
  String toString() =>
      'CruxIssueSubmission(prefilled: $bodyPrefilled, '
      'screenshot: $screenshotPath)';
}

/// Collects diagnostic context, assembles the GitHub issue body, copies it to
/// the clipboard, opens the pre-filled GitHub new-issue URL, and (on the
/// screenshot path) saves the PNG to the OS temp directory and reveals it in
/// the file manager.
///
/// The body is pre-filled into the URL when it fits under the configured
/// [CruxIssueReporterConfig.maxIssueUrlLength] (so the GitHub form opens
/// already populated), and otherwise omitted — GitHub's new-issue form drops
/// or rejects bodies in over-long GET URLs. In both cases the body is also
/// copied to the clipboard, so an over-sized report (typically a long
/// diagnostic log) can still be pasted by hand.
///
/// **Privacy contract.** Nothing this service renders reaches into private
/// file contents, signal values or filesystem paths. The App & Environment
/// section is build and host metadata; the Session State section renders only
/// the label/value pairs the product's session contributor supplied, which are
/// bound by the same contract (see [CruxIssueSessionContext]).
class CruxIssueReporterService {
  /// Creates the service. The seams default to the production
  /// implementations; tests inject fakes.
  const CruxIssueReporterService({
    required this.config,
    CruxUrlLauncherFn? urlLauncher,
    CruxClipboardWriter? clipboardWriter,
    this.now,
  }) : _urlLauncher = urlLauncher ?? launchUrl,
       _clipboardWriter = clipboardWriter ?? _defaultClipboardWriter;

  /// The per-product configuration: repository slug, labels, template, product
  /// name and URL length cap.
  final CruxIssueReporterConfig config;

  final CruxUrlLauncherFn _urlLauncher;
  final CruxClipboardWriter _clipboardWriter;

  /// Optional clock injection for deterministic screenshot file names.
  final DateTime Function()? now;

  /// Stable category id for the App & Environment section.
  static const String appEnvCategoryId = 'appEnv';

  /// Stable category id for the Session State section.
  static const String sessionCategoryId = 'session';

  /// Stable category id for the Diagnostic Log section.
  static const String logCategoryId = 'log';

  /// Number of WARNING-or-higher entries pulled from the ring buffer.
  static const int warningLogLineCount = 100;

  /// Number of any-level entries pulled from the ring buffer for context.
  static const int contextLogLineCount = 20;

  static Future<void> _defaultClipboardWriter(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  // ── category builders ──────────────────────────────────────────────────────

  /// Builds the always-on App & Environment category from build metadata.
  ///
  /// The field labels are intentionally English: the body is read by the
  /// maintainers in the GitHub repository, not by the reporting user.
  CruxIssueCategory buildAppEnvCategory({
    required String title,
    required ApplicationBuildInfo info,
    required String localeTag,
    required double devicePixelRatio,
    String? description,
  }) {
    final body = StringBuffer()
      ..writeln(
        '- **App:** ${config.productName}',
      )
      ..writeln(
        '- **App version:** ${info.version} (build ${info.buildNumber})',
      )
      ..writeln('- **Build SHA:** ${info.gitShortSha}')
      ..writeln('- **Platform:** ${platformLabel()}')
      ..writeln('- **OS:** ${info.os}')
      ..writeln('- **Architecture:** ${info.architecture}')
      ..writeln('- **Screen DPI:** ${devicePixelRatio.toStringAsFixed(2)}x')
      ..writeln('- **Locale:** $localeTag')
      ..writeln('- **Flutter:** ${info.flutterSdkVersion}')
      ..write('- **Dart:** ${info.dartSdkVersion}');
    return CruxIssueCategory(
      id: appEnvCategoryId,
      title: title,
      description: description,
      markdownBody: '$body',
    );
  }

  /// Builds the Session State category from the product-contributed [context].
  ///
  /// Renders one markdown bullet per [CruxIssueField]. Carries counts, format
  /// names and display names only — never file paths or private file content.
  CruxIssueCategory buildSessionCategory({
    required String title,
    required CruxIssueSessionContext context,
    String? description,
  }) {
    final body = StringBuffer();
    for (var i = 0; i < context.fields.length; i++) {
      final field = context.fields[i];
      final line = '- **${field.label}:** ${field.value}';
      if (i == context.fields.length - 1) {
        body.write(line);
      } else {
        body.writeln(line);
      }
    }
    return CruxIssueCategory(
      id: sessionCategoryId,
      title: title,
      description: description,
      markdownBody: '$body',
    );
  }

  /// Builds the Diagnostic Log category from the ring [buffer]: the last
  /// [warningLogLineCount] WARNING+ entries plus the last
  /// [contextLogLineCount] entries at any level, de-duplicated by timestamp
  /// and rendered as a fenced code block.
  CruxIssueCategory buildLogCategory({
    required String title,
    required CruxIssueReporterLogBuffer buffer,
    required String emptyPlaceholder,
    String? description,
  }) => CruxIssueCategory(
    id: logCategoryId,
    title: title,
    description: description,
    markdownBody: _renderRecentLog(buffer, emptyPlaceholder),
  );

  /// Builds the combined **Diagnostics** category: a snapshot [report] (the
  /// same structured text a product's diagnostics panel would copy) followed
  /// by the recent session log from the ring [buffer]. The report is always
  /// present; the log shows [logEmptyPlaceholder] when nothing was captured.
  ///
  /// The caller supplies [report] because building it requires reading
  /// app-level Riverpod providers; this service stays free of product
  /// dependencies.
  CruxIssueCategory buildDiagnosticsCategory({
    required String title,
    required String report,
    required CruxIssueReporterLogBuffer buffer,
    required String logEmptyPlaceholder,
    String? description,
  }) {
    final body = StringBuffer()
      ..writeln('```text')
      ..writeln(report.trimRight())
      ..writeln('```')
      ..writeln()
      ..writeln('**Session log**')
      ..writeln()
      ..write(_renderRecentLog(buffer, logEmptyPlaceholder));
    return CruxIssueCategory(
      id: logCategoryId,
      title: title,
      description: description,
      markdownBody: '$body',
    );
  }

  /// Renders the most-recent ring-buffer entries (last
  /// [warningLogLineCount] WARNING+ plus last [contextLogLineCount] at any
  /// level, de-duplicated by timestamp, oldest first) as a fenced code block,
  /// or [emptyPlaceholder] when the buffer is empty.
  String _renderRecentLog(
    CruxIssueReporterLogBuffer buffer,
    String emptyPlaceholder,
  ) {
    final warnings = buffer.recentEntries(
      warningLogLineCount,
      minLevel: Level.WARNING,
    );
    final anyLevel = buffer.recentEntries(contextLogLineCount);

    final byTimestamp = <DateTime, CruxIssueLogEntry>{};
    for (final e in [...warnings, ...anyLevel]) {
      byTimestamp[e.timestamp] = e;
    }
    final merged = byTimestamp.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (merged.isEmpty) return emptyPlaceholder;

    final body = StringBuffer()..writeln('```text');
    for (final e in merged) {
      body.writeln(
        '[${e.timestamp.toIso8601String()}] ${e.level.name} '
        '${e.loggerName.isEmpty ? 'root' : e.loggerName}: ${e.message}',
      );
    }
    body.write('```');
    return '$body';
  }

  // ── assembly ───────────────────────────────────────────────────────────────

  /// Joins enabled [categories] into the final GitHub issue body markdown,
  /// each under a `## <title>` heading.
  String buildMarkdownBody(List<CruxIssueCategory> categories) {
    final buf = StringBuffer();
    for (var i = 0; i < categories.length; i++) {
      final c = categories[i];
      buf
        ..writeln('## ${c.title}')
        ..writeln()
        ..writeln(c.markdownBody);
      if (i != categories.length - 1) buf.writeln();
    }
    return buf.toString().trimRight();
  }

  /// Builds the GitHub new-issue URL with the title, the configured default
  /// labels plus the platform label, and the configured issue template.
  ///
  /// When [body] is non-empty it is also embedded as the issue body — unless
  /// doing so would push the URL past
  /// [CruxIssueReporterConfig.maxIssueUrlLength], in which case the body is
  /// omitted (the caller still copies it to the clipboard). See the class doc.
  Uri buildIssueUrl({required String title, String? platform, String? body}) {
    final template = config.issueTemplate;
    final params = <String, String>{
      'title': title,
      'labels': [...config.defaultLabels, platform ?? platformLabel()].join(
        ',',
      ),
      if (template != null && template.isNotEmpty) 'template': template,
    };
    final base = config.newIssueUrl;
    final withoutBody = base.replace(queryParameters: params);
    if (body == null || body.isEmpty) return withoutBody;

    final withBody = base.replace(
      queryParameters: <String, String>{...params, 'body': body},
    );
    return withBody.toString().length <= config.maxIssueUrlLength
        ? withBody
        : withoutBody;
  }

  /// The platform label used in the issue labels: `macos`, `linux`,
  /// `windows`, `ios`, `android` or `web`.
  static String platformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  // ── screenshot capture ─────────────────────────────────────────────────────

  /// Captures the widget subtree under [boundary] as PNG bytes at 2x pixel
  /// ratio. Returns `null` when the boundary is not yet laid out or capture
  /// fails. Callers on web/mobile never reach here — the dialog hides the
  /// Screenshot tile there.
  Future<Uint8List?> captureScreenshot(RenderRepaintBoundary? boundary) async {
    if (boundary == null) return null;
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } on Object {
      return null;
    }
  }

  // ── submission ─────────────────────────────────────────────────────────────

  /// Copies [body] to the clipboard, opens the GitHub new-issue URL, and —
  /// when [screenshotPng] is non-null — writes the PNG to the OS temp dir and
  /// reveals it in the file manager on desktop.
  Future<CruxIssueSubmission> submit({
    required String title,
    required String body,
    Uint8List? screenshotPng,
  }) async {
    await _clipboardWriter(body);

    String? screenshotPath;
    if (screenshotPng != null && !kIsWeb) {
      screenshotPath = await _saveScreenshot(screenshotPng);
      // Best-effort, like every reveal: a file manager that will not open
      // never fails the submission.
      if (screenshotPath != null) await revealInFileManager(screenshotPath);
    }

    final url = buildIssueUrl(title: title, body: body);
    await _urlLauncher(url);

    return CruxIssueSubmission(
      issueUrl: url,
      clipboardBody: body,
      screenshotPath: screenshotPath,
      bodyPrefilled: url.queryParameters.containsKey('body'),
    );
  }

  Future<String?> _saveScreenshot(Uint8List png) async {
    try {
      final stamp = (now ?? DateTime.now)()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp('[:.]'), '-');
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          '${config.resolvedScreenshotFilePrefix}-issue-$stamp.png';
      await File(path).writeAsBytes(png, flush: true);
      return path;
    } on Object {
      return null;
    }
  }
}
