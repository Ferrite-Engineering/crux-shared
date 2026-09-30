// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The suite manifest shape, verbatim.
  Map<String, Object?> latestJson({
    String version = '1.2.0',
    bool mandatory = false,
    String? minSupported = '1.0.0',
    String? openCore = '1.1.0',
    String? serverTime = '2026-09-15T12:00:00Z',
  }) => {
    'version': version,
    'channel': 'stable',
    'release_date': '2026-09-15',
    'changelog_url': 'https://example.test/releases/$version',
    'mandatory': mandatory,
    'min_supported_version': ?minSupported,
    'open_core_version': ?openCore,
    'downloads': {
      'linux_x64': 'https://updates.example.test/$version/app-linux.tar.gz',
      'macos_universal': 'https://updates.example.test/$version/App.dmg',
      'windows_x64': 'https://updates.example.test/$version/App-Setup.exe',
    },
    'checksums': {
      'linux_x64': 'sha256:aaa',
      'macos_universal': 'sha256:bbb',
      'windows_x64': 'sha256:ccc',
    },
    'server_time': ?serverTime,
  };

  group('UpdateInfo.fromJson', () {
    test('parses a full release object incl. server_time', () {
      final info = UpdateInfo.fromJson(latestJson())!;
      expect(info.version, '1.2.0');
      expect(info.channel, 'stable');
      expect(info.releaseDate, DateTime.parse('2026-09-15'));
      expect(info.changelogUrl, 'https://example.test/releases/1.2.0');
      expect(info.mandatory, isFalse);
      expect(info.minSupportedVersion, '1.0.0');
      expect(info.openCoreVersion, '1.1.0');
      expect(info.downloads['macos_universal'], contains('App.dmg'));
      expect(info.downloadUrlFor('linux_x64'), contains('app-linux'));
      expect(info.downloadUrlFor('nope_x64'), isNull);
      expect(info.checksums['windows_x64'], 'sha256:ccc');
      expect(info.serverTime, DateTime.parse('2026-09-15T12:00:00Z'));
    });

    test('applies benign defaults for absent optional fields', () {
      final info = UpdateInfo.fromJson({'version': '3.0.0'})!;
      expect(info.channel, 'stable');
      expect(info.mandatory, isFalse);
      expect(info.releaseDate, isNull);
      expect(info.changelogUrl, isNull);
      expect(info.minSupportedVersion, isNull);
      expect(info.openCoreVersion, isNull);
      expect(info.downloads, isEmpty);
      expect(info.checksums, isEmpty);
      expect(info.serverTime, isNull);
    });

    test('fails soft on missing or empty version', () {
      expect(UpdateInfo.fromJson({'channel': 'stable'}), isNull);
      expect(UpdateInfo.fromJson({'version': ''}), isNull);
      expect(UpdateInfo.fromJson({'version': '   '}), isNull);
      expect(UpdateInfo.fromJson({'version': 42}), isNull);
    });

    test('fails soft on non-object input', () {
      expect(UpdateInfo.fromJson(null), isNull);
      expect(UpdateInfo.fromJson('nope'), isNull);
      expect(UpdateInfo.fromJson(<Object?>[]), isNull);
    });

    test('drops type-mismatched optional fields without throwing', () {
      final info = UpdateInfo.fromJson({
        'version': '1.0.0',
        'mandatory': 'yes', // not a bool -> false
        'downloads': 'oops', // not a map -> empty
        'release_date': 12345, // not a string -> null
        'changelog_url': 7, // not a string -> null
        'min_supported_version': false, // not a string -> null
        'open_core_version': 110, // not a string -> null
        'server_time': 'not-a-date', // unparseable -> null
        'checksums': {'linux_x64': 3}, // non-string value dropped
      })!;
      expect(info.mandatory, isFalse);
      expect(info.downloads, isEmpty);
      expect(info.releaseDate, isNull);
      expect(info.changelogUrl, isNull);
      expect(info.minSupportedVersion, isNull);
      expect(info.openCoreVersion, isNull);
      expect(info.serverTime, isNull);
      expect(info.checksums, isEmpty);
    });
  });

  group('UpdateManifest.tryParse', () {
    test('parses the wrapped latest object', () {
      final text = jsonEncode({'latest': latestJson()});
      final manifest = UpdateManifest.tryParse(text)!;
      expect(manifest.latest.version, '1.2.0');
      expect(manifest.toString(), contains('1.2.0'));
    });

    test('fails soft on malformed JSON', () {
      expect(UpdateManifest.tryParse('{not json'), isNull);
      expect(UpdateManifest.tryParse(''), isNull);
    });

    test('fails soft when latest is missing or invalid', () {
      expect(UpdateManifest.tryParse(jsonEncode({'foo': 1})), isNull);
      expect(
        UpdateManifest.tryParse(
          jsonEncode({
            'latest': {'channel': 'stable'},
          }),
        ),
        isNull,
      );
    });

    test('fails soft on a non-object JSON root', () {
      expect(UpdateManifest.tryParse('[1, 2, 3]'), isNull);
      expect(UpdateManifest.fromJson('nope'), isNull);
    });

    test('value equality', () {
      final a = UpdateManifest.tryParse(jsonEncode({'latest': latestJson()}))!;
      final b = UpdateManifest.tryParse(jsonEncode({'latest': latestJson()}))!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('UpdateInfo.isNewerThan', () {
    test('true only when the release is strictly newer', () {
      final info = UpdateInfo.fromJson(latestJson())!; // 1.2.0
      expect(info.isNewerThan('1.1.9'), isTrue);
      expect(info.isNewerThan('1.2.0'), isFalse); // equal
      expect(info.isNewerThan('1.3.0'), isFalse); // older than current
    });

    test('a pre-release current build is older than the release', () {
      final info = UpdateInfo.fromJson(latestJson())!; // 1.2.0
      expect(info.isNewerThan('1.2.0-rc.1'), isTrue);
    });

    test('a pre-release manifest entry is not newer than its release', () {
      final info = UpdateInfo.fromJson(latestJson(version: '1.2.0-rc.1'))!;
      expect(info.isNewerThan('1.2.0'), isFalse);
    });

    test('false when either version is malformed', () {
      final info = UpdateInfo.fromJson(latestJson(version: 'not-a-version'))!;
      expect(info.isNewerThan('1.0.0'), isFalse);
      final ok = UpdateInfo.fromJson(latestJson())!;
      expect(ok.isNewerThan('garbage'), isFalse);
    });
  });

  group('UpdateInfo.meetsMinSupported', () {
    test('true when current is at or above the floor', () {
      final info = UpdateInfo.fromJson(latestJson())!; // floor 1.0.0
      expect(info.meetsMinSupported('1.0.0'), isTrue);
      expect(info.meetsMinSupported('1.1.0'), isTrue);
    });

    test('false when current is below the floor', () {
      final info = UpdateInfo.fromJson(latestJson())!; // floor 1.0.0
      expect(info.meetsMinSupported('0.9.0'), isFalse);
    });

    test('true when no floor declared, empty, or unparseable', () {
      final none = UpdateInfo.fromJson(latestJson(minSupported: null))!;
      expect(none.meetsMinSupported('0.0.1'), isTrue);
      final blank = UpdateInfo.fromJson(latestJson(minSupported: '  '))!;
      expect(blank.meetsMinSupported('0.0.1'), isTrue);
      final bad = UpdateInfo.fromJson(latestJson(minSupported: 'x.y.z'))!;
      expect(bad.meetsMinSupported('0.0.1'), isTrue);
    });

    test('false when current is unparseable against a real floor', () {
      final info = UpdateInfo.fromJson(latestJson())!; // floor 1.0.0
      expect(info.meetsMinSupported('garbage'), isFalse);
    });
  });

  group('UpdateInfo.changesOpenCoreSince', () {
    test('true only when current predates the open-core release', () {
      final info = UpdateInfo.fromJson(latestJson())!; // open core 1.1.0
      expect(info.changesOpenCoreSince('1.0.9'), isTrue);
      expect(info.changesOpenCoreSince('1.1.0'), isFalse); // equal
      expect(info.changesOpenCoreSince('1.1.5'), isFalse);
    });

    test('true when nothing is declared, blank, or unparseable', () {
      final none = UpdateInfo.fromJson(latestJson(openCore: null))!;
      expect(none.changesOpenCoreSince('1.1.9'), isTrue);
      final blank = UpdateInfo.fromJson(latestJson(openCore: ' '))!;
      expect(blank.changesOpenCoreSince('1.1.9'), isTrue);
      final bad = UpdateInfo.fromJson(latestJson(openCore: 'x.y.z'))!;
      expect(bad.changesOpenCoreSince('1.1.9'), isTrue);
    });

    test('true when current is unparseable', () {
      final info = UpdateInfo.fromJson(latestJson())!;
      expect(info.changesOpenCoreSince('garbage'), isTrue);
    });
  });

  group('equality / copyWith', () {
    test('value equality includes maps', () {
      final a = UpdateInfo.fromJson(latestJson())!;
      final b = UpdateInfo.fromJson(latestJson())!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when a field changes', () {
      final a = UpdateInfo.fromJson(latestJson())!;
      expect(a.copyWith(mandatory: true), isNot(a));
      expect(a.copyWith(openCoreVersion: '1.2.0'), isNot(a));
      expect(a.copyWith(openCoreVersion: '1.2.0').openCoreVersion, '1.2.0');
      expect(a.copyWith(version: '9.9.9').version, '9.9.9');
      expect(a.copyWith(), a);
    });

    test('differs when a download map entry changes', () {
      final a = UpdateInfo.fromJson(latestJson())!;
      expect(
        a.copyWith(downloads: {...a.downloads, 'linux_x64': 'other'}),
        isNot(a),
      );
      expect(a.copyWith(downloads: const {}), isNot(a));
    });

    test('toString names the version and mandatory flag', () {
      final a = UpdateInfo.fromJson(latestJson())!;
      expect(a.toString(), contains('1.2.0'));
      expect(a.toString(), contains('mandatory: false'));
    });
  });
}
