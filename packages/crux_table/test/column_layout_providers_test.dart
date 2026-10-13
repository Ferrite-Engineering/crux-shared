// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_table/crux_table.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Col { a, b, c }

const _cols = CruxTableColumns<_Col>(
  columns: [_Col.a, _Col.b, _Col.c],
  defaultWeights: {_Col.a: 1, _Col.b: 2, _Col.c: 1},
);

final _providers = CruxColumnLayoutProviders<_Col>(
  columns: _cols,
  prefsKey: 'test.columnWeights',
  name: 'testColumnLayout',
);

class _ThrowingCodec implements SettingsCodec<CruxColumnLayout<_Col>> {
  const _ThrowingCodec();

  @override
  Future<CruxColumnLayout<_Col>> load(SharedPreferences prefs) =>
      throw StateError('no storage');

  @override
  Future<void> save(SharedPreferences prefs, CruxColumnLayout<_Col> settings) =>
      throw StateError('no storage');
}

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

ProviderContainer _container(List<Override> overrides) {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('names its providers after the table', () {
    expect(_providers.layout.name, 'testColumnLayout');
    expect(_providers.launch.name, 'testColumnLayout.launch');
    expect(
      _providers.settingsService.name,
      'testColumnLayout.settingsService',
    );
    expect(_providers.codec.prefsKey, 'test.columnWeights');
  });

  test('the live layout starts from the launch layout', () {
    final saved = CruxColumnLayout<_Col>(_cols, const {_Col.a: 2.5});
    final container = _container([_providers.launchOverride(saved)]);
    expect(container.read(_providers.layout), saved);
    expect(_container([]).read(_providers.layout), _cols.defaults);
  });

  test('the notifier is the resize controller the dividers drive', () async {
    final prefs = await _prefs();
    final container = _container([
      _providers.settingsService.overrideWithValue(
        SettingsService<CruxColumnLayout<_Col>>(
          _providers.codec,
          prefsOverride: prefs,
        ),
      ),
    ]);
    final controller = container.read(_providers.layout.notifier)
      ..resize(_Col.a, 50, 400);
    expect(controller, isA<CruxColumnResizeController<_Col>>());
    expect(
      container.read(_providers.layout).weights[_Col.a],
      closeTo(1.5, 1e-9),
    );
    expect(
      prefs.getString('test.columnWeights'),
      isNull,
      reason: 'a drag in progress is not saved',
    );
    controller.commit();
    await Future<void>.delayed(Duration.zero);
    expect(
      jsonDecode(prefs.getString('test.columnWeights')!),
      containsPair('a', closeTo(1.5, 1e-9)),
    );
    controller.reset();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(_providers.layout), _cols.defaults);
    expect(
      jsonDecode(prefs.getString('test.columnWeights')!),
      {'a': 1.0, 'b': 2.0, 'c': 1.0},
    );
  });

  test('a save that fails leaves the session widths in place', () async {
    final prefs = await _prefs();
    final container = _container([
      _providers.settingsService.overrideWithValue(
        SettingsService<CruxColumnLayout<_Col>>(
          const _ThrowingCodec(),
          prefsOverride: prefs,
        ),
      ),
    ]);
    final notifier = container.read(_providers.layout.notifier)
      ..resize(_Col.a, 50, 400)
      ..commit();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(_providers.layout).weights[_Col.a],
      closeTo(1.5, 1e-9),
    );
    notifier.reset();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(_providers.layout), _cols.defaults);
  });

  test(
    'load returns the persisted layout, or the defaults on failure',
    () async {
      final prefs = await _prefs({'test.columnWeights': '{"b": 4}'});
      final loaded = await _providers.load(
        service: SettingsService<CruxColumnLayout<_Col>>(
          _providers.codec,
          prefsOverride: prefs,
        ),
      );
      expect(loaded.weights, {_Col.a: 1, _Col.b: 4, _Col.c: 1});
      final fallback = await _providers.load(
        service: SettingsService<CruxColumnLayout<_Col>>(
          const _ThrowingCodec(),
          prefsOverride: prefs,
        ),
      );
      expect(fallback, _cols.defaults);
    },
  );
}
