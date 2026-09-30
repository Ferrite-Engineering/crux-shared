// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:test/test.dart';

void main() {
  group('YosysAvailability', () {
    test(
      'available factory sets isAvailable, path, version, and no reason',
      () {
        const result = YosysAvailability.available(
          executablePath: '/usr/local/bin/yosys',
          versionString: 'Yosys 0.50',
        );
        expect(result.isAvailable, isTrue);
        expect(result.executablePath, '/usr/local/bin/yosys');
        expect(result.versionString, 'Yosys 0.50');
        expect(result.unavailableReason, isNull);
      },
    );

    test('notFound factory defaults to the not_on_path reason', () {
      const result = YosysAvailability.notFound();
      expect(result.isAvailable, isFalse);
      expect(result.executablePath, isNull);
      expect(result.versionString, isNull);
      expect(result.unavailableReason, YosysUnavailableReason.notOnPath);
    });

    test('notFound factory honors a custom reason', () {
      const result = YosysAvailability.notFound(reason: 'custom');
      expect(result.unavailableReason, 'custom');
    });

    test('unusable factory retains the located path and surfaces a reason', () {
      const result = YosysAvailability.unusable(path: '/usr/bin/yosys');
      expect(result.isAvailable, isFalse);
      expect(result.executablePath, '/usr/bin/yosys');
      expect(result.versionString, isNull);
      expect(result.unavailableReason, YosysUnavailableReason.execFailed);
    });

    test('YosysUnavailableReason constants are stable strings', () {
      expect(YosysUnavailableReason.notOnPath, 'not_on_path');
      expect(YosysUnavailableReason.execFailed, 'exec_failed');
      expect(YosysUnavailableReason.bannerUnparsed, 'banner_unparsed');
    });
  });
}
