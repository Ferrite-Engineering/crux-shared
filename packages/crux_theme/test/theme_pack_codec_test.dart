// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = ThemePackCodec();

  ThemePack makePack({
    Map<String, Map<String, Color>>? tokens,
    Brightness brightness = Brightness.dark,
  }) {
    return ThemePack(
      id: 'pack',
      displayName: 'Pack',
      brightness: brightness,
      tokens:
          tokens ??
          {
            'canvas': {
              'background': const Color(0xFF1A1A1A),
              'cursor.primary': const Color(0xFFFFFF00),
            },
            'chrome': {
              'scaffold': const Color(0x80101010),
            },
          },
    );
  }

  group('encodeColor', () {
    test('opaque colors emit #RRGGBB', () {
      expect(
        ThemePackCodec.encodeColor(const Color(0xFF1A1A1A)),
        '#1A1A1A',
      );
      expect(
        ThemePackCodec.encodeColor(const Color(0xFFFFFFFF)),
        '#FFFFFF',
      );
    });

    test('semi-transparent colors emit #RRGGBBAA', () {
      expect(
        ThemePackCodec.encodeColor(const Color(0x80101010)),
        '#10101080',
      );
      expect(
        ThemePackCodec.encodeColor(const Color(0x00FFFFFF)),
        '#FFFFFF00',
      );
    });

    test('output is uppercase', () {
      expect(
        ThemePackCodec.encodeColor(const Color(0xFFAABBCC)),
        '#AABBCC',
      );
      expect(
        ThemePackCodec.encodeColor(const Color(0xDDFFFFFF)),
        '#FFFFFFDD',
      );
    });
  });

  group('tryParseColor', () {
    test('accepts #RRGGBB', () {
      expect(
        ThemePackCodec.tryParseColor('#1A1A1A'),
        const Color(0xFF1A1A1A),
      );
    });

    test('accepts #RRGGBBAA', () {
      expect(
        ThemePackCodec.tryParseColor('#10101080'),
        const Color(0x80101010),
      );
    });

    test('accepts forms without leading #', () {
      expect(
        ThemePackCodec.tryParseColor('1A1A1A'),
        const Color(0xFF1A1A1A),
      );
      expect(
        ThemePackCodec.tryParseColor('10101080'),
        const Color(0x80101010),
      );
    });

    test('accepts lower-case digits', () {
      expect(
        ThemePackCodec.tryParseColor('#aabbcc'),
        const Color(0xFFAABBCC),
      );
      expect(
        ThemePackCodec.tryParseColor('#aabbccdd'),
        const Color(0xDDAABBCC),
      );
    });

    test('returns null for malformed input', () {
      expect(ThemePackCodec.tryParseColor(''), isNull);
      expect(ThemePackCodec.tryParseColor('#'), isNull);
      expect(ThemePackCodec.tryParseColor('#12345'), isNull);
      expect(ThemePackCodec.tryParseColor('#1234567'), isNull);
      expect(ThemePackCodec.tryParseColor('#123456789'), isNull);
      expect(ThemePackCodec.tryParseColor('#GGGGGG'), isNull);
      expect(ThemePackCodec.tryParseColor('not-a-color'), isNull);
    });
  });

  group('encode/decode round-trip', () {
    test('preserves all fields and token entries', () {
      final pack = makePack();
      final encoded = codec.encode(pack);
      final decoded = codec.decode(encoded);
      expect(decoded.id, pack.id);
      expect(decoded.displayName, pack.displayName);
      expect(decoded.brightness, pack.brightness);
      expect(
        decoded.color('canvas', 'background'),
        const Color(0xFF1A1A1A),
      );
      expect(
        decoded.color('canvas', 'cursor.primary'),
        const Color(0xFFFFFF00),
      );
      expect(decoded.color('chrome', 'scaffold'), const Color(0x80101010));
    });

    test('encoded output is stable across runs', () {
      final pack = makePack();
      final first = codec.encode(pack);
      final second = codec.encode(pack);
      expect(first, second);
    });

    test('decode attaches sourceUri when provided', () {
      final encoded = codec.encode(makePack());
      final uri = Uri.parse('file:///themes/pack.crux-theme.json');
      final decoded = codec.decode(encoded, sourceUri: uri);
      expect(decoded.sourceUri, uri);
    });

    test('decode leaves sourceUri null when not supplied', () {
      final encoded = codec.encode(makePack());
      final decoded = codec.decode(encoded);
      expect(decoded.sourceUri, isNull);
    });

    test('preserves light brightness', () {
      final pack = makePack(brightness: Brightness.light);
      final decoded = codec.decode(codec.encode(pack));
      expect(decoded.brightness, Brightness.light);
    });

    test('empty token table round-trips', () {
      final pack = ThemePack(
        id: 'empty',
        displayName: 'Empty',
        brightness: Brightness.dark,
        tokens: const {},
      );
      final decoded = codec.decode(codec.encode(pack));
      expect(decoded.tokens, isEmpty);
    });
  });

  group('toJson / fromJson', () {
    test('toJson includes schemaVersion 1', () {
      final json = codec.toJson(makePack());
      expect(json['schemaVersion'], 1);
    });

    test('toJson emits "dark" or "light" for brightness', () {
      final dark = codec.toJson(makePack());
      final light = codec.toJson(makePack(brightness: Brightness.light));
      expect(dark['brightness'], 'dark');
      expect(light['brightness'], 'light');
    });

    test('round-trips through toJson/fromJson', () {
      final pack = makePack();
      final json = codec.toJson(pack);
      final decoded = codec.fromJson(json);
      expect(decoded.id, pack.id);
      expect(decoded.tokens['canvas']!['background'], const Color(0xFF1A1A1A));
    });
  });

  group('decode validation errors', () {
    test('rejects non-JSON input', () {
      expect(
        () => codec.decode('not json at all'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects JSON arrays at the top level', () {
      expect(
        () => codec.decode('[]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing schemaVersion', () {
      expect(
        () => codec.decode(
          '{"id":"x","displayName":"x","brightness":"dark","tokens":{}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('schemaVersion'),
          ),
        ),
      );
    });

    test('rejects unknown schemaVersion', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":99,"id":"x","displayName":"x",'
          '"brightness":"dark","tokens":{}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('unsupported schemaVersion'),
          ),
        ),
      );
    });

    test('rejects missing id', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"displayName":"x",'
          '"brightness":"dark","tokens":{}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"id"'),
          ),
        ),
      );
    });

    test('rejects empty id', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"","displayName":"x",'
          '"brightness":"dark","tokens":{}}',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing displayName', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"x",'
          '"brightness":"dark","tokens":{}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('displayName'),
          ),
        ),
      );
    });

    test('rejects invalid brightness', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"x","displayName":"x",'
          '"brightness":"sepia","tokens":{}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('brightness'),
          ),
        ),
      );
    });

    test('rejects missing tokens object', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"x","displayName":"x",'
          '"brightness":"dark"}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('tokens'),
          ),
        ),
      );
    });

    test('rejects non-string color values', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"x","displayName":"x",'
          '"brightness":"dark","tokens":{"canvas":{"background":42}}}',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed hex colors with category context', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"x","displayName":"x","brightness":"dark",'
          '"tokens":{"canvas":{"background":"#NOTAHEX"}}}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('canvas'), contains('background')),
          ),
        ),
      );
    });

    test('rejects non-object category entries', () {
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"id":"x","displayName":"x","brightness":"dark",'
          '"tokens":{"canvas":"not an object"}}',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
