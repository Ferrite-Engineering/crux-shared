// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Fake overlay data provider that always contributes one extra category, so
/// the dialog's extra-tile rendering can be exercised without a Pro build.
class _FakeDataProvider implements CruxIssueReporterDataProvider {
  @override
  List<CruxIssueCategory> extraCategories(CruxIssueSessionContext context) =>
      const [
        CruxIssueCategory(
          id: 'proState',
          title: 'Pro State',
          description: 'Active Pro features.',
          markdownBody: 'xyz',
        ),
      ];
}

/// Alternate string bundle. The package ships no ARB, so the "locale sweep"
/// is a strings sweep: swapping this in must not change layout behaviour or
/// throw, the same property the per-locale sweep checks in the products.
class _LongStrings extends CruxIssueReporterStringsEn {
  const _LongStrings();

  @override
  String get dialogTitle => '提交问题报告（Beta 测试反馈）';

  @override
  String get titleFieldLabel => '問題の概要をここに入力してください';

  @override
  String get privacyNotice =>
      '더 많은 컨텍스트는 문제를 재현하는 데 도움이 됩니다. 공유하고 싶지 않은 항목은 '
      '해제하십시오. 파일 내용이나 파일 경로는 절대 포함되지 않습니다.';

  @override
  String get categorySession => '会话状态（标签页、格式、计数）';

  @override
  String get previewHeader => 'プレビュー：送信される本文';

  @override
  String get submitButton => '제출하기';
}

// 1x1 transparent PNG so Image.memory decodes cleanly in the screenshot tile.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmM'
  'IQAAAABJRU5ErkJggg==',
);

const _buildInfo = ApplicationBuildInfo(
  version: '1.0.0',
  buildNumber: '1',
  gitShortSha: 'deadbee',
  os: 'TestOS',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.2',
);

const _config = CruxIssueReporterConfig(
  productName: 'NetCrux',
  repositorySlug: 'Ferrite-Engineering/netcrux',
);

const _session = CruxIssueSessionContext(
  fields: [
    CruxIssueField(label: 'Open projects', value: '2'),
    CruxIssueField(label: 'Active file format', value: 'JSON'),
  ],
);

List<Override> _baseOverrides({
  CruxIssueSessionContext session = _session,
  List<Override> extra = const [],
}) => [
  cruxIssueReporterConfigProvider.overrideWithValue(_config),
  cruxIssueReporterBuildInfoProvider.overrideWithValue(_buildInfo),
  cruxIssueSessionContextProvider.overrideWithValue(session),
  cruxIssueReporterLogBufferProvider.overrideWithValue(
    CruxIssueReporterLogBuffer(capacity: 10),
  ),
  ...extra,
];

Widget _host({
  Uint8List? screenshot,
  List<Override> overrides = const [],
  TextDirection textDirection = TextDirection.ltr,
  double textScale = 1,
}) => ProviderScope(
  overrides: overrides.isEmpty ? _baseOverrides() : overrides,
  child: MaterialApp(
    builder: (context, child) => Directionality(
      textDirection: textDirection,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: Scaffold(
      body: CruxIssueReporterDialog(screenshotPng: screenshot),
    ),
  ),
);

CruxIssueReporterStrings _stringsOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(CruxIssueReporterDialog)),
    ).read(cruxIssueReporterStringsProvider);

String _previewBody(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byKey(kCruxIssuePreviewBodyKey)).data ??
    '';

Future<void> _expandPreview(WidgetTester tester) async {
  // The disclosure sits at the bottom of the scrollable body, below the fold
  // on the default 800x600 test surface.
  await tester.ensureVisible(find.byKey(kCruxIssuePreviewToggleKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(kCruxIssuePreviewToggleKey));
  await tester.pumpAndSettle();
}

void main() {
  group('layout sweep', () {
    // Phone / tablet / desktop widths, both text directions, both string
    // bundles, at 1.0x and the clamped 1.5x accessibility ceiling.
    const widths = <double>[360, 800, 1400];

    for (final width in widths) {
      for (final rtl in const [false, true]) {
        for (final long in const [false, true]) {
          for (final scale in const <double>[1, 1.5]) {
            testWidgets(
              'renders without overflow (${width}px, '
              'rtl=$rtl, longStrings=$long, textScale=$scale)',
              (tester) async {
                tester.view.physicalSize = Size(width, 900);
                tester.view.devicePixelRatio = 1;
                addTearDown(tester.view.resetPhysicalSize);
                addTearDown(tester.view.resetDevicePixelRatio);

                await tester.pumpWidget(
                  _host(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    textScale: scale,
                    overrides: _baseOverrides(
                      extra: long
                          ? [
                              cruxIssueReporterStringsProvider
                                  .overrideWithValue(const _LongStrings()),
                            ]
                          : const [],
                    ),
                  ),
                );
                await tester.pumpAndSettle();

                expect(tester.takeException(), isNull);
                expect(find.byType(CruxIssueReporterDialog), findsOneWidget);
              },
            );
          }
        }
      }
    }
  });

  testWidgets('the injected string bundle drives every visible label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        overrides: _baseOverrides(
          extra: [
            cruxIssueReporterStringsProvider.overrideWithValue(
              const _LongStrings(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    const strings = _LongStrings();
    expect(find.text(strings.dialogTitle), findsWidgets);
    expect(find.text(strings.titleFieldLabel), findsOneWidget);
    expect(find.text(strings.privacyNotice), findsOneWidget);
    expect(find.text(strings.categorySession), findsOneWidget);
    expect(find.text(strings.submitButton), findsOneWidget);
    // No English default leaked through where the bundle overrode it.
    expect(
      find.text(const CruxIssueReporterStringsEn().dialogTitle),
      findsNothing,
    );
  });

  testWidgets('Session and Diagnostic Log tiles toggle on tap', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    for (final id in const [
      CruxIssueReporterService.sessionCategoryId,
      CruxIssueReporterService.logCategoryId,
    ]) {
      final tile = find.byKey(cruxIssueTileKey(id));
      expect(tile, findsOneWidget);
      final tileSwitch = find.descendant(
        of: tile,
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tileSwitch).value, isTrue);

      await tester.tap(tile);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(tileSwitch).value, isFalse);
    }
  });

  testWidgets('App & Environment is locked on and has no toggle key', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final strings = _stringsOf(tester);
    final lockedTile = find.ancestor(
      of: find.text(strings.categoryAppEnv),
      matching: find.byType(SwitchListTile),
    );
    expect(lockedTile, findsOneWidget);
    final tile = tester.widget<SwitchListTile>(lockedTile);
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('every category tile clears the 44 dp touch-target floor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        overrides: _baseOverrides(
          extra: [
            cruxIssueReporterDataProviderProvider.overrideWithValue(
              _FakeDataProvider(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final id in const [
      CruxIssueReporterService.sessionCategoryId,
      CruxIssueReporterService.logCategoryId,
      'proState',
    ]) {
      final size = tester.getSize(find.byKey(cruxIssueTileKey(id)));
      expect(
        size.height,
        greaterThanOrEqualTo(44),
        reason: 'tile "$id" must be at least 44 dp tall on touch',
      );
    }
    expect(
      tester.getSize(find.byKey(kCruxIssuePreviewToggleKey)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('preview pane updates live when a category is toggled off', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await _expandPreview(tester);

    final strings = _stringsOf(tester);
    expect(find.byKey(kCruxIssuePreviewBodyKey), findsOneWidget);
    expect(_previewBody(tester), contains('## ${strings.categorySession}'));
    expect(_previewBody(tester), contains('Open projects'));
    expect(_previewBody(tester), contains('## ${strings.categoryAppEnv}'));

    await tester.tap(
      find.byKey(
        cruxIssueTileKey(CruxIssueReporterService.sessionCategoryId),
      ),
    );
    await tester.pump();

    expect(
      _previewBody(tester),
      isNot(contains('## ${strings.categorySession}')),
    );
    // The locked App & Environment section is still there.
    expect(_previewBody(tester), contains('## ${strings.categoryAppEnv}'));
  });

  testWidgets('the preview is collapsed until the disclosure is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.byKey(kCruxIssuePreviewBodyKey), findsNothing);
    await _expandPreview(tester);
    expect(find.byKey(kCruxIssuePreviewBodyKey), findsOneWidget);
  });

  testWidgets('renders a tile for each overlay-contributed extra category', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        overrides: _baseOverrides(
          extra: [
            cruxIssueReporterDataProviderProvider.overrideWithValue(
              _FakeDataProvider(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(cruxIssueTileKey('proState'));
    expect(tile, findsOneWidget);

    await _expandPreview(tester);
    expect(_previewBody(tester), contains('## Pro State'));

    await tester.tap(tile);
    await tester.pump();
    expect(_previewBody(tester), isNot(contains('## Pro State')));
  });

  testWidgets('the Session tile is absent when the product wires no seam', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(overrides: _baseOverrides(session: CruxIssueSessionContext.empty)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        cruxIssueTileKey(CruxIssueReporterService.sessionCategoryId),
      ),
      findsNothing,
    );
    await _expandPreview(tester);
    expect(
      _previewBody(tester),
      isNot(contains('## ${_stringsOf(tester).categorySession}')),
    );
  });

  testWidgets('PRIVACY: the preview body carries no file paths', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await _expandPreview(tester);

    final body = _previewBody(tester);
    expect(body, isNot(contains('/Users/')));
    expect(body, isNot(contains('.vcd')));
    // The session section itself is path-free.
    final strings = _stringsOf(tester);
    final sessionSection = body.split('## ${strings.categorySession}').last;
    expect(sessionSection.split('\n##').first, isNot(contains('/')));
  });

  testWidgets('Screenshot tile is hidden on mobile platforms', (tester) async {
    // The default test target platform is android, so the screenshot tile is
    // hidden even when screenshot bytes are supplied.
    await tester.pumpWidget(_host(screenshot: _pngBytes));
    await tester.pumpAndSettle();

    expect(
      find.byKey(cruxIssueTileKey(kCruxIssueScreenshotCategoryId)),
      findsNothing,
    );
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('Screenshot tile and thumbnail appear on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(_host(screenshot: _pngBytes));
      await tester.pumpAndSettle();

      expect(
        find.byKey(cruxIssueTileKey(kCruxIssueScreenshotCategoryId)),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Toggling the tile off hides the thumbnail.
      await tester.tap(
        find.byKey(cruxIssueTileKey(kCruxIssueScreenshotCategoryId)),
      );
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    } finally {
      // Reset before the test body returns; flutter_test verifies foundation
      // debug vars are unset before tearDowns run.
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the diagnostics-report seam is folded into the log section', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        overrides: _baseOverrides(
          extra: [
            cruxIssueDiagnosticsReportProvider.overrideWithValue(
              '=== NetCrux Diagnostics ===',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expandPreview(tester);

    expect(_previewBody(tester), contains('=== NetCrux Diagnostics ==='));
    expect(_previewBody(tester), contains('**Session log**'));
  });

  testWidgets('Submit copies, launches and shows the pre-filled toast', (
    tester,
  ) async {
    String? clipboard;
    Uri? launched;
    final service = CruxIssueReporterService(
      config: _config,
      clipboardWriter: (text) async => clipboard = text,
      urlLauncher: (uri) async {
        launched = uri;
        return true;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _baseOverrides(
          extra: [
            cruxIssueReporterServiceProvider.overrideWithValue(service),
          ],
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const Dialog(
                      child: SizedBox(
                        width: CruxIssueReporterDialog.desktopWidth,
                        height: CruxIssueReporterDialog.desktopHeight,
                        child: CruxIssueReporterDialog(),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CruxIssueReporterDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(kCruxIssueTitleFieldKey),
      'crash on open',
    );
    await tester.pump();

    // The FilledButton is the Submit action (Cancel is a TextButton).
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(CruxIssueReporterDialog), findsNothing);
    expect(launched, isNotNull);
    expect(launched?.path, '/Ferrite-Engineering/netcrux/issues/new');
    expect(launched?.queryParameters['title'], 'crash on open');
    expect(clipboard, isNotNull);
    expect(clipboard, contains('## App & Environment'));
    expect(clipboard, contains('## Session State'));

    // A small diagnostic body fits in the URL, so the pre-filled toast shows.
    expect(launched?.queryParameters['body'], isNotNull);
    expect(
      find.text(const CruxIssueReporterStringsEn().openedToastPrefilled),
      findsOneWidget,
    );
  });

  testWidgets('an empty summary falls back to the dialog title', (
    tester,
  ) async {
    Uri? launched;
    final service = CruxIssueReporterService(
      config: _config,
      clipboardWriter: (_) async {},
      urlLauncher: (uri) async {
        launched = uri;
        return true;
      },
    );

    await tester.pumpWidget(
      _host(
        overrides: _baseOverrides(
          extra: [
            cruxIssueReporterServiceProvider.overrideWithValue(service),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      launched?.queryParameters['title'],
      const CruxIssueReporterStringsEn().dialogTitle,
    );
  });

  testWidgets('a toggled-off category is excluded from the submitted body', (
    tester,
  ) async {
    String? clipboard;
    final service = CruxIssueReporterService(
      config: _config,
      clipboardWriter: (text) async => clipboard = text,
      urlLauncher: (_) async => true,
    );

    await tester.pumpWidget(
      _host(
        overrides: _baseOverrides(
          extra: [
            cruxIssueReporterServiceProvider.overrideWithValue(service),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        cruxIssueTileKey(CruxIssueReporterService.sessionCategoryId),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(clipboard, contains('## App & Environment'));
    expect(clipboard, isNot(contains('## Session State')));
  });

  testWidgets('the App & Environment section is omitted without build info', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        overrides: [
          cruxIssueReporterConfigProvider.overrideWithValue(_config),
          cruxIssueSessionContextProvider.overrideWithValue(_session),
          cruxIssueReporterLogBufferProvider.overrideWithValue(
            CruxIssueReporterLogBuffer(capacity: 10),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _expandPreview(tester);

    expect(tester.takeException(), isNull);
    expect(
      _previewBody(tester),
      isNot(contains('## ${_stringsOf(tester).categoryAppEnv}')),
    );
  });
}
