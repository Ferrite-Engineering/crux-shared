// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = Color(0xFF102030);
const _b = Color(0xFF506070);

const _full = CruxChromeColors(
  toolbarIconActive: Color(0xFF000001),
  statusBarBackground: Color(0xFF000002),
  statusBarForeground: Color(0xFF000003),
  splitter: Color(0xFF000004),
  splitterHover: Color(0xFF000005),
  tabBarBackground: Color(0xFF000006),
  tabBarSelected: Color(0xFF000007),
  tabBarLabel: Color(0xFF000008),
);

/// Every field, read by name, so a field added to the class without being
/// threaded through `==`, `copyWith` and `lerp` fails below.
List<Color?> _fields(CruxChromeColors c) => [
  c.toolbarIconActive,
  c.statusBarBackground,
  c.statusBarForeground,
  c.splitter,
  c.splitterHover,
  c.tabBarBackground,
  c.tabBarSelected,
  c.tabBarLabel,
];

void main() {
  group('CruxChromeColors', () {
    test('an empty instance sets nothing', () {
      expect(const CruxChromeColors().isEmpty, isTrue);
      expect(_fields(const CruxChromeColors()), everyElement(isNull));
      expect(_full.isEmpty, isFalse);
      expect(const CruxChromeColors(tabBarLabel: _a).isEmpty, isFalse);
    });

    test('equality and hashCode cover every field', () {
      expect(_full, _full.copyWith());
      expect(_full.hashCode, _full.copyWith().hashCode);
      final variants = [
        _full.copyWith(toolbarIconActive: _a),
        _full.copyWith(statusBarBackground: _a),
        _full.copyWith(statusBarForeground: _a),
        _full.copyWith(splitter: _a),
        _full.copyWith(splitterHover: _a),
        _full.copyWith(tabBarBackground: _a),
        _full.copyWith(tabBarSelected: _a),
        _full.copyWith(tabBarLabel: _a),
      ];
      for (var i = 0; i < variants.length; i++) {
        expect(variants[i], isNot(_full), reason: 'field $i');
        expect(_fields(variants[i])[i], _a, reason: 'copyWith field $i');
      }
    });

    test('lerp interpolates fields set on both sides', () {
      const other = CruxChromeColors(
        toolbarIconActive: _b,
        statusBarBackground: _b,
        statusBarForeground: _b,
        splitter: _b,
        splitterHover: _b,
        tabBarBackground: _b,
        tabBarSelected: _b,
        tabBarLabel: _b,
      );
      const from = CruxChromeColors(
        toolbarIconActive: _a,
        statusBarBackground: _a,
        statusBarForeground: _a,
        splitter: _a,
        splitterHover: _a,
        tabBarBackground: _a,
        tabBarSelected: _a,
        tabBarLabel: _a,
      );
      final mid = from.lerp(other, 0.5);
      for (final value in _fields(mid)) {
        expect(value, Color.lerp(_a, _b, 0.5));
      }
    });

    // Null means "the widget's own colour". Fading toward transparent would
    // paint a colour neither theme has, so a one-sided field switches over.
    test('lerp switches a one-sided field at the midpoint', () {
      const from = CruxChromeColors(statusBarBackground: _a);
      const to = CruxChromeColors(tabBarLabel: _b);
      final early = from.lerp(to, 0.25);
      expect(early.statusBarBackground, _a);
      expect(early.tabBarLabel, isNull);
      final late = from.lerp(to, 0.75);
      expect(late.statusBarBackground, isNull);
      expect(late.tabBarLabel, _b);
    });

    test('lerp against a foreign extension keeps this one', () {
      expect(_full.lerp(null, 0.5), same(_full));
    });

    testWidgets('of reads the ambient theme', (tester) async {
      CruxChromeColors? seen;
      Widget reader(ThemeData data) => Theme(
        data: data,
        child: Builder(
          builder: (context) {
            seen = CruxChromeColors.of(context);
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(reader(ThemeData(extensions: const [_full])));
      expect(seen, _full);

      await tester.pumpWidget(reader(ThemeData()));
      expect(seen, isNull);
    });
  });
}
