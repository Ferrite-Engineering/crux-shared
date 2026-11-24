// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry_core/crux_telemetry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fake_store.dart';

const String _idA = '00000000-0000-4000-8000-00000000000a';
const String _idB = '00000000-0000-4000-8000-00000000000b';

void main() {
  group('desktopTelemetryStores: where each desktop app writes', () {
    // Expected locations are the products' own runner settings
    // (PRODUCT_BUNDLE_IDENTIFIER in macos/Runner/Configs/AppInfo.xcconfig,
    // APPLICATION_ID and BINARY_NAME in linux/CMakeLists.txt, CompanyName and
    // ProductName in windows/runner/Runner.rc, for each open core and each Pro
    // overlay) put through `path_provider`'s and `shared_preferences`' rules.
    test('macOS: the two preference domains, this edition first', () {
      final core = desktopTelemetryStores(
        CruxTelemetryProduct.wavecrux,
        pro: false,
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/u'},
      );
      expect(core.map((s) => s.toString()), <String>[
        'defaults com.ferriteengineering.wavecrux',
        'defaults com.ferriteengineering.wavecruxPro',
      ]);
      final pro = desktopTelemetryStores(
        CruxTelemetryProduct.simcrux,
        pro: true,
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/u'},
      );
      expect(pro.map((s) => s.toString()), <String>[
        'defaults com.ferriteengineering.simcruxPro',
        'defaults com.ferriteengineering.simcrux',
      ]);
    });

    test('Linux: the APPLICATION_ID directory, then the executable one', () {
      final stores = desktopTelemetryStores(
        CruxTelemetryProduct.netcrux,
        pro: true,
        operatingSystem: 'linux',
        environment: const {'HOME': '/home/u'},
      );
      expect(stores, hasLength(2));
      expect(
        stores[0].toString(),
        'file /home/u/.local/share/com.ferriteengineering.netcrux_pro | '
        '/home/u/.local/share/netcrux_pro shared_preferences.json',
      );
      expect(
        stores[1].toString(),
        'file /home/u/.local/share/com.ferriteengineering.netcrux | '
        '/home/u/.local/share/netcrux shared_preferences.json',
      );
      final xdg = desktopTelemetryStores(
        CruxTelemetryProduct.wavecrux,
        pro: false,
        operatingSystem: 'linux',
        environment: const {'HOME': '/home/u', 'XDG_DATA_HOME': '/data'},
      );
      expect(
        xdg.first.toString(),
        'file /data/com.ferriteengineering.wavecrux | /data/wavecrux '
        'shared_preferences.json',
      );
    });

    test('Windows: roaming application data, company, product', () {
      final stores = desktopTelemetryStores(
        CruxTelemetryProduct.simcrux,
        pro: false,
        operatingSystem: 'windows',
        environment: const {'APPDATA': r'C:\Users\u\AppData\Roaming'},
      );
      expect(stores, hasLength(2));
      expect(
        stores[0].toString(),
        r'file C:\Users\u\AppData\Roaming\com.ferriteengineering\SimCrux '
        'shared_preferences.json',
      );
      expect(
        stores[1].toString(),
        r'file C:\Users\u\AppData\Roaming\com.ferriteengineering\SimCrux Pro '
        'shared_preferences.json',
      );
    });

    test('LintCrux: its own file, one for both editions, on every OS', () {
      // `lintcruxTelemetryStorePath` in LintCrux's telemetry storage adapter.
      String only(String os, Map<String, String> env) => desktopTelemetryStores(
        CruxTelemetryProduct.lintcrux,
        pro: true,
        operatingSystem: os,
        environment: env,
      ).single.toString();
      expect(
        only('macos', const {'HOME': '/Users/u'}),
        'file /Users/u/Library/Application Support/crux/telemetry '
        'lintcrux.json',
      );
      expect(
        only('linux', const {'HOME': '/home/u'}),
        'file /home/u/.local/share/crux/telemetry lintcrux.json',
      );
      expect(
        only('windows', const {'APPDATA': r'C:\R'}),
        r'file C:\R\crux\telemetry lintcrux.json',
      );
    });

    test('no home or application-data variable: no store, so no consent', () {
      for (final os in <String>['macos', 'linux', 'windows']) {
        expect(
          desktopTelemetryStores(
            CruxTelemetryProduct.lintcrux,
            pro: false,
            operatingSystem: os,
            environment: const {},
          ),
          isEmpty,
          reason: os,
        );
      }
      for (final os in <String>['linux', 'windows']) {
        expect(
          desktopTelemetryStores(
            CruxTelemetryProduct.wavecrux,
            pro: false,
            operatingSystem: os,
            environment: const {'HOME': ''},
          ),
          isEmpty,
          reason: os,
        );
      }
    });
  });

  group('MacOsDefaultsTelemetryStore', () {
    test('reads the prefixed key through defaults', () {
      final calls = <List<String>>[];
      final store = MacOsDefaultsTelemetryStore(
        'com.ferriteengineering.wavecrux',
        run: (executable, arguments) {
          calls.add(<String>[executable, ...arguments]);
          return ProcessResult(0, 0, 'enabled\n', '');
        },
      );
      expect(store.read(kTelemetryConsentKey), 'enabled');
      expect(calls.single, <String>[
        '/usr/bin/defaults',
        'read',
        'com.ferriteengineering.wavecrux',
        'flutter.telemetry.consent',
      ]);
    });

    test('a missing key, an odd answer or a failure to run is null', () {
      String? read(ProcessResult Function() answer) =>
          MacOsDefaultsTelemetryStore(
            'd',
            run: (_, _) => answer(),
          ).read(kTelemetryConsentKey);
      expect(read(() => ProcessResult(0, 1, '', 'does not exist')), isNull);
      expect(read(() => ProcessResult(0, 0, <int>[1], '')), isNull);
      expect(read(() => throw const ProcessException('defaults', [])), isNull);
    });

    test(
      'reads a real property list with the real defaults',
      () {
        final dir = Directory.systemTemp.createTempSync('crux_tc_plist');
        addTearDown(() => dir.deleteSync(recursive: true));
        final plist = File(p.join(dir.path, 'prefs.plist'))
          ..writeAsStringSync(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict>\n'
            '<key>flutter.telemetry.consent</key><string>enabled</string>\n'
            '<key>flutter.telemetry.installationId</key>\n'
            '<string>$_idA</string>\n'
            '</dict></plist>\n',
          );
        // `defaults` takes a property list's path where a domain goes, so the
        // test reads a file it wrote rather than any real application's
        // preferences.
        final store = MacOsDefaultsTelemetryStore(plist.path);
        expect(store.read(kTelemetryConsentKey), 'enabled');
        expect(store.read(kTelemetryInstallationIdKey), _idA);
        expect(store.read('telemetry.absent'), isNull);
      },
      testOn: 'mac-os',
    );
  });

  group('JsonFileTelemetryStore', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('crux_tc_json'));
    tearDown(() => root.deleteSync(recursive: true));

    String dir(String name) => p.join(root.path, name);
    void write(String directory, Object? document) {
      Directory(directory).createSync(recursive: true);
      File(
        p.join(directory, 'shared_preferences.json'),
      ).writeAsStringSync(jsonEncode(document));
    }

    test('reads the prefixed key from the first directory that exists', () {
      write(dir('legacy'), {'flutter.telemetry.consent': 'disabled'});
      final store = JsonFileTelemetryStore(
        <String>[dir('appid'), dir('legacy')],
        'shared_preferences.json',
        keyPrefix: kFlutterPreferencesPrefix,
      );
      expect(store.read(kTelemetryConsentKey), 'disabled');
      // Once the application-id directory exists it is the one the app
      // writes, even before the file is in it.
      Directory(dir('appid')).createSync();
      expect(store.read(kTelemetryConsentKey), isNull);
      write(dir('appid'), {'flutter.telemetry.consent': 'enabled'});
      expect(store.read(kTelemetryConsentKey), 'enabled');
    });

    test('an unprefixed key, a non-string, bad JSON or no file is null', () {
      write(dir('a'), {
        'telemetry.consent': 'enabled',
        'flutter.telemetry.installationId': 7,
      });
      final store = JsonFileTelemetryStore(
        <String>[dir('a')],
        'shared_preferences.json',
        keyPrefix: kFlutterPreferencesPrefix,
      );
      expect(store.read(kTelemetryConsentKey), isNull);
      expect(store.read(kTelemetryInstallationIdKey), isNull);
      File(
        p.join(dir('a'), 'shared_preferences.json'),
      ).writeAsStringSync('{not json');
      expect(store.read(kTelemetryConsentKey), isNull);
      write(dir('b'), <Object?>['enabled']);
      expect(
        JsonFileTelemetryStore(<String>[
          dir('b'),
        ], 'shared_preferences.json').read(kTelemetryConsentKey),
        isNull,
      );
      expect(
        JsonFileTelemetryStore(<String>[
          dir('none'),
        ], 'x.json').read(kTelemetryConsentKey),
        isNull,
      );
    });
  });

  group('DesktopTelemetryConsent', () {
    DesktopTelemetryAnswer read(List<FakeStore> stores) =>
        DesktopTelemetryConsent(stores).read();

    test('absent: nothing recorded anywhere is not consent', () {
      final answer = read([FakeStore(), FakeStore()]);
      expect(answer.consent, TelemetryConsentState.unset);
      expect(answer.sendable, isFalse);
      expect(read(const []).sendable, isFalse);
    });

    test('present: enabled with an id is sendable under that id', () {
      final own = FakeStore.answered('enabled', id: _idA);
      final answer = read([own, FakeStore()]);
      expect(answer.sendable, isTrue);
      expect(answer.installationId, _idA);
      expect(answer.store, same(own));
    });

    test('enabled without a well-formed id is not sendable', () {
      expect(read([FakeStore.answered('enabled')]).sendable, isFalse);
      expect(
        read([FakeStore.answered('enabled', id: 'NOT-A-UUID')]).sendable,
        isFalse,
      );
    });

    test('disabled, unset and unknown values are not consent', () {
      for (final value in <String>['disabled', 'unset', 'Enabled', 'yes']) {
        expect(read([FakeStore.answered(value, id: _idA)]).sendable, isFalse);
      }
    });

    test('revoked: a later read sees the new answer', () {
      final store = FakeStore.answered('enabled', id: _idA);
      final consent = DesktopTelemetryConsent([store]);
      expect(consent.read().sendable, isTrue);
      store.values[kTelemetryConsentKey] = 'disabled';
      expect(consent.read().sendable, isFalse);
    });

    test("the other edition's answer counts only where this one has none", () {
      final otherEnabled = FakeStore.answered('enabled', id: _idB);
      expect(read([FakeStore(), otherEnabled]).installationId, _idB);
      expect(
        read([FakeStore.answered('unset'), otherEnabled]).installationId,
        _idB,
      );
      expect(
        read([FakeStore.answered('disabled'), otherEnabled]).sendable,
        isFalse,
      );
      expect(
        read([
          FakeStore.answered('enabled', id: _idA),
          FakeStore.answered('disabled'),
        ]).installationId,
        _idA,
      );
    });
  });
}
