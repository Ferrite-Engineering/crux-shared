// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A modal surface mounted over the app without a route, the way a licence
// agreement or consent disclosure sits above a product's Navigator. The host
// below mirrors a product's shape: a control outside the gate (the product's
// menu bar sits there), the gate, and an app behind it with a button that
// takes focus on launch.
//
// MUTATION: dropping the ExcludeFocus from CruxModalGate turns "app code
// cannot pull focus behind the surface" red; dropping the dialog's autofocus
// turns "focus opens inside the dialog" red; dropping the FocusScope from
// CruxModalSurface turns the Tab walk red, because Tab then reaches the
// control outside the gate.

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the app behind the gate did.
final List<String> _pressed = <String>[];

/// The app's own launch-time focus, which the gate must take away.
late FocusNode _behindFocus;

Widget _dialog({required VoidCallback onDone, String label = 'Agreement'}) {
  return Stack(
    children: [
      const ModalBarrier(dismissible: false, color: Colors.black54),
      CruxModalSurface(
        label: label,
        child: Center(
          child: Card(
            semanticContainer: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => _pressed.add('$label: read'),
                    child: const Text('Read it online'),
                  ),
                  FilledButton(onPressed: onDone, child: const Text('Done')),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _Host extends StatefulWidget {
  const _Host({this.outer = true, this.inner = false});

  final bool outer;
  final bool inner;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool _outer = widget.outer;
  late bool _inner = widget.inner;

  /// Raises the outer gate over an app that is already in use.
  void raiseOuter() => setState(() => _outer = true);

  @override
  Widget build(BuildContext context) {
    Widget app = Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            focusNode: _behindFocus,
            autofocus: true,
            onPressed: () => _pressed.add('behind: open'),
            child: const Text('Open design'),
          ),
          ElevatedButton(
            onPressed: () => _pressed.add('behind: save'),
            child: const Text('Save design'),
          ),
          const _Counter(),
        ],
      ),
    );
    app = CruxModalGate(
      modal: _inner
          ? _dialog(
              label: 'Consent',
              onDone: () => setState(() => _inner = false),
            )
          : null,
      child: app,
    );
    return MaterialApp(
      home: Column(
        children: [
          TextButton(
            onPressed: () => _pressed.add('menu'),
            child: const Text('Menu'),
          ),
          Expanded(
            // A host that binds Escape to something of its own: the surface
            // must consume the key rather than let it reach this.
            child: Actions(
              actions: <Type, Action<Intent>>{
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    _pressed.add('dismissed');
                    return null;
                  },
                ),
              },
              child: CruxModalGate(
                modal: _outer
                    ? _dialog(onDone: () => setState(() => _outer = false))
                    : null,
                child: app,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Holds state the gate must not discard when it opens or closes.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _count++),
    child: Text('Clicked $_count'),
  );
}

Future<void> _pumpHost(WidgetTester tester, _Host host) async {
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _pressed.clear();
    _behindFocus = FocusNode(debugLabel: 'behind');
  });
  tearDown(() => _behindFocus.dispose());

  group('CruxModalGate with a CruxModalSurface', () {
    testWidgets('focus opens inside the dialog, which is announced by name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHost(tester, const _Host());

      expectFocusAnnounced(tester, named: 'Read it online');
      expect(
        describeFocus(tester).line,
        '[Agreement grouping] Read it online button',
      );
      expect(
        tester.getSemantics(find.byType(CruxModalSurface)),
        matchesSemantics(
          label: 'Agreement',
          scopesRoute: true,
          namesRoute: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('Tab cycles through the dialog and never leaves it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHost(tester, const _Host());

      for (final walk in [
        await walkFocus(tester),
        await walkFocus(tester, reverse: true),
      ]) {
        expectCleanFocusWalk(walk);
        expect(walk.stops.map((s) => s.line).toSet(), <String>{
          'Read it online button',
          'Done button',
        });
        expect(walk.transcript, isNot(contains('design')));
        expect(walk.transcript, isNot(contains('Menu')));
      }
      handle.dispose();
    });

    testWidgets('app code cannot pull focus behind the surface', (
      tester,
    ) async {
      await _pumpHost(tester, const _Host());

      // A canvas or palette that grabs focus once it has loaded, after the
      // gate is already up.
      _behindFocus.requestFocus();
      await tester.pump();

      expect(_behindFocus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(_pressed, isNot(contains('behind: open')));
    });

    testWidgets('Escape does not dismiss it', (tester) async {
      await _pumpHost(tester, const _Host());

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(_pressed, isNot(contains('dismissed')));
      expect(find.byType(CruxModalSurface), findsOneWidget);
    });

    testWidgets('closing it puts focus on the first control behind it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHost(tester, const _Host());

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(CruxModalSurface), findsNothing);
      expectFocusAnnounced(tester, named: 'Open design');
      // And the app is reachable again.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_pressed, contains('behind: open'));
      handle.dispose();
    });

    testWidgets('a gate nested behind it takes focus when it closes', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHost(tester, const _Host(inner: true));

      expect(describeFocus(tester).line, contains('[Agreement grouping]'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        describeFocus(tester).line,
        '[Consent grouping] Read it online button',
      );
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.transcript, isNot(contains('design')));
      handle.dispose();
    });

    testWidgets('the app keeps its state across the gate', (tester) async {
      await tester.pumpWidget(const _Host(outer: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clicked 0'));
      await tester.pump();
      expect(find.text('Clicked 1'), findsOneWidget);

      tester.state<_HostState>(find.byType(_Host)).raiseOuter();
      await tester.pumpAndSettle();
      expect(find.text('Clicked 1'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Clicked 1'), findsOneWidget);
    });
  });

  group('CruxScrollRegion', () {
    Widget region({
      bool exclude = false,
      String label = 'Agreement text',
      Key key = const Key('region'),
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 200,
                child: CruxScrollRegion(
                  key: key,
                  semanticLabel: label,
                  excludeContentSemantics: exclude,
                  autofocus: true,
                  builder: (context, controller) => SingleChildScrollView(
                    key: const Key('scroll'),
                    controller: controller,
                    child: Column(
                      children: [
                        for (var i = 0; i < 40; i++)
                          SizedBox(height: 30, child: Text('Paragraph $i')),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(onPressed: () {}, child: const Text('Accept')),
            ],
          ),
        ),
      );
    }

    double offset(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('scroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    testWidgets('is a named Tab stop', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(region());
      await tester.pumpAndSettle();

      expect(describeFocus(tester).line, 'Agreement text grouping');
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.stops.map((s) => s.line), <String>[
        'Accept button',
        'Agreement text grouping',
      ]);
      handle.dispose();
    });

    testWidgets('scrolls with the arrow, Page, Home and End keys', (
      tester,
    ) async {
      await tester.pumpWidget(region());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(offset(tester), 50);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(offset(tester), 50 + 200 * .8);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(offset(tester), 160);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(offset(tester), 40 * 30 - 200);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(offset(tester), 40 * 30 - 200 - 160);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(offset(tester), 0);

      // Clamped at the start rather than overscrolling.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(offset(tester), 0);
    });

    testWidgets('keys do nothing to it once focus has moved on', (
      tester,
    ) async {
      await tester.pumpWidget(region());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(offset(tester), 0);
    });

    testWidgets('draws an outline only while focused', (tester) async {
      await tester.pumpWidget(region());
      await tester.pumpAndSettle();

      Color outline() {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byKey(const Key('region')),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return ((box.decoration as BoxDecoration).border! as Border).top.color;
      }

      final primary = Theme.of(
        tester.element(find.byKey(const Key('region'))),
      ).colorScheme.primary;
      expect(outline(), primary);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(outline(), Colors.transparent);
    });

    testWidgets('can carry its content as its name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        region(exclude: true, label: 'We count launches, not content.'),
      );
      await tester.pumpAndSettle();

      expect(
        describeFocus(tester).line,
        'We count launches, not content. text',
      );
      handle.dispose();
    });
  });
}
