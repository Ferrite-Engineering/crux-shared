// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('telemetryOsSlugFor', () {
    test('maps every desktop and mobile host to a Worker-accepted slug', () {
      const expected = <TargetPlatform, String>{
        TargetPlatform.macOS: 'macos',
        TargetPlatform.windows: 'windows',
        TargetPlatform.linux: 'linux',
        TargetPlatform.iOS: 'ios',
        TargetPlatform.android: 'android',
        TargetPlatform.fuchsia: 'linux',
      };
      for (final entry in expected.entries) {
        expect(
          telemetryOsSlugFor(isWeb: false, platform: entry.key),
          entry.value,
        );
      }
    });

    test('kIsWeb wins over the emulated host platform', () {
      // A browser on a Mac reports TargetPlatform.macOS. The question `os`
      // answers is "which build is this", so web must win.
      expect(
        telemetryOsSlugFor(isWeb: true, platform: TargetPlatform.macOS),
        'web',
      );
      expect(
        telemetryOsSlugFor(isWeb: true, platform: TargetPlatform.android),
        'web',
      );
    });

    test('every slug is one the ingestion Worker accepts', () {
      for (final platform in TargetPlatform.values) {
        expect(
          kTelemetryOperatingSystems,
          contains(telemetryOsSlugFor(isWeb: false, platform: platform)),
        );
      }
      expect(
        kTelemetryOperatingSystems,
        contains(telemetryOsSlugFor(isWeb: true, platform: TargetPlatform.iOS)),
      );
    });

    test('the live derivation lands inside the closed set', () {
      expect(kTelemetryOperatingSystems, contains(telemetryOsSlug()));
    });
  });

  group('the closed form-factor vocabulary', () {
    test('is the five buckets the Worker accepts', () {
      // The *derivation* is per-product — each app maps the layout idiom it
      // already drew — but the vocabulary it must land in is fixed here, and
      // each product's own derivation test asserts against this list.
      expect(kTelemetryFormFactors, <String>[
        'desktop',
        'phone',
        'tablet',
        'web',
        'vscode',
      ]);
    });

    test('the seam default is a member of it', () {
      expect(kTelemetryFormFactors, contains('desktop'));
    });

    test('carries the editor-host bucket', () {
      // A webview reports `kIsWeb == true`, so without its own bucket every
      // editor-hosted build would be indistinguishable from browser traffic —
      // losing extension adoption and corrupting the web-vs-desktop split.
      expect(kTelemetryFormFactors, contains('vscode'));
    });
  });
}
