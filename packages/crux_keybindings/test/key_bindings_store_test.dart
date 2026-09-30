// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Action implements CruxAction {
  zoomIn,
  quit;

  @override
  String get id => 'test.$name';

  @override
  ActionCategory get category => ActionCategory.tools;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final codec = KeymapCodec<_Action>(actions: _Action.values);

  Future<SharedPreferences> emptyPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('load returns empty when nothing persisted', () async {
    final store = KeyBindingsStore<_Action>(
      codec: codec,
      prefsOverride: await emptyPrefs(),
    );
    expect(await store.load(), isEmpty);
  });

  test('save then load round-trips diffs incl. explicit unbind', () async {
    final store = KeyBindingsStore<_Action>(
      codec: codec,
      prefsOverride: await emptyPrefs(),
    );
    final diffs = {
      _Action.zoomIn: const KeyBinding(
        key: LogicalKeyboardKey.keyZ,
        modifiers: {KeyModifier.mod},
      ),
      _Action.quit: null,
    };

    await store.save(diffs);
    final loaded = await store.load();

    expect(loaded, diffs);
    expect(loaded.containsKey(_Action.quit), isTrue);
    expect(loaded[_Action.quit], isNull);
  });

  test('saving an empty map clears the stored value', () async {
    final store = KeyBindingsStore<_Action>(
      codec: codec,
      prefsOverride: await emptyPrefs(),
    );
    await store.save({
      _Action.zoomIn: const KeyBinding(key: LogicalKeyboardKey.keyZ),
    });
    expect(await store.load(), isNotEmpty);

    await store.save({});
    expect(await store.load(), isEmpty);
  });

  test('corrupt persisted JSON falls back to empty (no throw)', () async {
    SharedPreferences.setMockInitialValues({
      'settings.shortcutBindings': '{ this is not json',
    });
    final store = KeyBindingsStore<_Action>(
      codec: codec,
      prefsOverride: await SharedPreferences.getInstance(),
    );
    expect(await store.load(), isEmpty);
  });

  test(
    'load propagates KeymapSchemaVersionException on a downgrade',
    () async {
      // Regression: a keymap written by a newer build (schema version above
      // kKeymapVersion) must be refused loudly, not swallowed to an empty map.
      // Swallowing reads to the host as "no customizations"; the next save
      // would then persist an empty diff over the user's real bindings —
      // wiping them. The store must let the refusal propagate so the host can
      // surface it and skip the destructive save.
      SharedPreferences.setMockInitialValues({
        'settings.shortcutBindings':
            '{"version":${kKeymapVersion + 1},"bindings":{}}',
      });
      final store = KeyBindingsStore<_Action>(
        codec: codec,
        prefsOverride: await SharedPreferences.getInstance(),
      );
      await expectLater(
        store.load(),
        throwsA(
          isA<KeymapSchemaVersionException>().having(
            (e) => e.version,
            'version',
            kKeymapVersion + 1,
          ),
        ),
      );
    },
  );

  test('a custom preferenceKey is honored', () async {
    final prefs = await emptyPrefs();
    final store = KeyBindingsStore<_Action>(
      codec: codec,
      preferenceKey: 'custom.key',
      prefsOverride: prefs,
    );
    await store.save({
      _Action.zoomIn: const KeyBinding(key: LogicalKeyboardKey.keyZ),
    });
    expect(prefs.getString('custom.key'), isNotNull);
    expect(prefs.getString('settings.shortcutBindings'), isNull);
  });
}
