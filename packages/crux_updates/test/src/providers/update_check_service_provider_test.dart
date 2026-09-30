// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderException;
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

const _manifestBody = '''
{"latest": {"version": "2.0.0", "min_supported_version": "1.0.0",
            "server_time": "2026-09-15T12:00:00Z"}}''';

void main() {
  // The provider gates on defaultTargetPlatform, whose value in the test
  // harness is host-dependent — pin it per test.
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  ProviderContainer container({
    CruxUpdateConfig? config,
    List<Override> extra = const [],
  }) {
    final c = ProviderContainer(
      overrides: [
        cruxUpdateConfigProvider.overrideWithValue(config ?? _config),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('platform gating', () {
    test('yields Noop on iOS by default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final c = container(
        extra: [updateBuildInfoProvider.overrideWith((_) async => _buildInfo)],
      );
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });

    test('yields Noop on Android by default', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final c = container(
        extra: [updateBuildInfoProvider.overrideWith((_) async => _buildInfo)],
      );
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });

    test('yields Noop in a browser, whatever the platform or config', () async {
      // A web tab runs the deployed build and the manifest describes desktop
      // releases, so there is nothing to offer — and the manifest GET's
      // `User-Agent` fails the updates Worker's CORS preflight on Safari and
      // Firefox, so every page load logged a blocked fetch. `checkOnMobile`
      // is a mobile opt-in and does not reach here: a phone browser is still
      // a browser.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        config: _config.copyWith(checkOnMobile: true),
        extra: [
          updateHostIsWebProvider.overrideWithValue(true),
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
        ],
      );
      await c.read(updateBuildInfoProvider.future);
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });

    test(
      'checkOnMobile opts a mobile build back into the live check',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final c = container(
          config: _config.copyWith(checkOnMobile: true),
          extra: [
            updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          ],
        );
        await c.read(updateBuildInfoProvider.future);
        expect(
          c.read(updateCheckServiceProvider),
          isA<HttpUpdateCheckService>(),
        );
      },
    );
  });

  group('build-info gating', () {
    test('yields Noop until build info resolves', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        extra: [
          // A build-info future that never completes -> value stays null.
          updateBuildInfoProvider.overrideWith(
            (_) => Completer<ApplicationBuildInfo?>().future,
          ),
        ],
      );
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });

    test('yields Noop when the product never wires build info', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container();
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });

    test(
      'yields the live service on desktop once build info is available',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final c = container(
          extra: [
            updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          ],
        );
        await c.read(updateBuildInfoProvider.future);
        final service = c.read(updateCheckServiceProvider);
        expect(service, isA<HttpUpdateCheckService>());
        expect((service as HttpUpdateCheckService).currentVersion, '1.0.0');
        expect(service.osName, 'macOS 15.0');
        expect(service.config, _config);
      },
    );
  });

  group('end-to-end through the provider graph', () {
    test(
      'fetches with the injected client and reports the server time',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final requests = <http.BaseRequest>[];
        final observed = <DateTime>[];
        final c = container(
          extra: [
            updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
            observedServerTimeSinkProvider.overrideWithValue(observed.add),
            updateHttpClientProvider.overrideWithValue(
              MockClient((request) async {
                requests.add(request);
                return http.Response(_manifestBody, 200);
              }),
            ),
          ],
        );
        await c.read(updateBuildInfoProvider.future);

        final info = await c.read(updateCheckServiceProvider).checkForUpdate();

        expect(info!.version, '2.0.0');
        expect(requests.single.url, _config.manifestUri);
        expect(
          requests.single.headers['User-Agent'],
          contains('NetCrux/1.0.0'),
        );
        expect(observed, [DateTime.parse('2026-09-15T12:00:00Z')]);
      },
    );

    test('the server-time sink survives the provider being disposed', () async {
      // Regression guard: the sink must be captured at construction, not read
      // through `ref` inside the post-fetch callback.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final observed = <DateTime>[];
      final gate = Completer<void>();
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          observedServerTimeSinkProvider.overrideWithValue(observed.add),
          updateHttpClientProvider.overrideWithValue(
            MockClient((_) async {
              await gate.future;
              return http.Response(_manifestBody, 200);
            }),
          ),
        ],
      );
      await c.read(updateBuildInfoProvider.future);
      final service = c.read(updateCheckServiceProvider);

      final pending = service.checkForUpdate();
      c.invalidate(updateCheckServiceProvider);
      gate.complete();

      expect((await pending)!.version, '2.0.0');
      expect(observed, [DateTime.parse('2026-09-15T12:00:00Z')]);
    });

    test('a malformed manifest surfaces the typed exception', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          updateHttpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('{oops', 200)),
          ),
        ],
      );
      await c.read(updateBuildInfoProvider.future);
      await expectLater(
        c.read(updateCheckServiceProvider).checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
    });
  });

  group('policy constraints', () {
    Future<ProviderContainer> live({required UpdatePolicy policy}) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          updatePolicyProvider.overrideWithValue(policy),
        ],
      );
      await c.read(updateBuildInfoProvider.future);
      return c;
    }

    test('an absent policy yields the bare live service', () async {
      final c = await live(policy: UpdatePolicy.absent);
      expect(c.read(updateCheckServiceProvider), isA<HttpUpdateCheckService>());
    });

    test('the default binding is absent, so nothing is wrapped', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        extra: [updateBuildInfoProvider.overrideWith((_) async => _buildInfo)],
      );
      await c.read(updateBuildInfoProvider.future);
      expect(c.read(updatePolicyProvider), UpdatePolicy.absent);
      expect(c.read(updateCheckServiceProvider), isA<HttpUpdateCheckService>());
    });

    test('a configured channel wraps the live service', () async {
      final c = await live(
        policy: const UpdatePolicy(channel: UpdateChannelPolicy.stable),
      );
      expect(
        c.read(updateCheckServiceProvider),
        isA<PolicyConstrainedUpdateCheckService>(),
      );
    });

    test('the mirror replaces the endpoint and nothing else', () async {
      final mirror = Uri.parse('https://mirror.corp.test/netcrux.json');
      final requests = <http.BaseRequest>[];
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          updatePolicyProvider.overrideWithValue(
            UpdatePolicy(manifestUri: mirror),
          ),
          updateHttpClientProvider.overrideWithValue(
            MockClient((request) async {
              requests.add(request);
              return http.Response(_manifestBody, 200);
            }),
          ),
        ],
      );
      await c.read(updateBuildInfoProvider.future);

      final info = await c.read(updateCheckServiceProvider).checkForUpdate();

      expect(info!.version, '2.0.0');
      expect(requests.single.url, mirror);
      // Same product token, so a mirrored fleet is not a different client.
      expect(requests.single.headers['User-Agent'], contains('NetCrux/1.0.0'));
    });

    test('a pin withholds the offer but still records server time', () async {
      // The pair that matters: an Enterprise seat pinned below the advertised
      // release sees no banner, and still contributes the observation that
      // keeps beta expiry resistant to a clock rollback.
      final observed = <DateTime>[];
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          observedServerTimeSinkProvider.overrideWithValue(observed.add),
          updatePolicyProvider.overrideWithValue(
            UpdatePolicy.fromNames(channel: 'pinned', pinnedVersion: '1.5.0'),
          ),
          updateHttpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response(_manifestBody, 200)),
          ),
        ],
      );
      await c.read(updateBuildInfoProvider.future);

      expect(await c.read(updateCheckServiceProvider).checkForUpdate(), isNull);
      expect(observed, [DateTime.parse('2026-09-15T12:00:00Z')]);
    });

    test('a managed install outranks every policy key', () async {
      // The ordering `ManagedInstall`'s doc comment insists on: an admin who
      // sets a channel must not thereby re-enable self-update across an
      // SCCM-managed fleet. Noop, not a wrapped live service.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          managedInstallProvider.overrideWithValue(
            const ManagedInstall(isManaged: true, mechanism: 'msi'),
          ),
          updatePolicyProvider.overrideWithValue(
            const UpdatePolicy(channel: UpdateChannelPolicy.stable),
          ),
        ],
      );
      await c.read(updateBuildInfoProvider.future);
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });

    test('a mirror does not resurrect a managed install either', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final c = container(
        extra: [
          updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
          managedInstallProvider.overrideWithValue(
            const ManagedInstall(isManaged: true, mechanism: 'deb'),
          ),
          updatePolicyProvider.overrideWithValue(
            UpdatePolicy(manifestUri: Uri.parse('https://mirror.test/m.json')),
          ),
        ],
      );
      await c.read(updateBuildInfoProvider.future);
      expect(c.read(updateCheckServiceProvider), isA<NoopUpdateCheckService>());
    });
  });

  test('an unwired config makes the service provider throw loudly', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // The unwired-config failure propagates out through the dependent
    // provider, wrapped by Riverpod, still naming the provider to override.
    expect(
      () => c.read(updateCheckServiceProvider),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.toString(),
          'toString',
          contains('cruxUpdateConfigProvider'),
        ),
      ),
    );
  });

  test('the raw manifest literal stays valid JSON', () {
    expect(jsonDecode(_manifestBody), isA<Map<String, Object?>>());
  });
}
