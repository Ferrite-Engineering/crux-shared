// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('useCustomWindowChrome', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is true on Windows and Linux desktop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(useCustomWindowChrome, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(useCustomWindowChrome, isTrue);
    });

    test('is false on macOS (keeps native title bar + system menu)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(useCustomWindowChrome, isFalse);
    });

    test('is false on mobile platforms', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(useCustomWindowChrome, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(useCustomWindowChrome, isFalse);
    });

    // Note: kIsWeb is a compile-time const false in the VM test target, so the
    // web exclusion can't be flipped at runtime here; it is covered by the
    // `!kIsWeb` guard in the predicate itself.
  });

  group('windowChromeLeftResizeEdge', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is 8 dp on Linux (left drag-to-resize border overlaps content)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(windowChromeLeftResizeEdge, 8.0);
    });

    test('is 0 on Windows (only the top resize edges are enabled)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(windowChromeLeftResizeEdge, 0.0);
    });

    test('is 0 on macOS and mobile (no custom chrome)', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(windowChromeLeftResizeEdge, 0.0, reason: '$platform');
      }
    });
  });
}
