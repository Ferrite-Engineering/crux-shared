// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required void Function(Offset) onContextMenu,
  required TargetPlatform platform,
  bool isTouchLayout = false,
}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Scaffold(
      body: Center(
        child: PlatformContextMenu(
          onContextMenu: onContextMenu,
          isTouchLayout: isTouchLayout,
          child: const SizedBox(key: Key('target'), width: 200, height: 200),
        ),
      ),
    ),
  );
}

void main() {
  group('PlatformContextMenu', () {
    testWidgets('right-click fires on a desktop platform', (tester) async {
      Offset? received;
      await tester.pumpWidget(
        _host(
          onContextMenu: (p) => received = p,
          platform: TargetPlatform.macOS,
        ),
      );

      final target = tester.getCenter(find.byKey(const Key('target')));
      final gesture = await tester.startGesture(
        target,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(received, isNotNull);
      expect(received, target);
    });

    testWidgets('long-press does NOT fire in a pointer-first desktop layout', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _host(
          onContextMenu: (_) => fired = true,
          platform: TargetPlatform.macOS,
        ),
      );

      await tester.longPress(find.byKey(const Key('target')));
      await tester.pump();

      expect(
        fired,
        isFalse,
        reason: 'pointer devices must not pay the 500 ms long-press delay',
      );
    });

    testWidgets('long-press fires in a touch-first layout on desktop OS', (
      tester,
    ) async {
      Offset? received;
      await tester.pumpWidget(
        _host(
          onContextMenu: (p) => received = p,
          platform: TargetPlatform.windows,
          isTouchLayout: true,
        ),
      );

      await tester.longPress(find.byKey(const Key('target')));
      await tester.pump();

      expect(received, isNotNull);
    });

    testWidgets('long-press fires on a mobile platform regardless of layout', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _host(
          onContextMenu: (_) => fired = true,
          platform: TargetPlatform.iOS,
        ),
      );

      await tester.longPress(find.byKey(const Key('target')));
      await tester.pump();

      expect(
        fired,
        isTrue,
        reason:
            'a desktop-sized tablet layout still has no right-click '
            'without an external mouse',
      );
    });

    testWidgets('right-click still works in a touch-first layout', (
      tester,
    ) async {
      var fired = false;
      await tester.pumpWidget(
        _host(
          onContextMenu: (_) => fired = true,
          platform: TargetPlatform.android,
          isTouchLayout: true,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('target'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(fired, isTrue);
    });
  });

  group('long-press belongs to touch and pen', () {
    // Over a remote display the button-up of a plain click can arrive after
    // the long-press timeout; the click must stay a click.
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      for (final kind in [
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      ]) {
        testWidgets('a ${kind.name} held past the timeout opens no menu '
            'on $platform in a touch layout', (tester) async {
          var fired = false;
          await tester.pumpWidget(
            _host(
              onContextMenu: (_) => fired = true,
              platform: platform,
              isTouchLayout: true,
            ),
          );

          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(const Key('target'))),
            kind: kind,
          );
          await tester.pump(const Duration(seconds: 2));
          await gesture.up();
          await tester.pump();

          expect(fired, isFalse);
        });
      }
    }

    for (final kind in [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      testWidgets('a ${kind.name} long press opens the menu', (tester) async {
        Offset? received;
        await tester.pumpWidget(
          _host(
            onContextMenu: (p) => received = p,
            platform: TargetPlatform.android,
          ),
        );

        final target = tester.getCenter(find.byKey(const Key('target')));
        final gesture = await tester.startGesture(target, kind: kind);
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pump();

        expect(received, target);
      });
    }

    testWidgets('right-click held past the timeout still opens the menu', (
      tester,
    ) async {
      var fired = 0;
      await tester.pumpWidget(
        _host(
          onContextMenu: (_) => fired++,
          platform: TargetPlatform.android,
          isTouchLayout: true,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('target'))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pump();

      expect(fired, 1);
    });
  });

  group('semantics of the content', () {
    // A value row with a control beside it, the shape of a value cell with a
    // lock: the value copies on tap, the lock says why something is withheld.
    // The wrapper must not fold the lock into the row's node, on a touch
    // layout or a pointer one.
    Widget row({required VoidCallback? onLock, required VoidCallback onValue}) {
      return SizedBox(
        width: 240,
        height: 24,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onValue,
                child: const Text('a'),
              ),
            ),
            Semantics(
              button: true,
              label: 'Locked: needs Pro.',
              onTap: onLock,
              excludeSemantics: true,
              child: InkWell(
                onTap: onLock ?? () {},
                child: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
      );
    }

    Future<void> pump(
      WidgetTester tester, {
      required TargetPlatform platform,
      required bool isTouchLayout,
      required Widget child,
      void Function(Offset)? onContextMenu,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: PlatformContextMenu(
                onContextMenu: onContextMenu ?? (_) {},
                isTouchLayout: isTouchLayout,
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    const layouts = <(TargetPlatform, bool)>[
      (TargetPlatform.android, false),
      (TargetPlatform.iOS, false),
      (TargetPlatform.windows, true),
      (TargetPlatform.macOS, false),
      (TargetPlatform.linux, false),
    ];

    for (final (platform, touch) in layouts) {
      final name = '${platform.name}${touch ? ', touch layout' : ''}';

      testWidgets('a control with its own tap stays its own node: $name', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        var locks = 0;
        var values = 0;
        await pump(
          tester,
          platform: platform,
          isTouchLayout: touch,
          child: row(onLock: () => locks++, onValue: () => values++),
        );

        final lock = find.semantics.byLabel('Locked: needs Pro.');
        expect(lock, findsOne);
        expect(
          lock.evaluate().single,
          isSemantics(
            label: 'Locked: needs Pro.',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(find.semantics.byLabel('a'), findsOne);

        tester.semantics.tap(lock);
        expect((locks, values), (1, 0));
        tester.semantics.tap(find.semantics.byLabel('a'));
        expect((locks, values), (1, 1));
        handle.dispose();
      });

      testWidgets('a control without a tap action keeps its own label: $name', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(
          tester,
          platform: platform,
          isTouchLayout: touch,
          child: row(onLock: null, onValue: () {}),
        );

        // Exact matches: neither label is folded into the other's node.
        expect(find.semantics.byLabel('Locked: needs Pro.'), findsOne);
        expect(find.semantics.byLabel('a'), findsOne);
        expect(
          find.semantics.byLabel(RegExp('a\nLocked|Locked.*\na')),
          findsNothing,
        );
        handle.dispose();
      });
    }

    testWidgets('a screen reader long press opens the menu at the centre on '
        'a touch layout', (tester) async {
      final handle = tester.ensureSemantics();
      Offset? received;
      await pump(
        tester,
        platform: TargetPlatform.android,
        isTouchLayout: true,
        onContextMenu: (p) => received = p,
        child: const SizedBox(width: 200, height: 100, child: Text('row')),
      );

      tester.semantics.longPress(
        find.semantics.byAction(SemanticsAction.longPress),
      );
      expect(received, const Offset(100, 50));
      handle.dispose();
    });

    testWidgets('a pointer-first desktop layout offers no long press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        platform: TargetPlatform.macOS,
        isTouchLayout: false,
        child: const SizedBox(width: 200, height: 100, child: Text('row')),
      );

      expect(
        find.semantics.byAction(SemanticsAction.longPress),
        findsNothing,
      );
      handle.dispose();
    });
  });

  group('shouldEnableLongPressContextMenu', () {
    test('touch-first layouts always enable long-press', () {
      for (final platform in TargetPlatform.values) {
        expect(
          shouldEnableLongPressContextMenu(
            isTouchLayout: true,
            platform: platform,
          ),
          isTrue,
          reason: '$platform',
        );
      }
    });

    test('pointer-first layouts gate on the host platform', () {
      const desktop = [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ];
      for (final platform in TargetPlatform.values) {
        expect(
          shouldEnableLongPressContextMenu(
            isTouchLayout: false,
            platform: platform,
          ),
          !desktop.contains(platform),
          reason: '$platform',
        );
      }
    });
  });
}
