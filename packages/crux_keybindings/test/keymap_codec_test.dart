// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Action implements CruxAction {
  openFile,
  zoomIn,
  quit;

  @override
  String get id => 'test.$name';

  @override
  ActionCategory get category => ActionCategory.tools;
}

void main() {
  _versionGatingTests();
  final codec = KeymapCodec<_Action>(actions: _Action.values);

  test('encode wraps bindings in the versioned envelope by action id', () {
    final json = codec.encode({
      _Action.openFile: const KeyBinding(
        key: LogicalKeyboardKey.keyO,
        modifiers: {KeyModifier.mod},
      ),
    });
    expect(json['schema'], defaultKeymapSchema);
    expect(json['version'], kKeymapVersion);
    expect((json['bindings']! as Map)['test.openFile'], {
      'key': 'o',
      'mods': ['mod'],
    });
  });

  test('custom schema string is honored', () {
    final wc = KeymapCodec<_Action>(
      actions: _Action.values,
      schema: 'wavecrux.keymap',
    );
    expect(wc.encode({})['schema'], 'wavecrux.keymap');
  });

  test('round-trips a rebind', () {
    final diffs = {
      _Action.zoomIn: const KeyBinding(
        key: LogicalKeyboardKey.keyZ,
        modifiers: {KeyModifier.mod, KeyModifier.shift},
      ),
    };
    expect(codec.decode(codec.encode(diffs)), diffs);
  });

  test('preserves an explicit unbind', () {
    final decoded = codec.decode(codec.encode({_Action.quit: null}));
    expect(decoded.containsKey(_Action.quit), isTrue);
    expect(decoded[_Action.quit], isNull);
  });

  test('skips unknown action ids', () {
    final decoded = codec.decode({
      'bindings': {
        'test.openFile': {
          'key': 'o',
          'mods': <String>['mod'],
        },
        'test.removedAction': {
          'key': 'k',
          'mods': <String>['mod'],
        },
      },
    });
    expect(decoded.keys, [_Action.openFile]);
  });

  test('skips malformed bindings', () {
    final decoded = codec.decode({
      'bindings': {
        'test.openFile': {'key': 'not-real'},
        'test.zoomIn': {
          'key': 'z',
          'mods': <String>['mod'],
        },
      },
    });
    expect(decoded.keys, [_Action.zoomIn]);
  });

  test('returns empty for invalid payloads', () {
    expect(codec.decode(null), isEmpty);
    expect(codec.decode('nope'), isEmpty);
    expect(codec.decodeString('{ not json'), isEmpty);
  });

  test('string round-trip preserves diffs incl. unbinds', () {
    final diffs = {
      _Action.openFile: const KeyBinding(
        key: LogicalKeyboardKey.keyO,
        modifiers: {KeyModifier.mod},
      ),
      _Action.quit: null,
    };
    expect(codec.decodeString(codec.encodeToString(diffs)), diffs);
  });
}

// Version gating. `version` was written into every envelope and
// never read, so a keymap from a newer build was parsed under this build's
// assumptions and silently produced the wrong bindings.
void _versionGatingTests() {
  final codec = KeymapCodec<_VersionTestAction>(
    actions: _VersionTestAction.values,
  );

  group('keymap schema version gating', () {
    Map<String, Object?> envelope(Object? version) => <String, Object?>{
      'schema': defaultKeymapSchema,
      'version': ?version,
      'bindings': <String, Object?>{
        _VersionTestAction.alpha.id: const KeyBinding(
          key: LogicalKeyboardKey.keyA,
          modifiers: {KeyModifier.mod},
        ).toJson(),
      },
    };

    test('accepts the current version', () {
      expect(codec.decode(envelope(kKeymapVersion)), hasLength(1));
    });

    test('accepts an older version', () {
      expect(codec.decode(envelope(kKeymapVersion - 1)), hasLength(1));
    });

    test('refuses a newer version loudly', () {
      expect(
        () => codec.decode(envelope(kKeymapVersion + 1)),
        throwsA(isA<KeymapSchemaVersionException>()),
      );
    });

    test('the refusal reports the offending version', () {
      try {
        codec.decode(envelope(99));
        fail('expected a KeymapSchemaVersionException');
      } on KeymapSchemaVersionException catch (e) {
        expect(e.version, 99);
        expect(e.message, contains('99'));
        expect(e.message, contains('$kKeymapVersion'));
      }
    });

    test('is a FormatException, so existing host handlers still catch it', () {
      expect(
        () => codec.decode(envelope(99)),
        throwsA(isA<FormatException>()),
      );
    });

    test('tolerates a missing version key', () {
      expect(codec.decode(envelope(null)), hasLength(1));
    });

    test('tolerates a non-integer version rather than failing', () {
      // Every field below is validated individually, so a hand-edited file
      // with a string version still decodes safely.
      expect(codec.decode(envelope('1')), hasLength(1));
    });

    test('encode writes a version decode will accept', () {
      final round = codec.decode(
        codec.encode({
          _VersionTestAction.alpha: const KeyBinding(
            key: LogicalKeyboardKey.keyA,
            modifiers: {KeyModifier.mod},
          ),
        }),
      );
      expect(round, hasLength(1));
    });

    group('decodeString', () {
      test('still returns empty for malformed JSON', () {
        expect(codec.decodeString('not json'), isEmpty);
      });

      test('propagates the version refusal instead of swallowing it', () {
        // Returning {} here would read as "no customizations" and wipe the
        // user's bindings on the next save — the failure mode the check
        // exists to prevent.
        expect(
          () => codec.decodeString(jsonEncode(envelope(kKeymapVersion + 1))),
          throwsA(isA<KeymapSchemaVersionException>()),
        );
      });

      test('decodes a well-formed current-version document', () {
        expect(
          codec.decodeString(jsonEncode(envelope(kKeymapVersion))),
          hasLength(1),
        );
      });
    });
  });
}

enum _VersionTestAction implements CruxAction {
  alpha;

  @override
  String get id => 'version.test.$name';

  @override
  ActionCategory get category => ActionCategory.tools;
}
