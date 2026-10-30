// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Windows network-path rule is lexical, so it is tested on every host
// by naming the platform rather than running on it.

import 'package:cxp/src/cxp_network_path.dart';
import 'package:test/test.dart';

void main() {
  group('Windows network and device paths are refused on their spelling', () {
    const reason = 'file_path is a network or device path';

    for (final path in <String>[
      r'\\attacker\share\design.v',
      '//attacker/share/design.v',
      r'\/attacker\share\design.v',
      r'\\attacker',
      r'\\?\C:\work\design.v',
      r'\\?\UNC\attacker\share\design.v',
      r'\\.\pipe\something',
    ]) {
      test('floor tier refuses $path', () {
        expect(cxpNetworkPathRefusal(path, windows: true), reason);
      });

      test('with an unrelated local root, refuses $path', () {
        expect(
          cxpNetworkPathRefusal(path, windows: true, roots: [r'C:\work']),
          reason,
        );
      });
    }

    test('a root on the same share lets the path through to the check', () {
      expect(
        cxpNetworkPathRefusal(
          r'\\FileServer\Designs\cpu\alu.v',
          windows: true,
          roots: [r'C:\work', '//fileserver/designs/cpu'],
        ),
        isNull,
      );
    });

    test('a root on another share of the same server does not', () {
      expect(
        cxpNetworkPathRefusal(
          r'\\fileserver\private\keys.txt',
          windows: true,
          roots: [r'\\fileserver\designs'],
        ),
        reason,
      );
    });

    test('a drive path is not a network path', () {
      expect(
        cxpNetworkPathRefusal(r'C:\work\design.v', windows: true),
        isNull,
      );
    });

    test('off Windows a leading // is an ordinary absolute path', () {
      expect(
        cxpNetworkPathRefusal('//attacker/share/design.v', windows: false),
        isNull,
      );
    });
  });
}
