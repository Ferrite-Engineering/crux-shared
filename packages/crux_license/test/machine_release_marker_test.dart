// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The note one product leaves for the others when it releases the machine.
///
/// Every file test resolves its path through the `environment` map into a
/// temp directory; nothing here touches the real shared directory.
void main() {
  const licence = 'lic00000-0000-4000-8000-000000000001';
  const otherLicence = 'lic00000-0000-4000-8000-000000000002';
  const fingerprint = 'fingerprint-000000001';

  group('FileMachineReleaseMarker', () {
    late Directory dir;
    late Map<String, String> env;
    var clock = DateTime.utc(2026, 9, 23, 12);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('crux_release_marker_');
      env = <String, String>{'HOME': dir.path};
      clock = DateTime.utc(2026, 9, 23, 12);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File file() => File(
      p.join(
        dir.path,
        'Library',
        'Application Support',
        'crux',
        'license',
        'released.json',
      ),
    );
    FileMachineReleaseMarker markerOver({Map<String, String>? environment}) =>
        FileMachineReleaseMarker(
          environment: environment ?? env,
          operatingSystem: 'macos',
          now: () => clock,
        );

    test('nothing is released until something is marked', () async {
      expect(
        await markerOver().wasReleased(
          licenseId: licence,
          fingerprint: fingerprint,
        ),
        isFalse,
      );
      expect(file().existsSync(), isFalse, reason: 'a read creates nothing');
    });

    test('mark, was, clear', () async {
      final marker = markerOver();
      await marker.markReleased(licenseId: licence, fingerprint: fingerprint);
      expect(
        await marker.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isTrue,
      );
      await marker.clearReleased(licenseId: licence);
      expect(
        await marker.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isFalse,
      );
    });

    test('matches on the licence and the fingerprint together', () async {
      final marker = markerOver();
      await marker.markReleased(licenseId: licence, fingerprint: fingerprint);
      expect(
        await marker.wasReleased(
          licenseId: otherLicence,
          fingerprint: fingerprint,
        ),
        isFalse,
        reason: "a note for another licence is somebody else's",
      );
      expect(
        await marker.wasReleased(
          licenseId: licence,
          fingerprint: 'fingerprint-000000002',
        ),
        isFalse,
        reason: 'a note for another fingerprint predates this identity',
      );
    });

    test('a second product over the same directory sees the note', () async {
      await markerOver().markReleased(
        licenseId: licence,
        fingerprint: fingerprint,
      );
      expect(
        await markerOver().wasReleased(
          licenseId: licence,
          fingerprint: fingerprint,
        ),
        isTrue,
      );
    });

    test('the document has the documented shape', () async {
      await markerOver().markReleased(
        licenseId: licence,
        fingerprint: fingerprint,
      );
      final doc =
          json.decode(file().readAsStringSync()) as Map<String, Object?>;
      expect(doc['v'], 1);
      expect(doc['released'], <String, Object?>{
        licence: <String, Object?>{
          'fingerprint': fingerprint,
          'at': '2026-09-23T12:00:00.000Z',
        },
      });
    });

    test('notes for several licences coexist', () async {
      final marker = markerOver();
      await marker.markReleased(licenseId: licence, fingerprint: fingerprint);
      await marker.markReleased(
        licenseId: otherLicence,
        fingerprint: fingerprint,
      );
      await marker.clearReleased(licenseId: licence);
      expect(
        await marker.wasReleased(
          licenseId: otherLicence,
          fingerprint: fingerprint,
        ),
        isTrue,
      );
    });

    test(
      'entries older than the retention are dropped on the next write',
      () async {
        final marker = markerOver();
        await marker.markReleased(licenseId: licence, fingerprint: fingerprint);

        clock = clock.add(FileMachineReleaseMarker.retention ~/ 2);
        await marker.markReleased(
          licenseId: otherLicence,
          fingerprint: fingerprint,
        );
        expect(
          await marker.wasReleased(
            licenseId: licence,
            fingerprint: fingerprint,
          ),
          isTrue,
          reason: 'half the retention is not the retention',
        );

        clock = clock
            .add(FileMachineReleaseMarker.retention ~/ 2)
            .add(
              const Duration(days: 1),
            );
        await marker.clearReleased(
          licenseId: 'lic00000-0000-4000-8000-0000000000ff',
        );
        expect(
          await marker.wasReleased(
            licenseId: licence,
            fingerprint: fingerprint,
          ),
          isTrue,
          reason: 'clearing a licence never noted writes nothing, so no prune',
        );
        await marker.clearReleased(licenseId: otherLicence);
        expect(
          await marker.wasReleased(
            licenseId: licence,
            fingerprint: fingerprint,
          ),
          isFalse,
          reason: 'the first note is past the retention at this write',
        );
        final doc =
            json.decode(file().readAsStringSync()) as Map<String, Object?>;
        expect(doc['released'], isEmpty);
      },
    );

    test('an entry whose stamp cannot be read is kept, not pruned', () async {
      file()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          json.encode(<String, Object?>{
            'v': 1,
            'released': <String, Object?>{
              licence: <String, Object?>{
                'fingerprint': fingerprint,
                'at': 'yesterday',
              },
            },
          }),
        );
      final marker = markerOver();
      await marker.markReleased(
        licenseId: otherLicence,
        fingerprint: fingerprint,
      );
      expect(
        await marker.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isTrue,
      );
    });

    test(
      'an unparseable file reads as empty and is replaced on write',
      () async {
        file()
          ..createSync(recursive: true)
          ..writeAsStringSync('not json {');
        final marker = markerOver();
        expect(
          await marker.wasReleased(
            licenseId: licence,
            fingerprint: fingerprint,
          ),
          isFalse,
        );
        await marker.markReleased(licenseId: licence, fingerprint: fingerprint);
        expect(
          await marker.wasReleased(
            licenseId: licence,
            fingerprint: fingerprint,
          ),
          isTrue,
        );
      },
    );

    test(
      'a document of another version, or another shape, reads as empty',
      () async {
        for (final doc in <Object?>[
          <String, Object?>{
            'v': 2,
            'released': <String, Object?>{
              licence: <String, Object?>{'fingerprint': fingerprint},
            },
          },
          <String, Object?>{
            'v': 1,
            'released': <Object?>[licence],
          },
          <String, Object?>{
            'v': 1,
            'released': <String, Object?>{licence: fingerprint},
          },
          <Object?>[licence],
        ]) {
          file()
            ..createSync(recursive: true)
            ..writeAsStringSync(json.encode(doc));
          expect(
            await markerOver().wasReleased(
              licenseId: licence,
              fingerprint: fingerprint,
            ),
            isFalse,
            reason: json.encode(doc),
          );
        }
      },
    );

    test('clearing a licence that was never noted writes nothing', () async {
      await markerOver().clearReleased(licenseId: licence);
      expect(file().existsSync(), isFalse);
    });

    test('a missing home directory fails soft in every method', () async {
      final homeless = markerOver(environment: const <String, String>{});
      await homeless.markReleased(licenseId: licence, fingerprint: fingerprint);
      expect(
        await homeless.wasReleased(
          licenseId: licence,
          fingerprint: fingerprint,
        ),
        isFalse,
      );
      await homeless.clearReleased(licenseId: licence);
    });

    test('an unwritable directory fails soft in every method', () async {
      final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('');
      final blocked = markerOver(
        environment: <String, String>{'HOME': blocker.path},
      );
      await blocked.markReleased(licenseId: licence, fingerprint: fingerprint);
      expect(
        await blocked.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isFalse,
      );
      await blocked.clearReleased(licenseId: licence);
    });

    test('a write leaves one whole file and no scratch debris', () async {
      await markerOver().markReleased(
        licenseId: licence,
        fingerprint: fingerprint,
      );
      expect(
        file().parent.listSync().map((e) => p.basename(e.path)),
        <String>['released.json'],
      );
    });
  });

  group('NoMachineReleaseMarker', () {
    test('notes nothing and was never released', () async {
      const marker = NoMachineReleaseMarker();
      await marker.markReleased(licenseId: licence, fingerprint: fingerprint);
      expect(
        await marker.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isFalse,
      );
      await marker.clearReleased(licenseId: licence);
    });
  });

  group('InMemoryMachineReleaseMarker', () {
    test('mark, was, clear, over a map two markers can share', () async {
      final shared = <String, String>{};
      final a = InMemoryMachineReleaseMarker(shared);
      final b = InMemoryMachineReleaseMarker(shared);
      await a.markReleased(licenseId: licence, fingerprint: fingerprint);
      expect(
        await b.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isTrue,
      );
      expect(
        await b.wasReleased(licenseId: licence, fingerprint: 'fingerprint-2'),
        isFalse,
      );
      await b.clearReleased(licenseId: licence);
      expect(
        await a.wasReleased(licenseId: licence, fingerprint: fingerprint),
        isFalse,
      );
      expect(shared, isEmpty);
    });
  });
}
