// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_license/crux_license_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The licence service's file-backed pieces in a browser, where `dart:io`'s
/// `Platform` throws `UnsupportedError` for every property.
///
/// Each Pro overlay builds all of these while constructing its licence
/// service, which the bootstrap reads before the first frame. A constructor
/// that asks the platform for anything turns a web edition's startup into a
/// provider error, and the VM suite cannot see it: there `Platform` answers.
///
/// Runs only under `flutter test --platform chrome test/web`, which CI invokes
/// as its own step.
void main() {
  test('the shared fingerprint source constructs without the platform', () {
    expect(SharedInstallFingerprint.new, returnsNormally);
  });

  test('the other file-backed licence pieces construct the same way', () {
    expect(FileMachineReleaseMarker.new, returnsNormally);
    expect(FileLicenseClockMark.new, returnsNormally);
    expect(() => LicenseFallbackFile.forProduct('wavecrux'), returnsNormally);
  });

  test('reading finds no fingerprint rather than throwing', () async {
    // No filesystem and no platform: the file answers "none", and nothing can
    // be minted, so the caller falls back to a fingerprint of its own.
    expect(await SharedInstallFingerprint().readOrCreate(), isNull);
  });

  test('a legacy source that throws is the failure the caller sees', () async {
    // The Linux allowance asks the platform only now, and a browser is not
    // Linux, so the original error propagates instead of an
    // `UnsupportedError` from the platform lookup replacing it.
    final failure = StateError('credential store locked');
    await expectLater(
      SharedInstallFingerprint().readOrCreate(
        legacy: [() async => throw failure],
      ),
      throwsA(same(failure)),
    );
  });
}
