// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SliderBox extends StatefulWidget {
  const _SliderBox();
  @override
  State<_SliderBox> createState() => _SliderBoxState();
}

class _SliderBoxState extends State<_SliderBox> {
  double v = 0.3;
  @override
  Widget build(BuildContext context) =>
      Slider(value: v, onChanged: (x) => setState(() => v = x));
}

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(content: child),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  testWidgets('records updates and reports none for a plain screen', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('hello'))),
      ),
    );
    await tester.pumpAndSettle();
    handle.dispose();
    expect(SemanticsOrphanGuard.instance.updates, greaterThan(0));
    expect(SemanticsOrphanGuard.instance.orphans, isEmpty);
    SemanticsOrphanGuard.instance.check();
  });

  testWidgets('detects the Slider-in-dialog orphan the bridge rejects', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: _DialogHost(child: _SliderBox())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    handle.dispose();
    final orphans = SemanticsOrphanGuard.instance.orphans;
    expect(orphans, isNotEmpty);
    expect(orphans.first.node.traversalParent, -1);
    expect(orphans.first.node.children, isEmpty);
    expect(orphans.first.reason, contains('not claimed'));
    expect(
      () => SemanticsOrphanGuard.instance.check(context: 'dialog'),
      throwsA(isA<TestFailure>()),
    );
    expect(
      SemanticsOrphanGuard.instance.describe(orphans.first.node.id),
      contains('traversalParent=-1'),
    );
  });

  testWidgets('a settled dialog opened before semantics turn on is clean', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: _DialogHost(child: _SliderBox())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'snapshot');
  });
}
