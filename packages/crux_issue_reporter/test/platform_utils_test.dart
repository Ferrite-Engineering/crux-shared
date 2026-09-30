// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('desktop hosts are linux, macOS and windows', () {
    for (final platform in const [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(isCruxDesktopPlatform, isTrue, reason: '$platform');
      expect(isCruxMobilePlatform, isFalse, reason: '$platform');
    }
  });

  test('mobile hosts are iOS and android', () {
    for (final platform in const [
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(isCruxDesktopPlatform, isFalse, reason: '$platform');
      expect(isCruxMobilePlatform, isTrue, reason: '$platform');
    }
  });

  test('fuchsia is neither', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(isCruxDesktopPlatform, isFalse);
    expect(isCruxMobilePlatform, isFalse);
  });
}
