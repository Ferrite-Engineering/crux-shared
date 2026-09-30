// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

class _FakeDataProvider implements CruxIssueReporterDataProvider {
  @override
  List<CruxIssueCategory> extraCategories(CruxIssueSessionContext context) => [
    CruxIssueCategory(
      id: 'proState',
      title: 'Pro State (${context.localeTag})',
      markdownBody: 'pro',
    ),
  ];
}

ProviderContainer _container([List<Override> overrides = const []]) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

void main() {
  const config = CruxIssueReporterConfig(
    productName: 'LintCrux',
    repositorySlug: 'Ferrite-Engineering/lintcrux',
  );

  group('cruxIssueReporterConfigProvider', () {
    test('fails loudly when unwired', () {
      // Riverpod wraps a provider-body throw before it reaches the caller,
      // so assert on the surfaced message rather than the wrapper type.
      Object? thrown;
      try {
        _container().read(cruxIssueReporterConfigProvider);
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect(
        thrown.toString(),
        contains('cruxIssueReporterConfigProvider'),
      );
    });

    test('the error message names the provider and the remedy', () {
      final error = CruxIssueReporterUnconfiguredError();
      expect(error.message, contains('cruxIssueReporterConfigProvider'));
      expect(error.message, contains('owner/repo'));
    });

    test('a product override supplies the configuration', () {
      final container = _container([
        cruxIssueReporterConfigProvider.overrideWithValue(config),
      ]);
      expect(container.read(cruxIssueReporterConfigProvider), config);
    });
  });

  group('cruxIssueReporterServiceProvider', () {
    test('is built from the configured slug', () {
      final container = _container([
        cruxIssueReporterConfigProvider.overrideWithValue(config),
      ]);
      final service = container.read(cruxIssueReporterServiceProvider);
      expect(service.config.repositorySlug, config.repositorySlug);
      expect(
        service.buildIssueUrl(title: 't', platform: 'linux').path,
        '/Ferrite-Engineering/lintcrux/issues/new',
      );
    });

    test('propagates the unconfigured failure', () {
      Object? thrown;
      try {
        _container().read(cruxIssueReporterServiceProvider);
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect(
        thrown.toString(),
        contains('cruxIssueReporterConfigProvider'),
      );
    });
  });

  group('package defaults', () {
    test('strings default to English', () {
      expect(
        _container().read(cruxIssueReporterStringsProvider),
        isA<CruxIssueReporterStringsEn>(),
      );
    });

    test('the session seam contributes nothing', () {
      expect(
        _container().read(cruxIssueSessionContextProvider),
        CruxIssueSessionContext.empty,
      );
    });

    test('the overlay seam contributes no extra categories', () {
      final dataProvider = _container().read(
        cruxIssueReporterDataProviderProvider,
      );
      expect(dataProvider, isA<NoopCruxIssueReporterDataProvider>());
      expect(
        dataProvider.extraCategories(CruxIssueSessionContext.empty),
        isEmpty,
      );
    });

    test('build info and diagnostics report are absent', () {
      final container = _container();
      expect(container.read(cruxIssueReporterBuildInfoProvider), isNull);
      expect(container.read(cruxIssueDiagnosticsReportProvider), isNull);
    });

    test('the log buffer is the process-wide instance', () {
      expect(
        _container().read(cruxIssueReporterLogBufferProvider),
        same(CruxIssueReporterLogBuffer.instance),
      );
    });

    test('the screenshot boundary key is a stable labelled GlobalKey', () {
      final container = _container();
      final key = container.read(cruxAppScreenshotBoundaryKeyProvider);
      expect(key, same(container.read(cruxAppScreenshotBoundaryKeyProvider)));
      expect(key.toString(), contains('cruxAppScreenshotBoundary'));
    });
  });

  group('product and overlay seams are independent', () {
    test('a product override supplies the session snapshot', () {
      final container = _container([
        cruxIssueSessionContextProvider.overrideWithValue(
          const CruxIssueSessionContext(
            fields: [CruxIssueField(label: 'Projects', value: '2')],
          ),
        ),
      ]);
      final session = container.read(cruxIssueSessionContextProvider);
      expect(session.isNotEmpty, isTrue);
      expect(session.fields.single.label, 'Projects');
    });

    test('an overlay override adds categories over the same snapshot', () {
      final container = _container([
        cruxIssueSessionContextProvider.overrideWithValue(
          const CruxIssueSessionContext(
            localeTag: 'ja',
            fields: [CruxIssueField(label: 'Projects', value: '2')],
          ),
        ),
        cruxIssueReporterDataProviderProvider.overrideWithValue(
          _FakeDataProvider(),
        ),
      ]);
      final extras = container
          .read(cruxIssueReporterDataProviderProvider)
          .extraCategories(container.read(cruxIssueSessionContextProvider));
      expect(extras.single.id, 'proState');
      // The overlay localizes from the snapshot's locale tag, never from a
      // BuildContext.
      expect(extras.single.title, 'Pro State (ja)');
    });

    test('a build-info override feeds the App & Environment category', () {
      const info = ApplicationBuildInfo(
        version: '0.9.0',
        buildNumber: '7',
        gitShortSha: 'feedbee',
        os: 'Linux',
        architecture: 'x86_64',
        flutterSdkVersion: '3.44.2',
        dartSdkVersion: '3.12.2',
      );
      final container = _container([
        cruxIssueReporterBuildInfoProvider.overrideWithValue(info),
      ]);
      expect(container.read(cruxIssueReporterBuildInfoProvider), info);
    });
  });

  group('locale tags', () {
    test('cruxLocaleTag joins language and country with an underscore', () {
      expect(
        cruxLocaleTag(
          const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        ),
        'zh_CN',
      );
      expect(cruxLocaleTag(const Locale('ja')), 'ja');
      expect(
        cruxLocaleTag(
          const Locale.fromSubtags(languageCode: 'ko'),
        ),
        'ko',
      );
    });

    test('cruxPlatformLocaleTag returns a non-empty tag', () {
      expect(cruxPlatformLocaleTag(), isNotEmpty);
    });
  });
}
