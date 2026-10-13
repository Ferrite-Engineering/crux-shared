// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart' show PolicySource;
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {String? scope}) async {
  final body = SizedBox(width: 400, child: child);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: scope == null
            ? body
            : CruxPolicyLockScope(message: scope, child: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CruxPolicyLock', () {
    var toggled = 0;
    Widget control() => Switch(value: true, onChanged: (_) => toggled++);

    setUp(() => toggled = 0);

    for (final source in PolicySource.values.where(
      (s) => s != PolicySource.policyLocked,
    )) {
      testWidgets('${source.name} renders the control untouched', (
        tester,
      ) async {
        await _pump(tester, CruxPolicyLock(source: source, child: control()));

        expect(find.byType(CruxPolicyLockNote), findsNothing);
        await tester.tap(find.byType(Switch));
        expect(toggled, 1);
      });
    }

    testWidgets('a locked value shows the note and an inert control', (
      tester,
    ) async {
      await _pump(
        tester,
        CruxPolicyLock(source: PolicySource.policyLocked, child: control()),
      );

      expect(find.text(kCruxPolicyLockNoteEn), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // Shown, not hidden: the organization's value stays readable.
      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.byType(Switch), warnIfMissed: false);
      expect(toggled, 0, reason: 'a locked control decides nothing');

      expect(
        tester
            .widgetList<ExcludeFocus>(
              find.ancestor(
                of: find.byType(Switch),
                matching: find.byType(ExcludeFocus),
              ),
            )
            .any((w) => w.excluding),
        isTrue,
        reason: 'the locked control is not a Tab stop',
      );
    });

    testWidgets('the sentence comes from the scope when one is mounted', (
      tester,
    ) async {
      await _pump(
        tester,
        CruxPolicyLock(source: PolicySource.policyLocked, child: control()),
        scope: 'Durch die Richtlinie festgelegt.',
      );

      expect(find.text('Durch die Richtlinie festgelegt.'), findsOneWidget);
      expect(find.text(kCruxPolicyLockNoteEn), findsNothing);
    });

    testWidgets('a detail line goes under the sentence', (tester) async {
      await _pump(
        tester,
        const CruxPolicyLock(
          source: PolicySource.policyLocked,
          detail: 'These packs outrank your own symbols.',
        ),
      );

      expect(
        find.text(
          '$kCruxPolicyLockNoteEn\nThese packs outrank your own symbols.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the note goes above or below, as asked', (tester) async {
      Future<(double, double)> positions(
        CruxPolicyLockNotePlacement placement,
      ) async {
        await _pump(
          tester,
          CruxPolicyLock(
            source: PolicySource.policyLocked,
            placement: placement,
            child: control(),
          ),
        );
        return (
          tester.getTopLeft(find.byType(CruxPolicyLockNote)).dy,
          tester.getTopLeft(find.byType(Switch)).dy,
        );
      }

      final (noteAbove, switchBelow) = await positions(
        CruxPolicyLockNotePlacement.above,
      );
      expect(noteAbove, lessThan(switchBelow));
      final (noteBelow, switchAbove) = await positions(
        CruxPolicyLockNotePlacement.below,
      );
      expect(noteBelow, greaterThan(switchAbove));
    });

    testWidgets('no source but a lock renders nothing without a child', (
      tester,
    ) async {
      await _pump(
        tester,
        const CruxPolicyLock(source: PolicySource.policyDefault),
      );
      expect(find.byType(CruxPolicyLockNote), findsNothing);
    });
  });

  test('the English sentence carries no em dash', () {
    expect(kCruxPolicyLockNoteEn, isNot(contains('—')));
  });
}
