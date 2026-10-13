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
    }
  });

  test('mobile hosts are iOS and android', () {
    for (final platform in const [
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(isCruxDesktopPlatform, isFalse, reason: '$platform');
    }
  });

  test('fuchsia is not desktop', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(isCruxDesktopPlatform, isFalse);
  });
}
