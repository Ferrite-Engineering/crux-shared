// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateStatus', () {
    test('singleton states compare equal by type', () {
      expect(const UpdateStatusCurrent(), const UpdateStatusCurrent());
      expect(const UpdateStatusChecking(), const UpdateStatusChecking());
      expect(const UpdateStatusError(), const UpdateStatusError());
      expect(
        const UpdateStatusCurrent().hashCode,
        const UpdateStatusCurrent().hashCode,
      );
    });

    test('distinct states are not equal', () {
      expect(const UpdateStatusCurrent(), isNot(const UpdateStatusChecking()));
      expect(const UpdateStatusError(), isNot(const UpdateStatusCurrent()));
      expect(const UpdateStatusChecking(), isNot(const UpdateStatusError()));
    });

    test('available carries and compares its UpdateInfo', () {
      final info = UpdateInfo.fromJson({'version': '1.2.0'})!;
      final other = UpdateInfo.fromJson({'version': '1.2.0'})!;
      final different = UpdateInfo.fromJson({'version': '2.0.0'})!;

      expect(UpdateStatusAvailable(info), UpdateStatusAvailable(other));
      expect(
        UpdateStatusAvailable(info).hashCode,
        UpdateStatusAvailable(other).hashCode,
      );
      expect(
        UpdateStatusAvailable(info),
        isNot(UpdateStatusAvailable(different)),
      );
      expect(UpdateStatusAvailable(info).info.version, '1.2.0');
      expect(UpdateStatusAvailable(info).toString(), contains('1.2.0'));
    });

    test('switch is exhaustive over the four states', () {
      String describe(UpdateStatus s) => switch (s) {
        UpdateStatusCurrent() => 'current',
        UpdateStatusChecking() => 'checking',
        UpdateStatusAvailable() => 'available',
        UpdateStatusError() => 'error',
      };
      expect(describe(const UpdateStatusCurrent()), 'current');
      expect(describe(const UpdateStatusChecking()), 'checking');
      expect(describe(const UpdateStatusError()), 'error');
      expect(
        describe(
          UpdateStatusAvailable(UpdateInfo.fromJson({'version': '1.0.0'})!),
        ),
        'available',
      );
    });

    test('toString is stable for the singleton states', () {
      expect(const UpdateStatusCurrent().toString(), 'UpdateStatusCurrent()');
      expect(const UpdateStatusChecking().toString(), 'UpdateStatusChecking()');
      expect(const UpdateStatusError().toString(), 'UpdateStatusError()');
    });
  });
}
