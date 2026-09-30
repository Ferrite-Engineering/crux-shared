// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsFlag;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({required this.plain, this.inline = false});
  final bool plain;
  final bool inline;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  double v = 2;
  final FocusNode focus = FocusNode();

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  double? lastStart;
  double? lastEnd;

  Widget _slider() => widget.plain
      ? Slider(
          key: const Key('s'),
          value: v,
          max: 10,
          divisions: 10,
          label: '${v.round()}',
          onChanged: (x) => setState(() => v = x),
        )
      : CruxSlider(
          key: const Key('s'),
          value: v,
          max: 10,
          divisions: 10,
          label: '${v.round()}',
          onChanged: (x) => setState(() => v = x),
          onChangeStart: (x) => lastStart = x,
          onChangeEnd: (x) => lastEnd = x,
          focusNode: focus,
        );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: widget.inline
          ? SizedBox(width: 300, child: _slider())
          : ElevatedButton(
              key: const Key('open'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: Row(
                    children: <Widget>[
                      Expanded(child: _slider()),
                      SizedBox(
                        width: 40,
                        child: Text('${v.round()}', key: const Key('v')),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
    ),
  );
}

Future<void> _openDialog(
  WidgetTester tester, {
  required bool plain,
}) async {
  await tester.pumpWidget(MaterialApp(home: _Host(plain: plain)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  testWidgets('a plain Slider in a dialog orphans a node (the defect)', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await _openDialog(tester, plain: true);
    handle.dispose();
    expect(SemanticsOrphanGuard.instance.orphans, isNotEmpty);
  });

  testWidgets('CruxSlider in a dialog orphans nothing, dragged or not', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await _openDialog(tester, plain: false);
    final c = tester.getCenter(find.byKey(const Key('s')));
    final g = await tester.startGesture(c);
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'CruxSlider in dialog');
    final host = tester.state<_HostState>(find.byType(_Host));
    expect(host.lastStart, isNotNull);
    expect(host.lastEnd, isNotNull);
    expect(host.v, greaterThan(2));
  });

  testWidgets('CruxSlider keeps Slider semantics in a dialog', (tester) async {
    final handle = tester.ensureSemantics();
    await _openDialog(tester, plain: false);
    expect(find.semantics.byFlag(SemanticsFlag.isSlider), findsOneWidget);
    expect(
      find.semantics.byAction(SemanticsAction.increase),
      findsOneWidget,
    );
    expect(
      find.semantics.byAction(SemanticsAction.decrease),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('CruxSlider keeps keyboard operation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _Host(plain: false, inline: true)),
      ),
    );
    await tester.pumpAndSettle();
    final host = tester.state<_HostState>(find.byType(_Host));
    host.focus.requestFocus();
    await tester.pumpAndSettle();
    expect(host.focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(host.v, isNot(2));
  });

  testWidgets('CruxSlider sizes to its slider inside a Row', (
    tester,
  ) async {
    await _openDialog(tester, plain: false);
    final overlay = tester.getSize(find.byType(Overlay).last);
    final slider = tester.getSize(find.byType(Slider));
    expect(overlay, slider);
  });
}
