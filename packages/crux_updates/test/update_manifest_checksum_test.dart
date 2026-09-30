// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

const _valid =
    'sha256:'
    '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

UpdateInfo _info(Map<String, String> checksums) =>
    UpdateInfo(version: '1.2.0', checksums: checksums);

void main() {
  group('UpdateInfo.checksumFor', () {
    test('returns a well-formed digest', () {
      final info = _info({'macos_universal': _valid});
      expect(info.checksumFor('macos_universal'), _valid);
    });

    test('normalizes case so a pasted digest compares equal', () {
      final shouty = _valid.toUpperCase().replaceFirst('SHA256', 'sha256');
      expect(_info({'linux_x64': shouty}).checksumFor('linux_x64'), _valid);
    });

    test('tolerates surrounding whitespace', () {
      final info = _info({'windows_x64': '  $_valid  '});
      expect(info.checksumFor('windows_x64'), _valid);
    });

    test('returns null for an unlisted platform', () {
      expect(_info(const {}).checksumFor('linux_x64'), isNull);
    });

    test('rejects malformed digests rather than handing them back', () {
      // The failure this prevents: a user pastes the returned string into
      // `shasum -c` and it silently never matches. Absent beats plausible.
      for (final bad in <String>[
        'deadbeef',
        'sha256:deadbeef',
        'sha512:${'a' * 128}',
        'sha256:${'z' * 64}',
        'sha256:${'a' * 63}',
        '',
      ]) {
        expect(
          _info({'linux_x64': bad}).checksumFor('linux_x64'),
          isNull,
          reason: '"$bad" is not a well-formed sha256 digest',
        );
      }
    });
  });
}
