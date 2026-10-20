// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_dock/crux_dock.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show CruxDesktopTokens, CruxPanelEmptyState;
import 'package:crux_settings_ui/crux_settings_ui.dart' show CruxFormRow;
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One editable canvas object of the harness.
class _Cell {
  _Cell(this.name, {this.readOnly = false});

  String name;
  bool locked = false;
  final bool readOnly;
}

/// A canvas of cells beside a two-tab dock (Values, Inspector): the shape
/// every product mounts the inspector in.
class _Host extends StatefulWidget {
  const _Host({
    this.cells,
    this.withProSeam = true,
    this.sinkCount = 0,
    super.key,
  });

  final Map<String, _Cell>? cells;
  final bool withProSeam;
  final int sinkCount;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final Map<String, _Cell> cells =
      widget.cells ??
      <String, _Cell>{
        'a': _Cell('alpha'),
        'b': _Cell('beta'),
        'c': _Cell('gamma', readOnly: true),
      };
  final FocusNode canvasFocus = FocusNode(debugLabel: 'canvas');
  late final CruxInspectorController controller = CruxInspectorController(
    onReveal: () => setState(() => activeTab = 'inspector'),
  );
  String? selected;
  String activeTab = 'values';

  /// Unapplied edits per cell: host state, as a product keeps them in a
  /// per-tab provider, so they outlast the dock rebuilding the tab.
  final Map<String, _Draft> drafts = <String, _Draft>{};

  void select(String? id) => setState(() => selected = id);

  void showTab(String id) => setState(() => activeTab = id);

  void showInspector([String? id]) => setState(() {
    if (id != null) selected = id;
    activeTab = 'inspector';
  });

  void remove(String id) => setState(() => cells.remove(id));

  @override
  void dispose() {
    canvasFocus.dispose();
    controller.dispose();
    super.dispose();
  }

  Widget? _general(BuildContext context, String id) {
    final cell = cells[id];
    if (cell == null) return null;
    if (cell.readOnly) {
      return CruxInspectorSection(
        title: 'Cell',
        children: <Widget>[
          CruxInspectorValueRow(label: 'Name', value: cell.name),
          const CruxInspectorValueRow(label: 'Type', value: r'$dff'),
        ],
      );
    }
    return _CellSection(
      key: ValueKey<String>('section-$id'),
      cell: cell,
      draft: drafts.putIfAbsent(id, () => _Draft(cell)),
      onApplied: () => setState(() => drafts.remove(id)),
    );
  }

  Widget? _pro(BuildContext context, String id) {
    if (id != 'b') return null;
    return const CruxInspectorSection(
      title: 'Custom symbol',
      trailing: Text('Pro'),
      children: <Widget>[CruxInspectorValueRow(label: 'Symbol', value: 'none')],
    );
  }

  Widget? _sinks(BuildContext context, String id) {
    if (widget.sinkCount == 0 || cells[id] == null) return null;
    return CruxInspectorListSection(
      title: 'Sinks',
      itemCount: widget.sinkCount,
      itemBuilder: (context, i) => CruxInspectorValueRow(
        key: ValueKey<int>(i),
        label: i == 0 ? 'Sinks' : '',
        value: 'u_$i.D',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Focus(
            focusNode: canvasFocus,
            child: Semantics(
              label: 'Schematic',
              child: Column(
                children: <Widget>[
                  for (final id in cells.keys)
                    GestureDetector(
                      key: ValueKey<String>('canvas-$id'),
                      onTap: () => select(id),
                      onDoubleTap: () {
                        select(id);
                        controller.open();
                      },
                      child: SizedBox(
                        width: 120,
                        height: 40,
                        child: Center(child: Text('cell $id')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 360,
          child: CruxDock(
            semanticsLabel: 'Right dock',
            activeId: activeTab,
            onSelect: (id) => setState(() => activeTab = id),
            entries: <CruxDockEntry>[
              CruxDockEntry(
                id: 'values',
                icon: Icons.data_object,
                label: 'Values',
                builder: (_) => const SizedBox.expand(),
              ),
              CruxDockEntry(
                id: 'inspector',
                icon: Icons.info_outline,
                label: 'Inspector',
                builder: (_) => CruxInspector<String>(
                  selection: selected,
                  controller: controller,
                  onEscape: canvasFocus.requestFocus,
                  emptyMessage: 'Select a cell to inspect.',
                  title: (id) => 'Cell $id',
                  heldMessage: (id) =>
                      'Apply or revert the changes to cell $id to follow '
                      'the selection.',
                  sections: <CruxInspectorSectionBuilder<String>>[
                    _general,
                    if (widget.withProSeam) _pro,
                    _sinks,
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

/// A cell's unapplied edits.
class _Draft {
  _Draft(_Cell cell) : name = cell.name, locked = cell.locked;

  String name;
  bool locked;
}

/// An editable section whose edits apply on Apply (or Enter).
class _CellSection extends StatefulWidget {
  const _CellSection({
    required this.cell,
    required this.draft,
    required this.onApplied,
    super.key,
  });

  final _Cell cell;
  final _Draft draft;
  final VoidCallback onApplied;

  @override
  State<_CellSection> createState() => _CellSectionState();
}

class _CellSectionState extends State<_CellSection> {
  late final TextEditingController name = TextEditingController(
    text: widget.draft.name,
  );

  bool get locked => widget.draft.locked;

  bool get dirty =>
      name.text != widget.cell.name || locked != widget.cell.locked;

  @override
  void initState() {
    super.initState();
    // A section mounted over a kept draft says so, so the hold is right.
    CruxInspector.markDirty(context, dirty: dirty);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _changed() {
    widget.draft.name = name.text;
    setState(() {});
    CruxInspector.markDirty(context, dirty: dirty);
  }

  void _apply() {
    widget.cell
      ..name = name.text
      ..locked = locked;
    CruxInspector.markDirty(context, dirty: false);
    widget.onApplied();
  }

  void _revert() {
    name.text = widget.cell.name;
    widget.draft.locked = widget.cell.locked;
    _changed();
  }

  @override
  Widget build(BuildContext context) => CruxInspectorSection(
    title: 'Cell',
    onSubmit: dirty ? _apply : null,
    footer: CruxInspectorApplyBar(
      applyLabel: 'Apply',
      revertLabel: 'Revert',
      onApply: dirty ? _apply : null,
      onRevert: dirty ? _revert : null,
    ),
    children: <Widget>[
      CruxFormRow(
        label: 'Name',
        child: TextField(
          key: const Key('nameField'),
          controller: name,
          onChanged: (_) => _changed(),
        ),
      ),
      CruxFormRow.checkbox(
        label: 'Locked',
        value: locked,
        onChanged: (v) {
          widget.draft.locked = v;
          _changed();
        },
      ),
      const CruxInspectorValueRow(label: 'Type', value: r'$dff'),
    ],
  );
}

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4650C8),
          brightness: brightness,
        ),
        extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
      ),
      home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
    );

_HostState _host(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _showInspector(WidgetTester tester, String id) async {
  _host(tester).showInspector(id);
  await tester.pumpAndSettle();
}

bool _nameFieldFocused(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('nameField')),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

void main() {
  testWidgets('with nothing selected it shows the panel empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    _host(tester).showInspector();
    await tester.pumpAndSettle();
    expect(find.byType(CruxPanelEmptyState), findsOneWidget);
    expect(find.text('Select a cell to inspect.'), findsOneWidget);
  });

  testWidgets('a double-click on the canvas opens it with focus on its first '
      'control', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Host()));
    expect(find.byType(CruxInspector<String>), findsNothing);

    await _doubleTap(tester, find.byKey(const ValueKey<String>('canvas-a')));

    expect(find.text('Cell a'), findsOneWidget);
    expect(_nameFieldFocused(tester), isTrue);
    expectFocusAnnounced(tester, named: 'Name', context: 'after open');
    handle.dispose();
  });

  testWidgets('Escape returns focus to the canvas and keeps the selection', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await _doubleTap(tester, find.byKey(const ValueKey<String>('canvas-a')));
    expect(_nameFieldFocused(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_host(tester).canvasFocus.hasFocus, isTrue);
    expect(_host(tester).selected, 'a');
    expect(find.text('Cell a'), findsOneWidget);
  });

  testWidgets('Escape while an input method composes is left to the field', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await _doubleTap(tester, find.byKey(const ValueKey<String>('canvas-a')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'alphaか',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_host(tester).canvasFocus.hasFocus, isFalse);
  });

  testWidgets('a read-only object takes focus on its named heading', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Host()));
    await _doubleTap(tester, find.byKey(const ValueKey<String>('canvas-c')));
    expectFocusAnnounced(tester, named: 'Cell c', context: 'read-only open');
    handle.dispose();
  });

  testWidgets('an open made while the tab is hidden waits for it to show', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    final host = _host(tester)..select('a');
    // A controller with no reveal: the request stays pending.
    final pending = CruxInspectorController()..open();
    expect(pending.focusPending, isTrue);
    pending.dispose();

    host.controller.open();
    await tester.pumpAndSettle();
    expect(_nameFieldFocused(tester), isTrue);
    expect(host.controller.focusPending, isFalse);
  });

  testWidgets('another selection rebuilds the section from that object', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    expect(find.widgetWithText(TextField, 'alpha'), findsOneWidget);

    _host(tester).select('b');
    await tester.pumpAndSettle();
    expect(find.text('Cell b'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'beta'), findsOneWidget);
  });

  testWidgets('unapplied edits hold the object, say so, and Apply releases '
      'it', (tester) async {
    final recorder = AnnouncementRecorder.attach(tester);
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    await tester.enterText(find.byKey(const Key('nameField')), 'alpha2');
    await tester.pump();
    // The same object again (a rebuild with the same selection) is not a move.
    _host(tester).select('a');
    await tester.pump();
    expect(_host(tester).controller.dirty, isTrue);

    _host(tester).select('b');
    await tester.pumpAndSettle();

    const notice =
        'Apply or revert the changes to cell a to follow the selection.';
    expect(find.text('Cell a'), findsOneWidget);
    expect(find.text(notice), findsOneWidget);
    expect(recorder.messages, contains(notice));

    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(_host(tester).cells['a']!.name, 'alpha2');
    expect(find.text('Cell b'), findsOneWidget);
    expect(find.text(notice), findsNothing);
  });

  testWidgets('a hold outlasts the dock showing another tab', (tester) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    await tester.enterText(find.byKey(const Key('nameField')), 'alpha2');
    await tester.pump();
    _host(tester).select('b');
    await tester.pumpAndSettle();

    _host(tester).showTab('values');
    await tester.pumpAndSettle();
    expect(find.byType(CruxInspector<String>), findsNothing);
    _host(tester).showTab('inspector');
    await tester.pumpAndSettle();

    expect(find.text('Cell a'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'alpha2'), findsOneWidget);
    expect(
      find.text(
        'Apply or revert the changes to cell a to follow the selection.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Revert releases a held object too', (tester) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    await tester.enterText(find.byKey(const Key('nameField')), 'alpha2');
    await tester.pump();
    _host(tester).select('b');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Revert'));
    await tester.pumpAndSettle();

    expect(_host(tester).cells['a']!.name, 'alpha');
    expect(find.text('Cell b'), findsOneWidget);
  });

  testWidgets('a held object that is deleted lets the selection through', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    await tester.enterText(find.byKey(const Key('nameField')), 'alpha2');
    await tester.pump();

    _host(tester)
      ..remove('a')
      ..select('b');
    await tester.pumpAndSettle();

    expect(find.text('Cell b'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'beta'), findsOneWidget);
  });

  testWidgets('Enter in a single-line field applies the section', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    await tester.enterText(find.byKey(const Key('nameField')), 'renamed');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_host(tester).cells['a']!.name, 'renamed');
    expect(find.widgetWithText(FilledButton, 'Apply'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Enter on a focused checkbox toggles it and does not apply', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    await tester.enterText(find.byKey(const Key('nameField')), 'renamed');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_host(tester).cells['a']!.name, 'alpha');
    expect(_host(tester).drafts['a']!.locked, isTrue);
  });

  testWidgets('a read-only object with header actions focuses the first '
      'action', (tester) async {
    final controller = CruxInspectorController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        CruxInspector<String>(
          selection: 'n1',
          controller: controller,
          emptyMessage: 'Nothing selected.',
          title: (id) => 'Net $id',
          headerActions: (context, id) => <Widget>[
            TextButton(onPressed: () {}, child: const Text('Go to source')),
          ],
          sections: <CruxInspectorSectionBuilder<String>>[
            (context, id) => const CruxInspectorSection(
              title: 'Net',
              children: <Widget>[
                CruxInspectorValueRow(label: 'Width', value: '8'),
              ],
            ),
          ],
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(
        of: find.byWidget(focused.widget),
        matching: find.widgetWithText(TextButton, 'Go to source'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a new controller with a pending open takes over; cancel '
      'withdraws one', (tester) async {
    final first = CruxInspectorController();
    final second = CruxInspectorController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget inspector(CruxInspectorController c) => _app(
      CruxInspector<String>(
        selection: 'x',
        controller: c,
        emptyMessage: 'Nothing selected.',
        title: (id) => 'Item $id',
        sections: <CruxInspectorSectionBuilder<String>>[
          (context, id) => const CruxInspectorSection(
            title: 'Item',
            children: <Widget>[
              CruxFormRow(label: 'Name', child: TextField()),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(inspector(first));
    first
      ..open()
      ..cancel();
    expect(first.focusPending, isFalse);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );

    second.open();
    await tester.pumpWidget(inspector(second));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus!.context!
          .findAncestorWidgetOfExactType<TextField>(),
      isNotNull,
    );
  });

  testWidgets('a list section outside an inspector builds every row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        CruxInspectorListSection(
          title: 'Ports',
          trailing: const Text('Pro'),
          itemCount: 3,
          itemBuilder: (context, i) =>
              CruxInspectorValueRow(label: 'p$i', value: 'in'),
        ),
      ),
    );
    expect(find.text('Ports'), findsOneWidget);
    expect(find.byType(CruxInspectorValueRow), findsNWidgets(3));
  });

  testWidgets('a section builder returning null is skipped; the Pro seam '
      'section carries its badge', (tester) async {
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    expect(find.text('Custom symbol'), findsNothing);

    _host(tester).select('b');
    await tester.pumpAndSettle();
    expect(find.text('Custom symbol'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
  });

  testWidgets('every builder skipped shows the empty state', (tester) async {
    await tester.pumpWidget(
      _app(const _Host(cells: <String, _Cell>{}, withProSeam: false)),
    );
    await _showInspector(tester, 'gone');
    expect(find.byType(CruxPanelEmptyState), findsOneWidget);
  });

  testWidgets('a list section builds only the rows on screen', (tester) async {
    await tester.pumpWidget(_app(const _Host(sinkCount: 100000)));
    await _showInspector(tester, 'c');
    expect(find.text('u_0.D'), findsOneWidget);
    expect(find.byType(CruxInspectorValueRow).evaluate().length, lessThan(80));
  });

  testWidgets('two inspectors keep their own focus requests', (tester) async {
    final first = GlobalKey<_HostState>();
    final second = GlobalKey<_HostState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
        ),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              SizedBox(width: 900, height: 300, child: _Host(key: first)),
              SizedBox(width: 900, height: 300, child: _Host(key: second)),
            ],
          ),
        ),
      ),
    );
    first.currentState!.showInspector('a');
    second.currentState!.showInspector('b');
    await tester.pumpAndSettle();

    second.currentState!.controller.open();
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.descendant(
        of: find.byKey(second),
        matching: find.byWidget(focused.widget),
      ),
      findsOneWidget,
    );
    expect(first.currentState!.controller.focusPending, isFalse);
  });

  testWidgets('value rows are one node each and never a Tab stop', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'c');
    expect(
      tester.getSemantics(find.byType(CruxInspectorValueRow).last),
      matchesSemantics(label: 'Type', value: r'$dff'),
    );
    final walk = await walkFocus(tester);
    expect(walk.transcript, isNot(contains(r'$dff')));
    handle.dispose();
  });

  testWidgets('focus walk: dock tabs, then the inspector form', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Host()));
    await _showInspector(tester, 'a');
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_inspector.txt');
    handle.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('meets the labelling and contrast guidelines '
        '(${brightness.name})', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const _Host(), brightness: brightness));
      await _showInspector(tester, 'b');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  test('the inspector opens no route', () {
    // Being a dock tab, not a route, is what keeps it inside the editor
    // tab's provider scope. A route opened from here would mount above it.
    final source = File('lib/src/crux_inspector.dart').readAsStringSync();
    final routeApis = RegExp(
      r'\b(showDialog|showCruxDialog|showGeneralDialog|showModalBottomSheet|'
      r'showBottomSheet|showMenu|Navigator\s*\.)',
    );
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(routeApis.hasMatch(code), isFalse);
  });
}
