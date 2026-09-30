// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Security regression tests for theme-pack path traversal.
///
/// A `.crux-theme.json` is an explicitly **shareable** artifact — users
/// are expected to download them, receive them in chat, and check them
/// into repos. The `id` field inside that attacker-authored document
/// was interpolated straight into a filename and joined against the
/// user's themes directory, so an id of
/// `../../../../Library/LaunchAgents/com.evil` made `install()` write a
/// file wherever the attacker chose, with contents the attacker also
/// controls (the pack's own JSON). That is arbitrary file write from
/// opening a theme.
///
/// The fix rejects unsafe ids at **decode** time, which is the choke
/// point every read path funnels through, so no future caller can
/// forget the check.
String _packJson(String id) => jsonEncode({
  'schemaVersion': 1,
  'id': id,
  'displayName': 'Evil',
  'brightness': 'dark',
  'tokens': <String, Object?>{
    'chrome': {'scaffold.background': '#000000'},
  },
});

void main() {
  const codec = ThemePackCodec();

  group('pack id traversal payloads are rejected at decode', () {
    const payloads = <String, String>{
      'posix parent traversal': '../../../../Library/LaunchAgents/com.evil',
      'posix single parent': '../evil',
      'windows parent traversal': r'..\..\..\Windows\System32\evil',
      'windows separator only': r'themes\evil',
      'posix separator only': 'themes/evil',
      'absolute posix path': '/etc/cron.d/evil',
      'absolute windows path': r'C:\Windows\evil',
      'windows drive prefix': 'C:evil',
      'alternate data stream': 'good:evil',
      'bare parent': '..',
      'bare current': '.',
      'hidden dotfile': '.bashrc',
      'home expansion': '~/.ssh/authorized_keys',
      'embedded parent segment': 'a/../../../b',
      'normalization bypass style': '....//....//evil',
      'nul truncation': 'good\u0000.png',
      'newline injection': 'good\nevil',
      'leading whitespace': '  evil',
      'trailing whitespace': 'evil  ',
    };

    for (final entry in payloads.entries) {
      test('rejects ${entry.key}', () {
        expect(
          () => codec.decode(_packJson(entry.value)),
          throwsA(isA<FormatException>()),
          reason: 'this payload must never reach the filesystem',
        );
        expect(ThemePackCodec.isValidPackId(entry.value), isFalse);
      });
    }

    test('rejects the same payloads through the header-only decode', () {
      // list() uses decodeHeader, so it needs the identical guard —
      // otherwise a malicious pack that is never "loaded" still gets
      // its id rendered into the UI and passed to activate/uninstall.
      for (final payload in payloads.values) {
        expect(
          () => codec.decodeHeader(_packJson(payload)),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('legitimate pack ids still decode', () {
    const good = <String>[
      'solarized-dark',
      'crux-dark',
      'my_custom_theme',
      'Theme 2024',
      'a.b',
      'ünïcödé-thème',
      '日本語テーマ',
    ];

    for (final id in good) {
      test('accepts "$id"', () {
        expect(ThemePackCodec.isValidPackId(id), isTrue);
        expect(codec.decode(_packJson(id)).id, id);
      });
    }
  });

  group('the service refuses to build a path from an unsafe id', () {
    const service = ThemePackService();

    test('fileFor throws rather than escaping the directory', () {
      expect(
        () => service.fileFor('../evil', Directory('/tmp/themes')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('save throws rather than writing outside the directory', () async {
      final dir = await Directory.systemTemp.createTemp('crux_theme_sec');
      addTearDown(() => dir.delete(recursive: true));
      final pack = ThemePack(
        id: '../escaped',
        displayName: 'Evil',
        brightness: Brightness.dark,
        tokens: const {},
      );
      await expectLater(
        service.save(pack, dir),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('end-to-end: installing a hostile pack writes nothing outside', () {
    test(
      'install of a traversal pack fails and leaves the tree clean',
      () async {
        final root = await Directory.systemTemp.createTemp('crux_theme_e2e');
        addTearDown(() => root.delete(recursive: true));
        final themes = Directory(p.join(root.path, 'app', 'themes'));
        await themes.create(recursive: true);
        final victim = File(p.join(root.path, 'victim.crux-theme.json'));

        final hostile = File(p.join(root.path, 'shared.crux-theme.json'));
        // Escapes `app/themes` back up to `root`.
        await hostile.writeAsString(_packJson('../../victim'));

        const service = ThemePackService();
        await expectLater(
          service.install(hostile, themes),
          throwsA(isA<FormatException>()),
        );

        expect(
          victim.existsSync(),
          isFalse,
          reason: 'install must not have written outside the themes directory',
        );
        expect(themes.listSync(), isEmpty);
      },
    );

    test('list() skips a hostile pack instead of surfacing its id', () async {
      final themes = await Directory.systemTemp.createTemp('crux_theme_list');
      addTearDown(() => themes.delete(recursive: true));
      await File(
        p.join(themes.path, 'hostile.crux-theme.json'),
      ).writeAsString(_packJson('../../../evil'));
      await File(
        p.join(themes.path, 'good.crux-theme.json'),
      ).writeAsString(_packJson('good-theme'));

      final headers = await const ThemePackService().list(themes);
      expect(headers.map((h) => h.id), ['good-theme']);
    });
  });
}
