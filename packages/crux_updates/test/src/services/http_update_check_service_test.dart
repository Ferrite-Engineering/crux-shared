// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final config = CruxUpdateConfig(
    productName: 'NetCrux',
    manifestUri: 'https://updates.example.test/manifest.json',
    downloadPageUri: 'https://example.test/download',
  );

  final requests = <http.BaseRequest>[];

  setUp(requests.clear);

  String manifest({
    String version = '1.2.0',
    String minSupported = '1.0.0',
    bool mandatory = false,
    String? serverTime = '2026-09-15T12:00:00Z',
  }) => jsonEncode({
    'latest': {
      'version': version,
      'channel': 'stable',
      'mandatory': mandatory,
      'min_supported_version': minSupported,
      'changelog_url': 'https://example.test/releases/$version',
      'server_time': ?serverTime,
    },
  });

  http.Client respondWith(String body, {int status = 200}) =>
      MockClient((request) async {
        requests.add(request);
        return http.Response(body, status);
      });

  http.Client failWith(Exception error) => MockClient((request) async {
    requests.add(request);
    throw error;
  });

  HttpUpdateCheckService serviceFor(
    String currentVersion, {
    required http.Client client,
    void Function(DateTime)? onServerTimeObserved,
    CruxUpdateConfig? withConfig,
  }) => HttpUpdateCheckService(
    config: withConfig ?? config,
    currentVersion: currentVersion,
    osName: 'TestOS',
    onServerTimeObserved: onServerTimeObserved,
    client: client,
  );

  group('happy path', () {
    test(
      'returns UpdateInfo when a newer, min-supported version exists',
      () async {
        final info = await serviceFor(
          '1.1.0',
          client: respondWith(manifest()),
        ).checkForUpdate();
        expect(info, isNotNull);
        expect(info!.version, '1.2.0');
        expect(info.mandatory, isFalse);
      },
    );

    test('returns null when already on the latest version', () async {
      expect(
        await serviceFor(
          '1.2.0',
          client: respondWith(manifest()),
        ).checkForUpdate(),
        isNull,
      );
    });

    test('returns null when current is newer than the manifest', () async {
      expect(
        await serviceFor(
          '1.3.0',
          client: respondWith(manifest()),
        ).checkForUpdate(),
        isNull,
      );
    });

    test('fetches the configured manifest URI', () async {
      await serviceFor(
        '1.1.0',
        client: respondWith(manifest()),
      ).checkForUpdate();
      expect(requests.single.url, config.manifestUri);
    });

    test(
      'below the min-supported floor surfaces a forced (mandatory) update',
      () async {
        // A newer version always surfaces; being below the floor forces it
        // non-dismissible even though the manifest's own flag is false.
        final info = await serviceFor(
          '1.0.0',
          client: respondWith(manifest(minSupported: '1.1.0')),
        ).checkForUpdate();
        expect(info, isNotNull);
        expect(info!.version, '1.2.0');
        expect(info.mandatory, isTrue);
      },
    );

    test(
      'at or above the floor surfaces a normal (dismissible) update',
      () async {
        final info = await serviceFor(
          '1.1.0',
          client: respondWith(manifest(minSupported: '1.1.0')),
        ).checkForUpdate();
        expect(info, isNotNull);
        expect(info!.mandatory, isFalse);
      },
    );

    test('a manifest-declared mandatory update stays mandatory', () async {
      final info = await serviceFor(
        '1.1.0',
        client: respondWith(manifest(mandatory: true)),
      ).checkForUpdate();
      expect(info!.mandatory, isTrue);
    });

    test('sends only product, version and OS via the User-Agent', () async {
      await serviceFor(
        '1.1.0',
        client: respondWith(manifest()),
      ).checkForUpdate();
      expect(requests.single.headers['User-Agent'], 'NetCrux/1.1.0 (TestOS)');
    });

    test('omits the OS suffix when no OS name is known', () async {
      final service = HttpUpdateCheckService(
        config: config,
        currentVersion: '1.1.0',
        client: respondWith(manifest()),
      );
      await service.checkForUpdate();
      expect(requests.single.headers['User-Agent'], 'NetCrux/1.1.0');
    });
  });

  group('server-time observation (beta-expiry hardening)', () {
    test('reports server_time when an update is available', () async {
      DateTime? observed;
      await serviceFor(
        '1.1.0',
        client: respondWith(manifest()),
        onServerTimeObserved: (t) => observed = t,
      ).checkForUpdate();
      expect(observed, DateTime.parse('2026-09-15T12:00:00Z'));
    });

    test(
      'reports server_time even when already current (null result)',
      () async {
        DateTime? observed;
        final info = await serviceFor(
          '1.2.0',
          client: respondWith(manifest()),
          onServerTimeObserved: (t) => observed = t,
        ).checkForUpdate();
        expect(info, isNull); // up to date
        expect(observed, DateTime.parse('2026-09-15T12:00:00Z'));
      },
    );

    test('does not report when the manifest omits server_time', () async {
      DateTime? observed;
      await serviceFor(
        '1.1.0',
        client: respondWith(manifest(serverTime: null)),
        onServerTimeObserved: (t) => observed = t,
      ).checkForUpdate();
      expect(observed, isNull);
    });

    test('does not report on a failed fetch', () async {
      DateTime? observed;
      await expectLater(
        serviceFor(
          '1.1.0',
          client: respondWith('nope', status: 500),
          onServerTimeObserved: (t) => observed = t,
        ).checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
      expect(observed, isNull);
    });
  });

  group('failure paths throw a typed UpdateCheckException', () {
    test('non-200 response carries the status in the reason', () async {
      await expectLater(
        serviceFor(
          '1.0.0',
          client: respondWith('nope', status: 503),
        ).checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.reason,
            'reason',
            'http 503',
          ),
        ),
      );
    });

    test('malformed manifest body', () async {
      await expectLater(
        serviceFor('1.0.0', client: respondWith('{not json')).checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.reason,
            'reason',
            'parse',
          ),
        ),
      );
    });

    test('a well-formed but latest-less manifest is a parse failure', () async {
      await expectLater(
        serviceFor('1.0.0', client: respondWith('{"foo": 1}')).checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.reason,
            'reason',
            'parse',
          ),
        ),
      );
    });

    test('a network error is wrapped, not leaked raw', () async {
      await expectLater(
        serviceFor(
          '1.0.0',
          client: failWith(const _FakeSocketException()),
        ).checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>()
              .having((e) => e.reason, 'reason', 'network')
              .having((e) => e.cause, 'cause', isA<_FakeSocketException>()),
        ),
      );
    });

    test('a timeout is wrapped as a network failure', () async {
      final slow = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(manifest(), 200);
      });
      final service = HttpUpdateCheckService(
        config: config.copyWith(checkTimeout: const Duration(milliseconds: 1)),
        currentVersion: '1.0.0',
        client: slow,
      );
      await expectLater(
        service.checkForUpdate(),
        throwsA(
          isA<UpdateCheckException>()
              .having((e) => e.reason, 'reason', 'network')
              .having((e) => e.cause, 'cause', isA<TimeoutException>()),
        ),
      );
    });

    test('UpdateCheckException.toString names the reason only', () {
      const e = UpdateCheckException('parse', 'secret internals');
      expect(e.toString(), 'UpdateCheckException(parse)');
    });
  });
}

class _FakeSocketException implements Exception {
  const _FakeSocketException();
}
