// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desktop accessibility bridge rejects an update that serializes a node
/// nobody claims, and a plain `Slider` inside a dialog does exactly that. The
/// slider tile is the one grouped-row widget that hosts a slider, and the
/// settings shell is a dialog, so this is the surface where the defect would
/// land for every product at once.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  double v = 4;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            child: SizedBox(
              width: 420,
              child: CruxSettingsSliderTile(
                title: 'Grid density',
                description: 'How many rows fit on screen.',
                min: 1,
                max: 10,
                divisions: 9,
                value: v,
                label: '${v.round()}',
                valueText: '${v.round()} rows',
                onChanged: (x) => setState(() => v = x),
              ),
            ),
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  testWidgets('a slider tile inside a dialog serializes no orphan node', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: _Host()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    final c = tester.getCenter(find.byType(Slider));
    final g = await tester.startGesture(c);
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'slider tile in dialog');
    expect(SemanticsOrphanGuard.instance.updates, greaterThan(1));
  });
}
