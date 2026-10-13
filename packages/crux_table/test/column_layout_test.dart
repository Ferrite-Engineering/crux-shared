// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/crux_table.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Col { a, b, c }

const _cols = CruxTableColumns<_Col>(
  columns: [_Col.a, _Col.b, _Col.c],
  defaultWeights: {_Col.a: 1, _Col.b: 2, _Col.c: 1},
);

void main() {
  group('CruxTableColumns', () {
    test('defaults to the 56 px minimum and knows its last column', () {
      expect(kCruxTableMinColumnWidth, 56);
      expect(_cols.minColumnWidth, 56);
      expect(_cols.isLast(_Col.c), isTrue);
      expect(_cols.isLast(_Col.a), isFalse);
      expect(_cols.isResizable(_Col.b), isTrue);
    });

    test('a column outside the set is not resizable', () {
      const two = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b],
        defaultWeights: {_Col.a: 1, _Col.b: 1},
      );
      expect(two.isResizable(_Col.c), isFalse);
      expect(two.isLast(_Col.c), isFalse);
    });

    test('equality is by columns, defaults and minimum', () {
      const same = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b, _Col.c],
        defaultWeights: {_Col.a: 1, _Col.b: 2, _Col.c: 1},
      );
      const narrower = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b, _Col.c],
        defaultWeights: {_Col.a: 1, _Col.b: 2, _Col.c: 1},
        minColumnWidth: 40,
      );
      expect(same, _cols);
      expect(same.hashCode, _cols.hashCode);
      expect(narrower, isNot(_cols));
      expect(_cols.toString(), contains('_Col.a'));
    });
  });

  group('CruxColumnLayout', () {
    test('the defaults carry every default weight', () {
      final layout = _cols.defaults;
      expect(layout.weights, {_Col.a: 1, _Col.b: 2, _Col.c: 1});
      expect(layout.totalWeight, 4);
      expect(layout.isDefault, isTrue);
    });

    test('a missing or invalid weight takes its default', () {
      final layout = CruxColumnLayout<_Col>(_cols, const {
        _Col.a: 3,
        _Col.b: -1,
        _Col.c: double.nan,
      });
      expect(layout.weights, {_Col.a: 3, _Col.b: 2, _Col.c: 1});
      expect(layout.isDefault, isFalse);
      expect(
        CruxColumnLayout<_Col>(_cols, const {
          _Col.a: double.infinity,
        }).weights[_Col.a],
        1,
      );
    });

    test('flexOf scales weights to integers a one-pixel drag can move', () {
      final layout = _cols.defaults;
      expect(layout.flexOf(_Col.a), 1000);
      expect(layout.flexOf(_Col.b), 2000);
      expect(
        CruxColumnLayout<_Col>(_cols, const {_Col.a: 0.0001}).flexOf(_Col.a),
        1,
        reason: 'never a zero flex',
      );
    });

    test('resize moves width between neighbours and keeps the total', () {
      // 400 px over a total weight of 4: one pixel is 0.01 weight.
      final resized = _cols.defaults.resize(_Col.a, 50, 400);
      expect(resized.weights[_Col.a], closeTo(1.5, 1e-9));
      expect(resized.weights[_Col.b], closeTo(1.5, 1e-9));
      expect(resized.weights[_Col.c], 1);
      expect(resized.totalWeight, closeTo(4, 1e-9));
      final back = resized.resize(_Col.a, -50, 400);
      expect(back, _cols.defaults);
    });

    test('neither column goes below the minimum width', () {
      final resized = _cols.defaults.resize(_Col.a, -1000, 400);
      expect(resized.weights[_Col.a], closeTo(0.56, 1e-9));
      expect(resized.weights[_Col.b], closeTo(2.44, 1e-9));
      final other = _cols.defaults.resize(_Col.a, 1000, 400);
      expect(other.weights[_Col.b], closeTo(0.56, 1e-9));
    });

    test('resize is a no-op on the last column, off the set, or without '
        'width', () {
      final layout = _cols.defaults;
      expect(identical(layout.resize(_Col.c, 10, 400), layout), isTrue);
      expect(identical(layout.resize(_Col.a, 10, 0), layout), isTrue);
      expect(identical(layout.resize(_Col.a, 0, 400), layout), isTrue);
      const two = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b],
        defaultWeights: {_Col.a: 1, _Col.b: 1},
      );
      final narrow = two.defaults;
      expect(identical(narrow.resize(_Col.c, 10, 400), narrow), isTrue);
    });

    test('two columns that cannot both meet the minimum do not throw', () {
      // 100 px for two columns at 56 px minimum each: the bounds would cross.
      const two = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b],
        defaultWeights: {_Col.a: 1, _Col.b: 1},
      );
      final layout = two.defaults;
      expect(identical(layout.resize(_Col.a, 10, 100), layout), isTrue);
    });

    test('equality is by column weights over the same column set', () {
      final a = CruxColumnLayout<_Col>(_cols, const {_Col.a: 1.5});
      final b = CruxColumnLayout<_Col>(_cols, const {_Col.a: 1.5, _Col.b: 2});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(_cols.defaults));
      const narrower = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b, _Col.c],
        defaultWeights: {_Col.a: 1, _Col.b: 2, _Col.c: 1},
        minColumnWidth: 40,
      );
      expect(narrower.defaults, isNot(_cols.defaults));
      expect(a.toString(), contains('1.5'));
    });

    test('a column without a default weight is a programming error', () {
      const incomplete = CruxTableColumns<_Col>(
        columns: [_Col.a, _Col.b],
        defaultWeights: {_Col.a: 1},
      );
      expect(() => incomplete.defaults, throwsA(isA<AssertionError>()));
    });
  });

  test('key conventions follow <table>Header-<column> and '
      '<table>Resize-<column>', () {
    expect(
      cruxTableHeaderKey('violationTable', _Col.a),
      const ValueKey<String>('violationTableHeader-a'),
    );
    expect(
      cruxTableResizeKey('dashboard', _Col.b),
      const ValueKey<String>('dashboardResize-b'),
    );
  });
}
