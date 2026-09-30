// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CruxUpdateConfig config({String? appStore, String? playStore}) =>
      CruxUpdateConfig(
        productName: 'NetCrux',
        manifestUri: 'https://updates.netcrux.app/manifest.json',
        downloadPageUri: 'https://netcrux.app/download',
        appStoreUri: appStore,
        playStoreUri: playStore,
      );

  group('construction', () {
    test('parses the string URIs and applies the documented defaults', () {
      final c = config();
      expect(c.manifestUri.host, 'updates.netcrux.app');
      expect(c.downloadPageUri.path, '/download');
      expect(c.appStoreUri, isNull);
      expect(c.playStoreUri, isNull);
      expect(c.checkOnMobile, isFalse);
      expect(c.checkTimeout, kUpdateCheckTimeout);
      expect(c.checkInterval, kUpdateCheckInterval);
    });

    test('fromUris accepts already-parsed endpoints', () {
      final c = CruxUpdateConfig.fromUris(
        productName: 'SimCrux',
        manifestUri: _manifest,
        downloadPageUri: _download,
      );
      expect(c.productName, 'SimCrux');
      expect(c.manifestUri, _manifest);
    });

    test('a malformed URI throws at construction, not at fetch time', () {
      expect(
        () => CruxUpdateConfig(
          productName: 'X',
          manifestUri: 'http://[oops',
          downloadPageUri: 'https://example.test',
        ),
        throwsFormatException,
      );
    });
  });

  group('updateTargetFor', () {
    test('desktop targets the download page', () {
      final c = config();
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(c.updateTargetFor(platform), c.downloadPageUri);
      }
    });

    test('web targets the download page even on a mobile platform', () {
      final c = config(appStore: 'https://apps.apple.test/netcrux');
      expect(
        c.updateTargetFor(TargetPlatform.iOS, isWeb: true),
        c.downloadPageUri,
      );
    });

    test('mobile targets the configured stores', () {
      final c = config(
        appStore: 'https://apps.apple.test/netcrux',
        playStore: 'https://play.google.test/netcrux',
      );
      expect(c.updateTargetFor(TargetPlatform.iOS), c.appStoreUri);
      expect(c.updateTargetFor(TargetPlatform.android), c.playStoreUri);
    });

    test('mobile falls back to the download page when no store is set', () {
      final c = config();
      expect(c.updateTargetFor(TargetPlatform.iOS), c.downloadPageUri);
      expect(c.updateTargetFor(TargetPlatform.android), c.downloadPageUri);
    });
  });

  group('value semantics', () {
    test('equal configurations compare equal', () {
      expect(config(), config());
      expect(config().hashCode, config().hashCode);
    });

    test('copyWith replaces only the named fields', () {
      final base = config();
      final copy = base.copyWith(
        checkOnMobile: true,
        checkInterval: const Duration(hours: 6),
      );
      expect(copy.checkOnMobile, isTrue);
      expect(copy.checkInterval, const Duration(hours: 6));
      expect(copy.manifestUri, base.manifestUri);
      expect(copy, isNot(base));
      expect(base.copyWith(), base);
    });

    test('toString names the product and endpoints', () {
      expect(config().toString(), contains('NetCrux'));
      expect(config().toString(), contains('updates.netcrux.app'));
    });
  });
}

final Uri _manifest = Uri.parse('https://updates.simcrux.app/manifest.json');
final Uri _download = Uri.parse('https://simcrux.app/download');
