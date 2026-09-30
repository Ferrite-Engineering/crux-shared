// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Action { zoomIn, zoomOut, panLeft, closeFile, closeTab }

void main() {
  group('activatorSignature', () {
    test('equal chords share a signature; different ones differ', () {
      expect(
        activatorSignature(
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
        ),
        activatorSignature(
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
        ),
      );
      expect(
        activatorSignature(
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
        ),
        isNot(
          activatorSignature(
            const SingleActivator(LogicalKeyboardKey.keyP, control: true),
          ),
        ),
      );
    });
  });

  group('findShortcutConflicts', () {
    test('no conflicts when every chord is unique', () {
      expect(
        findShortcutConflicts({
          _Action.zoomIn: const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
          ),
          _Action.zoomOut: const SingleActivator(
            LogicalKeyboardKey.keyX,
            meta: true,
          ),
        }),
        isEmpty,
      );
    });

    test('reports both members of an accidental collision', () {
      const shared = SingleActivator(LogicalKeyboardKey.keyZ, meta: true);
      final conflicts = findShortcutConflicts({
        _Action.zoomIn: shared,
        _Action.panLeft: shared,
      });
      expect(conflicts[_Action.zoomIn], [_Action.panLeft]);
      expect(conflicts[_Action.panLeft], [_Action.zoomIn]);
    });

    test('honors a caller-supplied intentional-shadow allow-list', () {
      const shared = SingleActivator(LogicalKeyboardKey.keyW, meta: true);
      final conflicts = findShortcutConflicts(
        {_Action.closeFile: shared, _Action.closeTab: shared},
        intentionalShadows: const {
          {_Action.closeFile, _Action.closeTab},
        },
      );
      expect(conflicts, isEmpty);
    });

    test('a third action joining a shadowed chord is still flagged', () {
      const shared = SingleActivator(LogicalKeyboardKey.keyW, meta: true);
      final conflicts = findShortcutConflicts(
        {
          _Action.closeFile: shared,
          _Action.closeTab: shared,
          _Action.zoomIn: shared,
        },
        intentionalShadows: const {
          {_Action.closeFile, _Action.closeTab},
        },
      );
      expect(
        conflicts.keys,
        containsAll([_Action.closeFile, _Action.closeTab, _Action.zoomIn]),
      );
    });
  });

  group('resolveShortcutConflicts', () {
    const z = SingleActivator(LogicalKeyboardKey.keyZ, meta: true);
    const x = SingleActivator(LogicalKeyboardKey.keyX, meta: true);
    const w = SingleActivator(LogicalKeyboardKey.keyW, meta: true);

    test('no collisions: effective == bindings, no conflicts, count 0', () {
      final r = resolveShortcutConflicts(
        {_Action.zoomIn: z, _Action.zoomOut: x},
        {_Action.zoomIn: z, _Action.zoomOut: x},
      );
      expect(r.effectiveBindings, {_Action.zoomIn: z, _Action.zoomOut: x});
      expect(r.conflicts, isEmpty);
      expect(r.conflictChordCount, 0);
    });

    test('a customized interloper wins the chord over the default owner', () {
      // zoomIn holds Z by default; the user remaps panLeft (default X) onto Z.
      final r = resolveShortcutConflicts(
        {_Action.zoomIn: z, _Action.panLeft: z},
        {_Action.zoomIn: z, _Action.panLeft: x},
      );
      // Runtime: only panLeft keeps Z; the owner zoomIn is dropped.
      expect(r.effectiveBindings, {_Action.panLeft: z});
      // Both rows know panLeft is the winner; count is one chord.
      expect(r.conflicts[_Action.panLeft]!.winner, _Action.panLeft);
      expect(r.conflicts[_Action.zoomIn]!.winner, _Action.panLeft);
      expect(r.conflicts[_Action.zoomIn]!.others, [_Action.panLeft]);
      expect(r.conflictChordCount, 1);
    });

    test('precedence is independent of enum/iteration order', () {
      // Same scenario as above but with panLeft listed first: winner unchanged.
      final r = resolveShortcutConflicts(
        {_Action.panLeft: z, _Action.zoomIn: z},
        {_Action.panLeft: x, _Action.zoomIn: z},
        order: _Action.values,
      );
      expect(r.effectiveBindings, {_Action.panLeft: z});
      expect(r.conflicts[_Action.zoomIn]!.winner, _Action.panLeft);
    });

    test(
      'intentional shadow: resolved at runtime, not surfaced as a warning',
      () {
        final r = resolveShortcutConflicts(
          {_Action.closeFile: w, _Action.closeTab: w},
          {_Action.closeFile: w, _Action.closeTab: w},
          order: _Action.values, // closeFile before closeTab
          intentionalShadows: const {
            {_Action.closeFile, _Action.closeTab},
          },
        );
        // Later-declared closeTab wins the chord (preserves prior behavior);
        // closeFile is dropped from the runtime map.
        expect(r.effectiveBindings, {_Action.closeTab: w});
        // No warning for the by-design shadow.
        expect(r.conflicts, isEmpty);
        expect(r.conflictChordCount, 0);
      },
    );

    test(
      'all-default tie (no shadow) breaks by later declaration, both warned',
      () {
        final r = resolveShortcutConflicts(
          {_Action.zoomIn: z, _Action.zoomOut: z},
          {_Action.zoomIn: z, _Action.zoomOut: z},
          order: _Action.values, // zoomIn before zoomOut
        );
        expect(r.effectiveBindings, {_Action.zoomOut: z});
        expect(r.conflicts[_Action.zoomIn]!.winner, _Action.zoomOut);
        expect(r.conflicts[_Action.zoomOut]!.winner, _Action.zoomOut);
        expect(r.conflictChordCount, 1);
      },
    );

    test('effectiveBindings never maps two actions to the same chord', () {
      final r = resolveShortcutConflicts(
        {_Action.zoomIn: z, _Action.zoomOut: z, _Action.panLeft: z},
        {_Action.zoomIn: z, _Action.zoomOut: z, _Action.panLeft: x},
        order: _Action.values,
      );
      final signatures = r.effectiveBindings.values
          .map(activatorSignature)
          .toList();
      expect(signatures.length, signatures.toSet().length);
      // The customized panLeft wins over the two default owners.
      expect(r.effectiveBindings, {_Action.panLeft: z});
    });
  });
}
