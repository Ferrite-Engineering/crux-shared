// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal product-style adapter, standing in for the ARB-backed subclass
/// each product writes. Proves the abstract surface is implementable without
/// touching the English default.
class _StubStrings extends CruxUpdateStrings {
  const _StubStrings();

  @override
  String bannerMessage(String version) => '[banner:$version]';

  @override
  String get viewChangesAction => '[changes]';

  @override
  String get updateNowAction => '[now]';

  @override
  String get dismissLabel => '[dismiss]';

  @override
  String get checkInProgress => '[checking]';

  @override
  String checkUpToDate(String version) => '[current:$version]';

  @override
  String get checkFailed => '[failed]';
}

void main() {
  group('CruxUpdateStringsEn', () {
    test('interpolates the version into the banner message', () {
      const strings = CruxUpdateStringsEn(productName: 'NetCrux');
      expect(strings.bannerMessage('1.2.0'), 'NetCrux 1.2.0 is available.');
    });

    test('falls back to a neutral product name', () {
      const strings = CruxUpdateStringsEn();
      expect(strings.bannerMessage('1.0.0'), startsWith('This application'));
    });

    test('names the running version in the up-to-date confirmation', () {
      const strings = CruxUpdateStringsEn();
      expect(strings.checkUpToDate('1.2.3'), contains('1.2.3'));
    });

    test('drops the parenthetical when the version is unknown', () {
      const strings = CruxUpdateStringsEn();
      expect(strings.checkUpToDate(''), isNot(contains('(')));
    });

    test('every action label is non-empty', () {
      const strings = CruxUpdateStringsEn();
      for (final label in [
        strings.viewChangesAction,
        strings.updateNowAction,
        strings.dismissLabel,
        strings.checkInProgress,
        strings.checkFailed,
      ]) {
        expect(label, isNotEmpty);
      }
    });
  });

  group('CruxUpdateStrings', () {
    test('a product adapter can replace every getter', () {
      const CruxUpdateStrings strings = _StubStrings();
      expect(strings.bannerMessage('9.9.9'), '[banner:9.9.9]');
      expect(strings.viewChangesAction, '[changes]');
      expect(strings.updateNowAction, '[now]');
      expect(strings.dismissLabel, '[dismiss]');
      expect(strings.checkInProgress, '[checking]');
      expect(strings.checkUpToDate('1.0.0'), '[current:1.0.0]');
      expect(strings.checkFailed, '[failed]');
    });
  });
}
