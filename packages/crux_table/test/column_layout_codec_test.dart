// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_table/crux_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Col { a, b, c }

const _cols = CruxTableColumns<_Col>(
  columns: [_Col.a, _Col.b, _Col.c],
  defaultWeights: {_Col.a: 1, _Col.b: 2, _Col.c: 1},
);

const _codec = CruxColumnLayoutCodec<_Col>(
  prefsKey: 'settings.testColumnWeights',
  columns: _cols,
);

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  test('round-trips a layout under the given key', () async {
    final prefs = await _prefs();
    final layout = CruxColumnLayout<_Col>(_cols, const {
      _Col.a: 1.5,
      _Col.b: 1.5,
    });
    await _codec.save(prefs, layout);
    expect(
      jsonDecode(prefs.getString('settings.testColumnWeights')!),
      {'a': 1.5, 'b': 1.5, 'c': 1.0},
      reason: 'one JSON object of column name to weight',
    );
    expect(await _codec.load(prefs), layout);
  });

  test('loads the defaults when nothing is stored', () async {
    expect(await _codec.load(await _prefs()), _cols.defaults);
  });

  test(
    'a document written for the same key by a product codec loads',
    () async {
      // The shape a product's own codec wrote: partial, numbers as ints.
      final prefs = await _prefs({
        'settings.testColumnWeights': '{"a": 3, "zz": 9}',
      });
      final layout = await _codec.load(prefs);
      expect(layout.weights, {_Col.a: 3, _Col.b: 2, _Col.c: 1});
    },
  );

  test('unreadable storage falls back to the defaults', () async {
    for (final raw in <Object>['not json', '[1, 2]', 42, '{"a": "wide"}']) {
      final prefs = await _prefs({'settings.testColumnWeights': raw});
      expect(await _codec.load(prefs), _cols.defaults, reason: '$raw');
    }
  });

  test('an invalid stored weight keeps the others', () async {
    final prefs = await _prefs({
      'settings.testColumnWeights': '{"a": -4, "b": 5}',
    });
    final layout = await _codec.load(prefs);
    expect(layout.weights, {_Col.a: 1, _Col.b: 5, _Col.c: 1});
  });
}
