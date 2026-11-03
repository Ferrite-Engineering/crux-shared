// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxDesktopTokens;
import 'package:crux_settings_ui/crux_settings_ui.dart' show CruxFormRow;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// For sections whose callbacks the test never reads.
final List<String> _unlogged = <String>[];

const Size _panel = Size(320, 260);

final Finder _fade = find.byKey(
  const ValueKey<String>('cruxInspectorScrollFade'),
);
final Finder _bar = find.byKey(
  const ValueKey<String>('cruxInspectorActionBar'),
);
final Finder _inspector = find.byType(CruxInspector<String>);

/// Rows enough to stand taller than [_panel].
List<Widget> _rows(String prefix, {int count = 24}) => <Widget>[
  for (var i = 0; i < count; i++)
    CruxInspectorValueRow(label: '$prefix$i', value: 'value $i'),
];

Future<void> _mount(
  WidgetTester tester,
  List<CruxInspectorSectionBuilder<String>> sections, {
  Size size = _panel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: CruxInspector<String>(
              selection: 'x',
              emptyMessage: 'Select something.',
              sections: sections,
            ),
          ),
        ),
      ),
    ),
  );
  // A section registers its footer while it builds; the bar follows a frame
  // later.
  await tester.pumpAndSettle();
}

/// The widget is on screen inside the Inspector and a pointer there would
/// reach it, with the list left at its top.
void _expectReachable(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  final inspector = tester.getRect(_inspector);
  expect(inspector.contains(rect.center), isTrue);
}

/// A section that is taller than the panel and applies on Apply.
class _ApplySection extends StatefulWidget {
  const _ApplySection({
    required this.title,
    required this.log,
    this.enabled = true,
    this.count = 24,
  });

  final String title;
  final List<String> log;
  final bool enabled;
  final int count;

  @override
  State<_ApplySection> createState() => _ApplySectionState();
}

class _ApplySectionState extends State<_ApplySection> {
  final TextEditingController field = TextEditingController();

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CruxInspectorSection(
    title: widget.title,
    onSubmit: widget.enabled
        ? () => widget.log.add('${widget.title} submit')
        : null,
    footer: CruxInspectorApplyBar(
      applyLabel: 'Apply',
      revertLabel: 'Revert',
      onApply: widget.enabled
          ? () => widget.log.add('${widget.title} apply')
          : null,
      onRevert: widget.enabled
          ? () => widget.log.add('${widget.title} revert')
          : null,
    ),
    children: <Widget>[
      CruxFormRow(
        label: 'Name',
        child: TextField(key: Key('${widget.title}-field'), controller: field),
      ),
      ..._rows(widget.title, count: widget.count),
    ],
  );
}

void main() {
  testWidgets('an Apply bar under a tall section is on screen without '
      'scrolling', (tester) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Cell', log: log),
    ]);

    _expectReachable(tester, find.widgetWithText(FilledButton, 'Apply'));
    _expectReachable(tester, find.widgetWithText(TextButton, 'Revert'));
    // It sits on the Inspector's bottom edge, below every row of the list.
    final inspector = tester.getRect(_inspector);
    final apply = tester.getRect(find.widgetWithText(FilledButton, 'Apply'));
    expect(apply.bottom, lessThanOrEqualTo(inspector.bottom));
    expect(apply.bottom, greaterThan(inspector.bottom - 60));

    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.tap(find.widgetWithText(TextButton, 'Revert'));
    expect(log, <String>['Cell apply', 'Cell revert']);
  });

  testWidgets('the bar has one divider above it and none without a footer', (
    tester,
  ) async {
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) =>
          CruxInspectorSection(title: 'Info', children: _rows('r', count: 3)),
    ]);
    expect(_bar, findsNothing);
    expect(find.byType(Divider), findsNothing);

    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Cell', log: _unlogged, count: 3),
    ]);
    expect(
      find.descendant(of: _bar, matching: find.byType(Divider)),
      findsOneWidget,
    );
  });

  testWidgets('a custom button row in the footer is pinned too', (
    tester,
  ) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => CruxInspectorSection(
        title: 'New decoder',
        footer: Wrap(
          alignment: WrapAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => log.add('cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => log.add('add'),
              child: const Text('Add Decoder'),
            ),
          ],
        ),
        children: _rows('Pin'),
      ),
    ]);

    _expectReachable(tester, find.widgetWithText(FilledButton, 'Add Decoder'));
    _expectReachable(tester, find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.text('Add Decoder'));
    expect(log, <String>['add']);
  });

  testWidgets('a section inside a wrapper widget still pins its footer', (
    tester,
  ) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.zero,
          child: _ApplySection(title: 'Wrapped', log: log),
        ),
      ),
    ]);
    _expectReachable(tester, find.widgetWithText(FilledButton, 'Apply'));
  });

  testWidgets('two Apply sections share one bar that applies and reverts '
      'both', (tester) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Format', log: log, count: 4),
      (_, _) => _ApplySection(title: 'States', log: log),
    ]);

    expect(find.widgetWithText(FilledButton, 'Apply'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Revert'), findsOneWidget);
    _expectReachable(tester, find.widgetWithText(FilledButton, 'Apply'));

    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    expect(log, <String>['Format apply', 'States apply']);
    log.clear();
    await tester.tap(find.widgetWithText(TextButton, 'Revert'));
    expect(log, <String>['Format revert', 'States revert']);
  });

  testWidgets('the merged bar is enabled when either section is and calls '
      'only the enabled ones', (tester) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) =>
          _ApplySection(title: 'Format', log: log, enabled: false, count: 4),
      (_, _) => _ApplySection(title: 'States', log: log, count: 4),
    ]);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    expect(log, <String>['States apply']);

    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) =>
          _ApplySection(title: 'Format', log: log, enabled: false, count: 4),
      (_, _) =>
          _ApplySection(title: 'States', log: log, enabled: false, count: 4),
    ]);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Revert'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('footers that are not all Apply bars stack in section order', (
    tester,
  ) async {
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => CruxInspectorSection(
        title: 'A',
        footer: const Text('first footer'),
        children: _rows('a', count: 2),
      ),
      (_, _) => _ApplySection(title: 'B', log: _unlogged, count: 2),
    ]);
    expect(find.text('first footer'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Apply'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('first footer')).dy,
      lessThan(
        tester.getTopLeft(find.widgetWithText(FilledButton, 'Apply')).dy,
      ),
    );
  });

  testWidgets('the bar stays live while its section is scrolled out of view', (
    tester,
  ) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Cell', log: log),
      (_, _) =>
          CruxInspectorSection(title: 'Rest', children: _rows('z', count: 60)),
    ]);
    await tester.fling(find.byType(ListView), const Offset(0, -3000), 4000);
    await tester.pumpAndSettle();
    expect(find.text('Cell0'), findsNothing);

    _expectReachable(tester, find.widgetWithText(FilledButton, 'Apply'));
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    expect(log, <String>['Cell apply']);
  });

  testWidgets('a fade shows at the bottom edge only while content continues '
      'below', (tester) async {
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) =>
          CruxInspectorSection(title: 'Short', children: _rows('s', count: 2)),
    ]);
    expect(_fade, findsNothing);

    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => CruxInspectorSection(title: 'Tall', children: _rows('t')),
    ]);
    expect(_fade, findsOneWidget);
    final inspector = tester.getRect(_inspector);
    expect(tester.getRect(_fade).bottom, inspector.bottom);

    await tester.fling(find.byType(ListView), const Offset(0, -3000), 4000);
    await tester.pumpAndSettle();
    expect(_fade, findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, 3000), 4000);
    await tester.pumpAndSettle();
    expect(_fade, findsOneWidget);
  });

  testWidgets('the fade ends above the pinned bar', (tester) async {
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Cell', log: _unlogged),
    ]);
    expect(_fade, findsOneWidget);
    expect(
      tester.getRect(_fade).bottom,
      lessThanOrEqualTo(tester.getRect(_bar).top + 0.5),
    );
  });

  testWidgets('a plain Enter in a field still applies', (tester) async {
    final log = <String>[];
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Cell', log: log),
    ]);
    await tester.tap(find.byKey(const Key('Cell-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(log, <String>['Cell submit']);
  });

  testWidgets('Tab reaches the pinned bar after the body', (tester) async {
    await _mount(tester, <CruxInspectorSectionBuilder<String>>[
      (_, _) => _ApplySection(title: 'Cell', log: _unlogged),
    ]);
    await tester.tap(find.byKey(const Key('Cell-field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      focused.findAncestorWidgetOfExactType<TextButton>() != null ||
          focused.findAncestorWidgetOfExactType<FilledButton>() != null,
      isTrue,
    );
  });
}
