// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _A { open, save, close, search, crossProbe, settings, zoomIn, zoomOut }

Widget _wrap({
  required List<CruxToolbarItem<_A>> common,
  List<CruxToolbarItem<_A>> specific = const [],
  bool Function(_A)? isEnabled,
  void Function(_A)? onAction,
  ShortcutActivator? Function(_A)? shortcutOf,
  Widget? overflow,
  CruxToolbarMetrics metrics = CruxToolbarMetrics.desktop,
  double width = 800,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: CruxToolbar<_A>(
        common: common,
        specific: specific,
        isEnabled: isEnabled ?? (_) => true,
        onAction: onAction ?? (_) {},
        shortcutOf: shortcutOf ?? (_) => null,
        semanticsLabel: 'Toolbar',
        metrics: metrics,
        overflow: overflow,
      ),
    ),
  ),
);

CruxToolbarButtonItem<_A> _btn(
  _A action,
  IconData icon, {
  String? tooltip,
  bool isSelected = false,
  IconData? selectedIcon,
  int badgeCount = 0,
}) => CruxToolbarButtonItem<_A>(
  action: action,
  icon: icon,
  tooltip: tooltip ?? action.name,
  isSelected: isSelected,
  selectedIcon: selectedIcon,
  badgeCount: badgeCount,
);

void main() {
  group('CruxToolbar layout', () {
    testWidgets('renders common, then a divider, then specific', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          common: [_btn(_A.open, Icons.folder_open_outlined)],
          specific: [_btn(_A.zoomIn, Icons.zoom_in)],
        ),
      );
      await tester.pumpAndSettle();

      // One divider between the two sections, and the common button precedes
      // the specific one in paint order.
      expect(find.byType(CruxToolbarDivider), findsOneWidget);
      final openX = tester.getCenter(find.byKey(const ValueKey(_A.open))).dx;
      final zoomX = tester.getCenter(find.byKey(const ValueKey(_A.zoomIn))).dx;
      expect(openX, lessThan(zoomX));
    });

    testWidgets('draws no section divider when specific is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(common: [_btn(_A.open, Icons.folder_open_outlined)]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CruxToolbarDivider), findsNothing);
    });

    testWidgets('renders explicit separators inside a section', (tester) async {
      await tester.pumpWidget(
        _wrap(
          common: [
            _btn(_A.open, Icons.folder_open_outlined),
            const CruxToolbarSeparatorItem<_A>(),
            _btn(_A.search, Icons.search),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CruxToolbarDivider), findsOneWidget);
    });

    testWidgets('keys every button by its action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          common: [
            _btn(_A.open, Icons.folder_open_outlined),
            _btn(_A.settings, Icons.settings_outlined),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(_A.open)), findsOneWidget);
      expect(find.byKey(const ValueKey(_A.settings)), findsOneWidget);
    });

    testWidgets('exposes one labelled semantics region', (tester) async {
      await tester.pumpWidget(
        _wrap(common: [_btn(_A.open, Icons.folder_open_outlined)]),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Toolbar'), findsOneWidget);
    });

    testWidgets('applies the metric set to height and hit box', (tester) async {
      await tester.pumpWidget(
        _wrap(
          common: [_btn(_A.open, Icons.folder_open_outlined)],
          metrics: CruxToolbarMetrics.touch,
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getSize(
        find
            .ancestor(
              of: find.byType(CruxToolbarButton),
              matching: find.byType(SizedBox),
            )
            .last,
      );
      expect(bar.height, CruxToolbarMetrics.touch.height);
      expect(
        tester.getSize(find.byKey(const ValueKey(_A.open))).width,
        CruxToolbarMetrics.touch.buttonSize,
      );
    });
  });

  group('enablement', () {
    testWidgets('a disabled action renders with a null onPressed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          common: [
            _btn(_A.open, Icons.folder_open_outlined),
            _btn(_A.save, Icons.save_outlined),
          ],
          isEnabled: (a) => a != _A.save,
        ),
      );
      await tester.pumpAndSettle();

      IconButton buttonFor(_A a) => tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(ValueKey(a)),
          matching: find.byType(IconButton),
        ),
      );
      expect(buttonFor(_A.open).onPressed, isNotNull);
      expect(buttonFor(_A.save).onPressed, isNull);
    });

    testWidgets('tapping dispatches the action', (tester) async {
      final fired = <_A>[];
      await tester.pumpWidget(
        _wrap(
          common: [_btn(_A.open, Icons.folder_open_outlined)],
          onAction: fired.add,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(_A.open)));
      expect(fired, [_A.open]);
    });

    testWidgets('a disabled button does not dispatch', (tester) async {
      final fired = <_A>[];
      await tester.pumpWidget(
        _wrap(
          common: [_btn(_A.open, Icons.folder_open_outlined)],
          isEnabled: (_) => false,
          onAction: fired.add,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(_A.open)));
      expect(fired, isEmpty);
    });
  });

  group('selected state', () {
    testWidgets('swaps to the selected glyph and tints it', (tester) async {
      await tester.pumpWidget(
        _wrap(
          common: [
            _btn(
              _A.crossProbe,
              Icons.sensors_outlined,
              selectedIcon: Icons.sensors,
              isSelected: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey(_A.crossProbe)),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.sensors);
      expect(icon.color, isNotNull);
    });

    testWidgets('uses the base glyph and no tint when unselected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          common: [
            _btn(
              _A.crossProbe,
              Icons.sensors_outlined,
              selectedIcon: Icons.sensors,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey(_A.crossProbe)),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.sensors_outlined);
      expect(icon.color, isNull);
    });
  });

  group('badges', () {
    testWidgets('renders a badge when the count is positive', (tester) async {
      await tester.pumpWidget(
        _wrap(
          common: [
            _btn(_A.crossProbe, Icons.sensors_outlined, badgeCount: 3),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // The bubble is pointer-transparent decoration: a tap on the badged
      // corner must still reach the button (regression: the old
      // Badge-as-wrapper swallowed taps on the count bubble).
      expect(
        find.ancestor(
          of: find.byType(Badge),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    testWidgets('renders no badge at zero', (tester) async {
      await tester.pumpWidget(
        _wrap(common: [_btn(_A.crossProbe, Icons.sensors_outlined)]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Badge), findsNothing);
    });
  });

  group('overflow', () {
    testWidgets('hides the overflow button when nothing overflows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          common: [_btn(_A.open, Icons.folder_open_outlined)],
          overflow: const Icon(Icons.more_vert, key: Key('overflow')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overflow')), findsNothing);
    });

    testWidgets('shows the overflow button once the strip scrolls', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          width: 120,
          common: [
            for (final a in _A.values) _btn(a, Icons.folder_open_outlined),
          ],
          overflow: const Icon(Icons.more_vert, key: Key('overflow')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overflow')), findsOneWidget);
    });

    testWidgets('the strip scrolls horizontally rather than clipping', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          width: 120,
          common: [
            for (final a in _A.values) _btn(a, Icons.folder_open_outlined),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollable.scrollDirection, Axis.horizontal);
      expect(tester.takeException(), isNull);
    });
  });

  group('cruxToolbarTooltip', () {
    test('appends the live binding when there is one', () {
      const cmdO = SingleActivator(LogicalKeyboardKey.keyO, control: true);
      expect(cruxToolbarTooltip('Open Project…', cmdO), contains('Open'));
      expect(cruxToolbarTooltip('Open Project…', cmdO), contains('Ctrl'));
    });

    test('returns the bare label when the action is unbound', () {
      expect(cruxToolbarTooltip('Open Project…', null), 'Open Project…');
    });
  });
}
