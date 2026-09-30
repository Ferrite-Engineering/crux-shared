// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

const _buildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.4',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.2',
);

const _config = CruxIssueReporterConfig(
  productName: 'NetCrux',
  repositorySlug: 'Ferrite-Engineering/netcrux',
);

const _strings = CruxIssueReporterStringsEn();

CruxIssueReporterService _service({
  CruxIssueReporterConfig config = _config,
  CruxUrlLauncherFn? urlLauncher,
  CruxClipboardWriter? clipboardWriter,
}) => CruxIssueReporterService(
  config: config,
  urlLauncher: urlLauncher,
  clipboardWriter: clipboardWriter,
);

void main() {
  group('CruxIssueReporterService category builders', () {
    test('App & Environment lists product, version, SHA, DPI, locale', () {
      final cat = _service().buildAppEnvCategory(
        title: 'App & Environment',
        info: _buildInfo,
        localeTag: 'ja',
        devicePixelRatio: 2,
      );
      expect(cat.id, CruxIssueReporterService.appEnvCategoryId);
      expect(cat.markdownBody, contains('**App:** NetCrux'));
      expect(cat.markdownBody, contains('1.2.3 (build 42)'));
      expect(cat.markdownBody, contains('abc1234'));
      expect(cat.markdownBody, contains('2.00x'));
      expect(cat.markdownBody, contains('Locale:** ja'));
      expect(cat.markdownBody, contains('3.44.2'));
      expect(cat.markdownBody, contains('3.12.2'));
    });

    test('Session State renders one bullet per contributed field', () {
      final cat = _service().buildSessionCategory(
        title: 'Session State',
        context: const CruxIssueSessionContext(
          localeTag: 'en',
          fields: [
            CruxIssueField(label: 'Open tabs', value: '3'),
            CruxIssueField(label: 'Active file format', value: 'VCD'),
            CruxIssueField(label: 'Signals in active tab', value: '128'),
            CruxIssueField(label: 'Active decoders', value: 'SPI #1'),
          ],
        ),
      );
      expect(cat.id, CruxIssueReporterService.sessionCategoryId);
      expect(cat.markdownBody, contains('- **Open tabs:** 3'));
      expect(cat.markdownBody, contains('VCD'));
      expect(cat.markdownBody, contains('128'));
      expect(cat.markdownBody, contains('SPI #1'));
    });

    test(
      'PRIVACY: a Session State body carries no file paths',
      () {
        // The privacy contract of the reporter: counts, formats and display
        // names only. The rendered body must contain no path separators, so a
        // contributor that accidentally passed `/Users/me/sim/dump.vcd`
        // through would fail here (and in the consuming product's own suite,
        // where this assertion is repeated over the real contributor).
        final cat = _service().buildSessionCategory(
          title: 'Session State',
          context: const CruxIssueSessionContext(
            localeTag: 'en',
            fields: [
              CruxIssueField(label: 'Open tabs', value: '3'),
              CruxIssueField(label: 'Active file format', value: 'VCD'),
              CruxIssueField(label: 'Active decoders', value: 'SPI #1, I2C #2'),
            ],
          ),
        );
        expect(cat.markdownBody, isNot(contains('/')));
        expect(cat.markdownBody, isNot(contains(r'\')));
      },
    );

    test('an empty session context renders an empty body', () {
      final cat = _service().buildSessionCategory(
        title: 'Session State',
        context: CruxIssueSessionContext.empty,
      );
      expect(cat.markdownBody, isEmpty);
    });

    test(
      'Diagnostic Log renders a fenced code block and dedups by timestamp',
      () {
        final ts = DateTime.utc(2026, 6, 6, 12);
        final buffer = CruxIssueReporterLogBuffer(capacity: 100)
          // The same timestamp appears in both the WARNING+ slice and the
          // any-level slice; it must be de-duplicated.
          ..add(
            CruxIssueLogEntry(
              timestamp: ts,
              level: Level.WARNING,
              loggerName: 'a',
              message: 'dup warning',
            ),
          )
          ..add(
            CruxIssueLogEntry(
              timestamp: ts.add(const Duration(seconds: 1)),
              level: Level.INFO,
              loggerName: 'b',
              message: 'info line',
            ),
          );
        final cat = _service().buildLogCategory(
          title: 'Diagnostic Log',
          buffer: buffer,
          emptyPlaceholder: _strings.emptyLogPlaceholder,
        );
        expect(cat.markdownBody, startsWith('```text'));
        expect(cat.markdownBody, endsWith('```'));
        expect('dup warning'.allMatches(cat.markdownBody).length, 1);
        expect(cat.markdownBody, contains('info line'));
      },
    );

    test('keeps the last 100 WARNING+ plus the last 20 at any level', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 1000);
      // 150 warnings, then 30 info lines. The body should carry the last 100
      // warnings and the last 20 info lines.
      for (var i = 0; i < 150; i++) {
        buffer.add(
          CruxIssueLogEntry(
            timestamp: DateTime.utc(2026).add(Duration(seconds: i)),
            level: Level.WARNING,
            loggerName: 'w',
            message: 'warn$i',
          ),
        );
      }
      for (var i = 0; i < 30; i++) {
        buffer.add(
          CruxIssueLogEntry(
            timestamp: DateTime.utc(2026).add(Duration(seconds: 1000 + i)),
            level: Level.INFO,
            loggerName: 'i',
            message: 'info$i',
          ),
        );
      }
      final body = _service()
          .buildLogCategory(
            title: 'Diagnostic Log',
            buffer: buffer,
            emptyPlaceholder: _strings.emptyLogPlaceholder,
          )
          .markdownBody;

      expect(body, contains('warn50'));
      expect(body, isNot(contains('warn49')));
      expect(body, contains('info10'));
      expect(body, isNot(contains('info9\n')));
    });

    test('empty Diagnostic Log shows the supplied placeholder', () {
      final cat = _service().buildLogCategory(
        title: 'Diagnostic Log',
        buffer: CruxIssueReporterLogBuffer(capacity: 10),
        emptyPlaceholder: 'NONE',
      );
      expect(cat.markdownBody, 'NONE');
    });
  });

  group('CruxIssueReporterService diagnostics category', () {
    test('includes the report snapshot and the empty-log placeholder', () {
      final category = _service().buildDiagnosticsCategory(
        title: 'Diagnostics',
        report: '=== Report ===\nMemory: 1 MB\n===',
        buffer: CruxIssueReporterLogBuffer(capacity: 10),
        logEmptyPlaceholder: _strings.emptySessionLogPlaceholder,
      );
      expect(category.id, CruxIssueReporterService.logCategoryId);
      expect(category.markdownBody, contains('=== Report ==='));
      expect(category.markdownBody, contains('Memory: 1 MB'));
      expect(category.markdownBody, contains('**Session log**'));
      expect(
        category.markdownBody,
        contains('(no errors or warnings logged this session)'),
      );
    });

    test('renders captured log entries under the session log', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 10)
        ..add(
          CruxIssueLogEntry(
            timestamp: DateTime.utc(2026, 6, 6, 12),
            level: Level.SEVERE,
            loggerName: 'flutter',
            message: 'RangeError (index)',
          ),
        );
      final category = _service().buildDiagnosticsCategory(
        title: 'Diagnostics',
        report: '=== Report ===',
        buffer: buffer,
        logEmptyPlaceholder: _strings.emptySessionLogPlaceholder,
      );
      expect(category.markdownBody, contains('SEVERE flutter: RangeError'));
      expect(category.markdownBody, contains('```text'));
    });

    test('a root-logger entry renders as "root"', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 10)
        ..add(
          CruxIssueLogEntry(
            timestamp: DateTime.utc(2026, 6, 6, 12),
            level: Level.SEVERE,
            loggerName: '',
            message: 'anonymous',
          ),
        );
      final category = _service().buildLogCategory(
        title: 'Diagnostic Log',
        buffer: buffer,
        emptyPlaceholder: _strings.emptyLogPlaceholder,
      );
      expect(category.markdownBody, contains('SEVERE root: anonymous'));
    });
  });

  group('CruxIssueReporterService markdown body', () {
    test('joins enabled categories under ## headings, omits toggled-off', () {
      const categories = [
        CruxIssueCategory(id: 'a', title: 'Alpha', markdownBody: 'aaa'),
        CruxIssueCategory(id: 'b', title: 'Beta', markdownBody: 'bbb'),
      ];
      final body = _service().buildMarkdownBody(categories);
      expect(body, contains('## Alpha'));
      expect(body, contains('aaa'));
      expect(body, contains('## Beta'));
      // A category not in the list is excluded.
      expect(body, isNot(contains('Gamma')));
      // Trailing whitespace is trimmed.
      expect(body, body.trimRight());
    });

    test('an empty category list yields an empty body', () {
      expect(_service().buildMarkdownBody(const []), isEmpty);
    });
  });

  group('CruxIssueReporterService URL construction', () {
    test('builds the new-issue URL from the configured repository slug', () {
      final url = _service().buildIssueUrl(
        title: 'crash on open',
        platform: 'linux',
      );
      expect(url.host, 'github.com');
      expect(url.path, '/Ferrite-Engineering/netcrux/issues/new');
      expect(url.queryParameters['title'], 'crash on open');
      expect(url.queryParameters['labels'], 'bug,user-report,linux');
      expect(url.queryParameters.containsKey('template'), isFalse);
    });

    test('the slug is configuration, not a hardcoded product', () {
      for (final slug in const [
        'Ferrite-Engineering/netcrux',
        'Ferrite-Engineering/simcrux',
        'Ferrite-Engineering/lintcrux',
      ]) {
        final url = _service(
          config: _config.copyWith(repositorySlug: slug),
        ).buildIssueUrl(title: 't', platform: 'linux');
        expect(url.path, '/$slug/issues/new');
      }
    });

    test('honours a custom host, template and default labels', () {
      final url = _service(
        config: const CruxIssueReporterConfig(
          productName: 'SimCrux',
          repositorySlug: 'acme/internal',
          host: 'github.example.com',
          issueTemplate: 'bug.yml',
          defaultLabels: ['triage'],
        ),
      ).buildIssueUrl(title: 't', platform: 'macos');
      expect(url.host, 'github.example.com');
      expect(url.queryParameters['template'], 'bug.yml');
      expect(url.queryParameters['labels'], 'triage,macos');
    });

    test('falls back to the live platform label when none is supplied', () {
      final url = _service().buildIssueUrl(title: 't');
      expect(
        url.queryParameters['labels'],
        'bug,user-report,${CruxIssueReporterService.platformLabel()}',
      );
    });

    test('omits the body param when no body is supplied', () {
      final url = _service().buildIssueUrl(title: 't', platform: 'linux');
      expect(url.queryParameters.containsKey('body'), isFalse);
    });

    test('pre-fills a short body into the URL', () {
      final url = _service().buildIssueUrl(
        title: 't',
        platform: 'linux',
        body: '## Section\n\nbody text',
      );
      expect(url.queryParameters['body'], '## Section\n\nbody text');
    });

    test('drops an over-long body so the URL stays under the length cap', () {
      final url = _service().buildIssueUrl(
        title: 't',
        platform: 'linux',
        body: 'x' * 20000,
      );
      expect(url.queryParameters.containsKey('body'), isFalse);
      expect(url.toString().length, lessThanOrEqualTo(6000));
    });

    test('the length cap is configurable', () {
      final url = _service(
        config: _config.copyWith(maxIssueUrlLength: 100),
      ).buildIssueUrl(title: 't', platform: 'linux', body: 'x' * 200);
      expect(url.queryParameters.containsKey('body'), isFalse);
    });
  });

  group('CruxIssueReporterService submit', () {
    test('copies the body to the clipboard and launches the URL', () async {
      String? clipboard;
      Uri? launched;
      final result = await _service(
        clipboardWriter: (text) async => clipboard = text,
        urlLauncher: (uri) async {
          launched = uri;
          return true;
        },
      ).submit(title: 'my title', body: '## Section\n\nbody text');

      expect(clipboard, '## Section\n\nbody text');
      expect(launched, isNotNull);
      expect(launched?.queryParameters['title'], 'my title');
      expect(launched?.queryParameters['body'], '## Section\n\nbody text');
      expect(launched?.path, '/Ferrite-Engineering/netcrux/issues/new');
      expect(result.clipboardBody, contains('body text'));
      expect(result.screenshotPath, isNull);
      expect(result.bodyPrefilled, isTrue);
      expect(result.issueUrl, launched);
    });

    test(
      'reports bodyPrefilled=false and still copies when body is over-long',
      () async {
        String? clipboard;
        Uri? launched;
        final hugeBody = 'x' * 20000;
        final result = await _service(
          clipboardWriter: (text) async => clipboard = text,
          urlLauncher: (uri) async {
            launched = uri;
            return true;
          },
        ).submit(title: 'my title', body: hugeBody);

        expect(clipboard, hugeBody);
        expect(launched?.queryParameters.containsKey('body'), isFalse);
        expect(result.bodyPrefilled, isFalse);
      },
    );
  });

  test('captureScreenshot returns null for a null boundary', () async {
    expect(await _service().captureScreenshot(null), isNull);
  });

  test('platformLabel returns a known platform token', () {
    expect(
      CruxIssueReporterService.platformLabel(),
      anyOf('macos', 'linux', 'windows', 'web', 'ios', 'android', 'unknown'),
    );
  });
}
