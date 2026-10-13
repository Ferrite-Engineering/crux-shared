// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_table/crux_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Col { first, second, third }

const _cols = CruxTableColumns<_Col>(
  columns: [_Col.first, _Col.second, _Col.third],
  defaultWeights: {_Col.first: 1, _Col.second: 1, _Col.third: 2},
);

final _providers = CruxColumnLayoutProviders<_Col>(
  columns: _cols,
  prefsKey: 'test.widths',
  name: 'testColumnLayout',
);

const _labels = <_Col, String>{
  _Col.first: 'First',
  _Col.second: 'Second',
  _Col.third: 'Third',
};

/// The 32 px check box column every table in the suite leads with.
const double _leading = 32;

/// A header over one body row, the shape every table in the suite has.
class _Table extends ConsumerStatefulWidget {
  const _Table({
    this.labels = _labels,
    this.annotation,
    this.withController = true,
  });

  final Map<_Col, String> labels;
  final Widget? annotation;
  final bool withController;

  @override
  ConsumerState<_Table> createState() => _TableState();
}

class _TableState extends ConsumerState<_Table> {
  _Col sorted = _Col.second;
  bool ascending = true;

  void _sort(_Col column) {
    setState(() {
      if (sorted == column) {
        ascending = !ascending;
      } else {
        sorted = column;
        ascending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(_providers.layout);
    return Column(
      children: <Widget>[
        CruxTableHeader<_Col>(
          tableId: 't',
          layout: layout,
          controller: widget.withController
              ? ref.read(_providers.layout.notifier)
              : null,
          leading: const <Widget>[SizedBox(width: _leading)],
          cellBuilder: (context, column) => CruxSortableHeaderCell(
            key: cruxTableHeaderKey('t', column),
            label: widget.labels[column]!,
            sorted: sorted == column,
            ascending: ascending,
            onTap: () => _sort(column),
          ),
        ),
        SizedBox(
          height: kCruxTableRowHeight,
          child: Row(
            children: <Widget>[
              const SizedBox(width: _leading),
              Expanded(
                child: Row(
                  children: <Widget>[
                    CruxTableCell(
                      key: const ValueKey('cell.first'),
                      text: 'alpha',
                      flex: layout.flexOf(_Col.first),
                      tooltip: '/full/path/alpha',
                    ),
                    CruxTableCell(
                      key: const ValueKey('cell.second'),
                      text: 'beta beta beta beta beta beta beta beta',
                      flex: layout.flexOf(_Col.second),
                      annotation: widget.annotation,
                    ),
                    CruxTableCell(
                      key: const ValueKey('cell.third'),
                      text: 'gamma',
                      flex: layout.flexOf(_Col.third),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<SharedPreferences> _pump(
  WidgetTester tester, {
  Widget table = const _Table(),
  CruxColumnLayout<_Col>? launch,
  Locale? locale,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        _providers.settingsService.overrideWithValue(
          SettingsService<CruxColumnLayout<_Col>>(
            _providers.codec,
            prefsOverride: prefs,
          ),
        ),
        if (launch != null) _providers.launchOverride(launch),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: locale == null
            ? null
            : GlobalMaterialLocalizations.delegates,
        supportedLocales: locale == null
            ? const <Locale>[Locale('en')]
            : <Locale>[locale],
        home: Scaffold(body: table),
      ),
    ),
  );
  return prefs;
}

/// The right edge of the divider after [column]: where the column ends.
double _dividerRight(WidgetTester tester, _Col column) =>
    tester.getRect(find.byKey(cruxTableResizeKey('t', column))).right;

double _cellRight(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey<String>(key))).right;

void main() {
  // 800 px wide surface less the 32 px check box column, over a total
  // weight of 4: the first two columns are 192 px, the third 384 px.
  const tableWidth = 800 - _leading;

  testWidgets('the header carries the suite tokens and the row height', (
    tester,
  ) async {
    await _pump(tester);
    final context = tester.element(find.byType(CruxTableHeader<_Col>));
    final theme = Theme.of(context);
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(CruxTableHeader<_Col>),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, theme.colorScheme.surfaceContainerHighest);
    expect(decoration.border!.bottom.color, theme.colorScheme.outlineVariant);
    expect(
      tester.getSize(find.byType(CruxTableHeader<_Col>)).height,
      kCruxTableRowHeight,
    );
    final label = tester.widget<Text>(find.text('First'));
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.color, theme.colorScheme.onSurfaceVariant);
    expect(label.style!.fontSize, theme.textTheme.labelMedium!.fontSize);
    expect(label.overflow, TextOverflow.ellipsis);
  });

  testWidgets('a drag moves the header and the row together, then saves', (
    tester,
  ) async {
    final prefs = await _pump(tester);
    expect(_dividerRight(tester, _Col.first), _leading + 192);
    expect(_cellRight(tester, 'cell.first'), _leading + 192);
    expect(prefs.getString('test.widths'), isNull);

    await tester.drag(
      find.byKey(cruxTableResizeKey('t', _Col.first)),
      const Offset(40, 0),
    );
    // Lets the divider's double-tap recognizer drop its countdown.
    await tester.pump(const Duration(milliseconds: 100));

    expect(_dividerRight(tester, _Col.first), closeTo(_leading + 232, 0.5));
    expect(_cellRight(tester, 'cell.first'), closeTo(_leading + 232, 0.5));
    expect(
      _dividerRight(tester, _Col.second),
      closeTo(_leading + 384, 0.5),
      reason: 'the next column gave the width; the rest did not move',
    );
    final saved = jsonDecode(prefs.getString('test.widths')!) as Map;
    expect(saved['first'], closeTo(1 + 40 * 4 / tableWidth, 1e-9));
    expect(saved['second'], closeTo(1 - 40 * 4 / tableWidth, 1e-9));
    expect(saved['third'], 2.0);
  });

  testWidgets('a double-click on a divider restores and saves the defaults', (
    tester,
  ) async {
    final prefs = await _pump(tester);
    final handle = find.byKey(cruxTableResizeKey('t', _Col.first));
    await tester.drag(handle, const Offset(40, 0));
    await tester.pump();
    expect(_cellRight(tester, 'cell.first'), isNot(_leading + 192));

    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(handle);
    // Lets the double-tap recognizer's own countdown run out.
    await tester.pump(const Duration(milliseconds: 100));

    expect(_cellRight(tester, 'cell.first'), _leading + 192);
    expect(
      jsonDecode(prefs.getString('test.widths')!),
      {'first': 1.0, 'second': 1.0, 'third': 2.0},
    );
  });

  testWidgets('no divider after the last column, none without a controller', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(cruxTableResizeKey('t', _Col.first)), findsOneWidget);
    expect(find.byKey(cruxTableResizeKey('t', _Col.second)), findsOneWidget);
    expect(find.byKey(cruxTableResizeKey('t', _Col.third)), findsNothing);
    expect(
      _cellRight(tester, 'cell.third'),
      800,
      reason: 'the last column reaches the edge: no reserved slot after it',
    );

    await _pump(tester, table: const _Table(withController: false));
    expect(find.byType(CruxColumnResizeHandle<_Col>), findsNothing);
  });

  testWidgets('the dividers are outside semantics and the Tab order', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(walk.stops.map((s) => s.line), <String>[
      'First button',
      'Second button',
      'Third button',
    ]);
    expect(
      find.bySemanticsLabel('alpha'),
      findsNothing,
      reason: 'a body cell is not announced on its own',
    );
    handle.dispose();
  });

  testWidgets('the sort arrow sits on the sorted column only and flips', (
    tester,
  ) async {
    await _pump(tester);
    Finder arrowIn(_Col column, IconData icon) => find.descendant(
      of: find.byKey(cruxTableHeaderKey('t', column)),
      matching: find.byIcon(icon),
    );
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(arrowIn(_Col.second, Icons.arrow_drop_up), findsOneWidget);

    await tester.tap(find.byKey(cruxTableHeaderKey('t', _Col.third)));
    await tester.pump();
    expect(arrowIn(_Col.second, Icons.arrow_drop_up), findsNothing);
    expect(arrowIn(_Col.third, Icons.arrow_drop_up), findsOneWidget);

    await tester.tap(find.byKey(cruxTableHeaderKey('t', _Col.third)));
    await tester.pump();
    expect(arrowIn(_Col.third, Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
  });

  testWidgets(
    'the label may use the whole cell less padding and the arrow slot',
    (tester) async {
      await _pump(tester);
      // A 192 px column less its 8 px divider is a 184 px cell.
      const cell = 192 - kCruxTableResizeHandleWidth;
      final sorted = tester.renderObject<RenderBox>(find.text('Second'));
      expect(
        sorted.constraints.maxWidth,
        cell - 2 * kCruxTableCellPadding - kCruxTableSortArrowSize,
      );
      final unsorted = tester.renderObject<RenderBox>(find.text('First'));
      expect(unsorted.constraints.maxWidth, cell - 2 * kCruxTableCellPadding);
    },
  );

  testWidgets('a body cell shows its full value on hover only', (
    tester,
  ) async {
    await _pump(tester);
    final tooltips = tester
        .widgetList<Tooltip>(
          find.descendant(
            of: find.byKey(const ValueKey('cell.first')),
            matching: find.byType(Tooltip),
          ),
        )
        .toList();
    expect(tooltips, hasLength(1));
    expect(tooltips.single.message, '/full/path/alpha');
    expect(tooltips.single.triggerMode, TooltipTriggerMode.manual);
    final plain = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const ValueKey('cell.third')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(plain.message, 'gamma', reason: 'the text itself when not given');
    expect(
      tester.widget<Text>(find.text('gamma')).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('an annotation renders inside its cell after the text', (
    tester,
  ) async {
    await _pump(
      tester,
      table: const _Table(
        annotation: SizedBox(key: ValueKey('anno'), width: 40, height: 10),
      ),
    );
    final cell = tester.getRect(find.byKey(const ValueKey('cell.second')));
    final anno = tester.getRect(find.byKey(const ValueKey('anno')));
    expect(anno.width, 40, reason: 'natural width when there is room');
    expect(anno.right, cell.right - kCruxTableCellPadding);
    final text = tester.renderObject<RenderBox>(
      find.text('beta beta beta beta beta beta beta beta'),
    );
    expect(
      text.constraints.maxWidth,
      cell.width - 2 * kCruxTableCellPadding - CruxTableCell.annotationGap - 40,
      reason: 'the text ellipsizes before the annotation shrinks',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('in a cell too narrow for both, the annotation scales down', (
    tester,
  ) async {
    // The second column at 0.2 of a total 3.2 over 768 px is 48 px wide:
    // 32 px inside the padding, of which the text keeps 24 and the gap 6.
    await _pump(
      tester,
      launch: CruxColumnLayout<_Col>(_cols, const {_Col.second: 0.2}),
      table: const _Table(
        annotation: SizedBox(key: ValueKey('anno'), width: 40, height: 10),
      ),
    );
    final anno = tester.getRect(find.byKey(const ValueKey('anno')));
    expect(anno.width, lessThan(40));
    expect(anno.width, closeTo(2, 0.5));
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });

  testWidgets('a restored tab draws at its saved widths on the first frame', (
    tester,
  ) async {
    await _pump(
      tester,
      launch: CruxColumnLayout<_Col>(_cols, const {
        _Col.first: 2,
        _Col.third: 1,
      }),
    );
    // Weights 2, 1, 1 over 768 px.
    expect(_cellRight(tester, 'cell.first'), _leading + 384);
    expect(_cellRight(tester, 'cell.second'), _leading + 576);
  });

  group('locale sweep', () {
    // Not a const map: `Locale` overrides `==`, which a const key may not.
    final sweeps = <Locale, Map<_Col, String>>{
      const Locale('zh', 'CN'): {
        _Col.first: '严重性',
        _Col.second: '引擎',
        _Col.third: '消息',
      },
      const Locale('zh'): {
        _Col.first: '規則',
        _Col.second: '檔案',
        _Col.third: '訊息',
      },
      const Locale('ja'): {
        _Col.first: '重大度',
        _Col.second: 'エンジン',
        _Col.third: 'メッセージ',
      },
      const Locale('ko'): {
        _Col.first: '심각도',
        _Col.second: '엔진',
        _Col.third: '메시지',
      },
    };
    for (final entry in sweeps.entries) {
      testWidgets('${entry.key} renders the header and sorts', (tester) async {
        await _pump(
          tester,
          locale: entry.key,
          table: _Table(labels: entry.value),
        );
        for (final label in entry.value.values) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.byKey(cruxTableHeaderKey('t', _Col.third)));
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(cruxTableHeaderKey('t', _Col.third)),
            matching: find.byIcon(Icons.arrow_drop_up),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
