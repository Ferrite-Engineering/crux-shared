// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _config = CruxUpdateConfig(
  productName: 'NetCrux',
  manifestUri: 'https://updates.example.test/manifest.json',
  downloadPageUri: 'https://example.test/download',
);

const _buildInfo = ApplicationBuildInfo(
  version: '1.0.0',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.2',
);

/// Records every call so launch / periodic / manual paths can be distinguished.
class _FakeUpdateCheckService implements UpdateCheckService {
  _FakeUpdateCheckService({this.result, this.error});

  UpdateInfo? result;
  Object? error;
  int calls = 0;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    calls++;
    // ignore: only_throw_errors -- tests inject both Exception and Error types.
    if (error != null) throw error!;
    return result;
  }
}

/// A seat's edition that a test can change mid-session, the way a licence key
/// being entered or lapsing changes it in a product.
class _MutableEdition extends Notifier<UpdateEdition> {
  @override
  UpdateEdition build() => UpdateEdition.openCore;

  UpdateEdition get value => state;

  set value(UpdateEdition edition) => state = edition;
}

final _mutableEditionProvider =
    NotifierProvider<_MutableEdition, UpdateEdition>(_MutableEdition.new);

void main() {
  final available = UpdateInfo.fromJson({'version': '9.9.9'})!;

  ProviderContainer makeContainer({
    required bool autoCheck,
    required UpdateCheckService service,
    CruxUpdateConfig? config,
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        cruxUpdateConfigProvider.overrideWithValue(config ?? _config),
        updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
        autoUpdateCheckEnabledProvider.overrideWith((_) async => autoCheck),
        updateCheckServiceProvider.overrideWithValue(service),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('launch check', () {
    test(
      'runs and surfaces an available update when auto-check is on',
      () async {
        final fake = _FakeUpdateCheckService(result: available);
        final container = makeContainer(autoCheck: true, service: fake)
          ..read(updateStatusProvider); // instantiate -> launch check
        await pumpEventQueue();

        expect(fake.calls, greaterThanOrEqualTo(1));
        expect(
          container.read(updateStatusProvider),
          UpdateStatusAvailable(available),
        );
      },
    );

    test('resolves to current when no newer version exists', () async {
      final fake = _FakeUpdateCheckService(); // result == null
      final container = makeContainer(autoCheck: true, service: fake)
        ..read(updateStatusProvider);
      await pumpEventQueue();

      expect(fake.calls, greaterThanOrEqualTo(1));
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });

    test('starts out current before the check resolves', () {
      final fake = _FakeUpdateCheckService(result: available);
      final container = makeContainer(autoCheck: true, service: fake);
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });

    test('toggle off suppresses the launch/auto check', () async {
      final fake = _FakeUpdateCheckService(result: available);
      final container = makeContainer(autoCheck: false, service: fake)
        ..read(updateStatusProvider);
      await pumpEventQueue();

      expect(fake.calls, 0);
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });
  });

  group('runScheduledCheck (periodic-fire path)', () {
    test('does nothing when auto-check is off', () async {
      final fake = _FakeUpdateCheckService(result: available);
      final container = makeContainer(autoCheck: false, service: fake);
      final notifier = container.read(updateStatusProvider.notifier);
      await pumpEventQueue();

      await notifier.runScheduledCheck();

      expect(fake.calls, 0);
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });

    test('runs when auto-check is on', () async {
      final fake = _FakeUpdateCheckService(result: available);
      final container = makeContainer(autoCheck: true, service: fake);
      final notifier = container.read(updateStatusProvider.notifier);
      await pumpEventQueue();
      final before = fake.calls;

      await notifier.runScheduledCheck();

      expect(fake.calls, greaterThan(before));
    });

    test('the periodic timer re-checks on the configured interval', () async {
      // Real time with a tiny interval rather than a fake clock: the package
      // takes no fake_async dependency, and the notifier only needs to prove
      // that the timer drives the same gated path.
      final fake = _FakeUpdateCheckService(result: available);
      makeContainer(
        autoCheck: true,
        service: fake,
        config: _config.copyWith(
          checkInterval: const Duration(milliseconds: 10),
        ),
      ).read(updateStatusProvider);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fake.calls, greaterThan(1)); // launch check plus timer ticks
    });

    test('the timer is cancelled when the container is disposed', () async {
      final fake = _FakeUpdateCheckService(result: available);
      final container = ProviderContainer(
        overrides: [
          cruxUpdateConfigProvider.overrideWithValue(
            _config.copyWith(checkInterval: const Duration(milliseconds: 10)),
          ),
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          autoUpdateCheckEnabledProvider.overrideWith((_) async => true),
          updateCheckServiceProvider.overrideWithValue(fake),
        ],
      )..read(updateStatusProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final afterLaunch = fake.calls;

      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(fake.calls, afterLaunch);
    });
  });

  group('checkNow (manual path)', () {
    test('always runs even when auto-check is off', () async {
      final fake = _FakeUpdateCheckService(result: available);
      final container = makeContainer(autoCheck: false, service: fake);
      final notifier = container.read(updateStatusProvider.notifier);
      await pumpEventQueue();
      expect(fake.calls, 0); // launch suppressed

      await notifier.checkNow();

      expect(fake.calls, 1);
      expect(
        container.read(updateStatusProvider),
        UpdateStatusAvailable(available),
      );
    });

    test('publishes the checking state while the fetch is in flight', () async {
      final fake = _FakeUpdateCheckService(result: available);
      final container = makeContainer(autoCheck: false, service: fake);
      final notifier = container.read(updateStatusProvider.notifier);
      await pumpEventQueue();

      final pending = notifier.checkNow();
      expect(
        container.read(updateStatusProvider),
        const UpdateStatusChecking(),
      );
      await pending;
      expect(
        container.read(updateStatusProvider),
        UpdateStatusAvailable(available),
      );
    });
  });

  group('error handling', () {
    test(
      'typed UpdateCheckException maps to error state, never thrown',
      () async {
        final fake = _FakeUpdateCheckService(
          error: const UpdateCheckException('network'),
        );
        final container = makeContainer(autoCheck: false, service: fake);
        final notifier = container.read(updateStatusProvider.notifier);
        await pumpEventQueue();

        await expectLater(notifier.checkNow(), completes);
        expect(container.read(updateStatusProvider), const UpdateStatusError());
      },
    );

    test('a raw error is also contained as the error state', () async {
      final fake = _FakeUpdateCheckService(error: StateError('boom'));
      final container = makeContainer(autoCheck: false, service: fake);
      final notifier = container.read(updateStatusProvider.notifier);
      await pumpEventQueue();

      await expectLater(notifier.checkNow(), completes);
      expect(container.read(updateStatusProvider), const UpdateStatusError());
    });

    test('a later successful check clears the error state', () async {
      final fake = _FakeUpdateCheckService(
        error: const UpdateCheckException('network'),
      );
      final container = makeContainer(autoCheck: false, service: fake);
      final notifier = container.read(updateStatusProvider.notifier);
      await notifier.checkNow();
      expect(container.read(updateStatusProvider), const UpdateStatusError());

      fake.error = null;
      await notifier.checkNow();

      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });
  });

  group('edition filter', () {
    // The running build is 1.0.0 (`_buildInfo`). Open core last changed in
    // 1.0.0 itself, and 1.0.1 changed only paid features.
    final paidOnly = UpdateInfo.fromJson({
      'version': '1.0.1',
      'open_core_version': '1.0.0',
    })!;

    ProviderContainer editionContainer({
      required UpdateCheckService service,
    }) => makeContainer(
      autoCheck: false,
      service: service,
      extra: [
        updateEditionProvider.overrideWith(
          (ref) => ref.watch(_mutableEditionProvider),
        ),
      ],
    );

    test('an open-core seat is withheld a release that changed only paid '
        'features, and the fetch still ran', () async {
      final fake = _FakeUpdateCheckService(result: paidOnly);
      final container = editionContainer(service: fake);

      await container.read(updateStatusProvider.notifier).checkNow();

      expect(fake.calls, 1);
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });

    test('an unlocked seat is offered the same release', () async {
      final fake = _FakeUpdateCheckService(result: paidOnly);
      final container = editionContainer(service: fake);
      container.read(_mutableEditionProvider.notifier).value =
          UpdateEdition.unlocked;

      await container.read(updateStatusProvider.notifier).checkNow();

      expect(
        container.read(updateStatusProvider),
        UpdateStatusAvailable(paidOnly),
      );
    });

    test('an open-core seat is offered a release that changed open core '
        'since its build', () async {
      final changed = paidOnly.copyWith(openCoreVersion: '1.0.1');
      final fake = _FakeUpdateCheckService(result: changed);
      final container = editionContainer(service: fake);

      await container.read(updateStatusProvider.notifier).checkNow();

      expect(
        container.read(updateStatusProvider),
        UpdateStatusAvailable(changed),
      );
    });

    test(
      'an open-core seat is offered a mandatory release regardless',
      () async {
        final critical = paidOnly.copyWith(mandatory: true);
        final fake = _FakeUpdateCheckService(result: critical);
        final container = editionContainer(service: fake);

        await container.read(updateStatusProvider.notifier).checkNow();

        expect(
          container.read(updateStatusProvider),
          UpdateStatusAvailable(critical),
        );
      },
    );

    test('unlocking mid-session re-presents the held release without a '
        'second fetch', () async {
      final fake = _FakeUpdateCheckService(result: paidOnly);
      final container = editionContainer(service: fake);
      await container.read(updateStatusProvider.notifier).checkNow();
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());

      container.read(_mutableEditionProvider.notifier).value =
          UpdateEdition.unlocked;

      expect(
        container.read(updateStatusProvider),
        UpdateStatusAvailable(paidOnly),
      );
      expect(fake.calls, 1);
    });

    test('a licence lapsing mid-session withdraws the offer', () async {
      final fake = _FakeUpdateCheckService(result: paidOnly);
      final container = editionContainer(service: fake);
      container.read(_mutableEditionProvider.notifier).value =
          UpdateEdition.unlocked;
      await container.read(updateStatusProvider.notifier).checkNow();
      expect(
        container.read(updateStatusProvider),
        UpdateStatusAvailable(paidOnly),
      );

      container.read(_mutableEditionProvider.notifier).value =
          UpdateEdition.openCore;

      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
      expect(fake.calls, 1);
    });

    test('an edition change does not mask a failed check', () async {
      final fake = _FakeUpdateCheckService(
        error: const UpdateCheckException('network'),
      );
      final container = editionContainer(service: fake);
      await container.read(updateStatusProvider.notifier).checkNow();

      container.read(_mutableEditionProvider.notifier).value =
          UpdateEdition.unlocked;

      expect(container.read(updateStatusProvider), const UpdateStatusError());
    });

    test('a check that finds nothing stays current across an edition '
        'change', () async {
      final fake = _FakeUpdateCheckService();
      final container = editionContainer(service: fake);
      await container.read(updateStatusProvider.notifier).checkNow();

      container.read(_mutableEditionProvider.notifier).value =
          UpdateEdition.unlocked;

      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });
  });

  group('edition filter through the live provider graph', () {
    // Real HttpUpdateCheckService, real manifest JSON: proves the field is
    // read off the wire, that the below-floor path reaches the filter already
    // marked mandatory, and that a withheld seat still records server time.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<ProviderContainer> liveContainer(String manifest) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final observed = <DateTime>[];
      final container = ProviderContainer(
        overrides: [
          cruxUpdateConfigProvider.overrideWithValue(_config),
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          autoUpdateCheckEnabledProvider.overrideWith((_) async => false),
          updateEditionProvider.overrideWithValue(UpdateEdition.openCore),
          observedServerTimeSinkProvider.overrideWithValue(observed.add),
          updateHttpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response(manifest, 200)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(updateStatusProvider.notifier).checkNow();
      expect(
        observed,
        [DateTime.parse('2026-09-15T12:00:00Z')],
        reason: 'a withheld seat must still feed the beta-expiry clock',
      );
      return container;
    }

    test('withholds a paid-only release from the open-core seat', () async {
      final container = await liveContainer('''
{"latest": {"version": "1.0.1", "open_core_version": "1.0.0",
            "server_time": "2026-09-15T12:00:00Z"}}''');
      expect(container.read(updateStatusProvider), const UpdateStatusCurrent());
    });

    test('a build below min_supported_version is offered the paid-only '
        'release, non-dismissibly', () async {
      final container = await liveContainer('''
{"latest": {"version": "1.2.1", "open_core_version": "0.9.0",
            "min_supported_version": "1.1.0",
            "server_time": "2026-09-15T12:00:00Z"}}''');
      final status = container.read(updateStatusProvider);
      expect(status, isA<UpdateStatusAvailable>());
      expect((status as UpdateStatusAvailable).info.mandatory, isTrue);
    });
  });
}
