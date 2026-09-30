// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderException;
import 'package:flutter_test/flutter_test.dart';

final _config = CruxUpdateConfig(
  productName: 'NetCrux',
  manifestUri: 'https://updates.example.test/manifest.json',
  downloadPageUri: 'https://example.test/download',
);

const _buildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.2',
);

ProviderContainer _container({List<Override> overrides = const []}) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('cruxUpdateConfigProvider', () {
    test('throws until the product overrides it', () {
      // Riverpod wraps a provider's own failure in a ProviderException; the
      // wiring mistake itself is the UnimplementedError inside it.
      expect(
        () => _container().read(cruxUpdateConfigProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });

    test('the failure message points at the override', () {
      expect(
        () => _container().read(cruxUpdateConfigProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => (e.exception as UnimplementedError).message,
            'message',
            allOf(
              contains('cruxUpdateConfigProvider'),
              contains('Override it'),
            ),
          ),
        ),
      );
    });

    test('an override supplies the product configuration', () {
      final container = _container(
        overrides: [cruxUpdateConfigProvider.overrideWithValue(_config)],
      );
      expect(container.read(cruxUpdateConfigProvider), _config);
    });
  });

  group('cruxUpdateStringsProvider', () {
    test('defaults to English named after the configured product', () {
      final container = _container(
        overrides: [cruxUpdateConfigProvider.overrideWithValue(_config)],
      );
      expect(
        container.read(cruxUpdateStringsProvider).bannerMessage('1.2.0'),
        'NetCrux 1.2.0 is available.',
      );
    });

    test('a product override replaces the whole string set', () {
      final container = _container(
        overrides: [
          cruxUpdateConfigProvider.overrideWithValue(_config),
          cruxUpdateStringsProvider.overrideWithValue(
            const CruxUpdateStringsEn(productName: 'Localized'),
          ),
        ],
      );
      expect(
        container.read(cruxUpdateStringsProvider).bannerMessage('1.2.0'),
        startsWith('Localized'),
      );
    });
  });

  group('updateBuildInfoProvider', () {
    test('defaults to null (no build info wired)', () async {
      expect(await _container().read(updateBuildInfoProvider.future), isNull);
    });

    test('an override supplies the running build metadata', () async {
      final container = _container(
        overrides: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
        ],
      );
      expect(
        await container.read(updateBuildInfoProvider.future),
        _buildInfo,
      );
    });
  });

  group('autoUpdateCheckEnabledProvider', () {
    test('defaults to enabled', () async {
      expect(
        await _container().read(autoUpdateCheckEnabledProvider.future),
        isTrue,
      );
    });

    test('an override projects the product setting', () async {
      final container = _container(
        overrides: [
          autoUpdateCheckEnabledProvider.overrideWith((_) async => false),
        ],
      );
      expect(
        await container.read(autoUpdateCheckEnabledProvider.future),
        isFalse,
      );
    });
  });

  group('observedServerTimeSinkProvider', () {
    test('defaults to a no-op that swallows the observation', () {
      final sink = _container().read(observedServerTimeSinkProvider);
      expect(() => sink(DateTime.utc(2026, 9, 15)), returnsNormally);
    });

    test('an override receives the observed time', () {
      final observed = <DateTime>[];
      final container = _container(
        overrides: [
          observedServerTimeSinkProvider.overrideWithValue(observed.add),
        ],
      );
      container.read(observedServerTimeSinkProvider)(DateTime.utc(2026, 9, 15));
      expect(observed, [DateTime.utc(2026, 9, 15)]);
    });
  });

  group('updateUrlLauncherProvider', () {
    test('the unbound default throws rather than silently doing nothing', () {
      final launcher = _container().read(updateUrlLauncherProvider);
      expect(
        () => launcher(Uri.parse('https://example.test')),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('an override receives the URI', () async {
      final opened = <Uri>[];
      final container = _container(
        overrides: [
          updateUrlLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      await container.read(updateUrlLauncherProvider)(
        Uri.parse('https://example.test/release'),
      );
      expect(opened, [Uri.parse('https://example.test/release')]);
    });
  });

  group('updateEditionProvider', () {
    test('defaults to unlocked, so an unbound product offers everything', () {
      expect(_container().read(updateEditionProvider), UpdateEdition.unlocked);
    });

    test('an override is honoured', () {
      final container = _container(
        overrides: [
          updateEditionProvider.overrideWithValue(UpdateEdition.openCore),
        ],
      );
      expect(container.read(updateEditionProvider), UpdateEdition.openCore);
    });
  });

  group('updateHttpClientProvider', () {
    test('yields a client and closes it on dispose', () {
      final container = ProviderContainer();
      expect(container.read(updateHttpClientProvider), isNotNull);
      expect(container.dispose, returnsNormally);
    });
  });
}
