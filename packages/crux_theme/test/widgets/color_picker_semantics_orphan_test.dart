// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour picker is a dialog with sliders in it, which is precisely the
/// shape the desktop accessibility bridge rejects when the sliders are plain
/// `Slider`s. Opening it under semantics must serialize nothing unclaimed.
class _Host extends StatelessWidget {
  const _Host();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open'),
        onPressed: () => showColorPickerDialog(
          context: context,
          initialColor: const Color(0xFF3366CC),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  testWidgets('the colour picker dialog serializes no orphan node', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsWidgets);
    final c = tester.getCenter(find.byType(Slider).first);
    final g = await tester.startGesture(c);
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'colour picker dialog');
  });
}
