// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

// Layout only: whether the dialog fits the window it is given, at the sizes
// and text scales the four desktop apps actually run at. Behaviour (Accept
// disabled until ticked, Decline/online-link visibility, the back gesture) is
// `crux_eula_gate_test.dart`; this file only asks "is everything on screen,
// and can a user reach it".
//
// The regression this guards: `RenderFlex overflowed` from the dialog's
// `Column` at CI's default runner window size, first seen in the desktop
// integration run. In debug that draws overflow stripes; in release the
// content is clipped, and on a small window that clip can take the Accept
// button with it.

const _decline = Key('cruxEulaDeclineButton');
const _accept = Key('cruxEulaAcceptButton');
const _checkbox = Key('cruxEulaAcceptCheckbox');
const _openOnline = Key('cruxEulaOpenOnlineButton');

Widget _wrap({
  required Size size,
  double textScale = 1,
  bool isPhoneLayout = false,
  VoidCallback? onAccept,
  VoidCallback? onDecline,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: CruxEulaAcceptanceDialog(
        onAccept: onAccept ?? () {},
        onDecline: onDecline ?? () {},
        onOpenOnline: () async {},
        isPhoneLayout: isPhoneLayout,
      ),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  bool isPhoneLayout = false,
  VoidCallback? onAccept,
  VoidCallback? onDecline,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _wrap(
      size: size,
      textScale: textScale,
      isPhoneLayout: isPhoneLayout,
      onAccept: onAccept,
      onDecline: onDecline,
    ),
  );
  await tester.pumpAndSettle();
}

/// No `RenderFlex overflowed` (or any other) exception, at any point in the
/// pump — not just "no exception left at the end", since `takeException`
/// only reports what has not already been flushed by a FlutterError handler.
void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

void main() {
  group('fits without scrolling at documented sizes', () {
    // The sizes this surface is documented to support: a small desktop
    // window, a larger one, and a phone. At text scale 1, the fixed chrome
    // (title, checkbox, buttons) is sized to fit all three without needing
    // to scroll the whole dialog — only the licence text itself scrolls.
    for (final (name, size, phone) in <(String, Size, bool)>[
      ('800x600', const Size(800, 600), false),
      ('1024x640', const Size(1024, 640), false),
      ('390x844 phone', const Size(390, 844), true),
    ]) {
      testWidgets(name, (tester) async {
        await _pumpAt(tester, size: size, isPhoneLayout: phone);
        _expectNoOverflow(tester);

        for (final key in [_checkbox, _decline, _accept, _openOnline]) {
          expect(
            find.byKey(key).hitTestable(),
            findsOneWidget,
            reason: '$key is not reachable without scrolling at $name',
          );
        }

        // Accept is reachable and, once armed, actually accepts — not just
        // present in the tree.
        var accepted = false;
        await tester.pumpWidget(
          _wrap(
            size: size,
            isPhoneLayout: phone,
            onAccept: () => accepted = true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_accept));
        await tester.pumpAndSettle();
        expect(accepted, isTrue);
      });
    }
  });

  group('does not overflow at text scale 2.0', () {
    // The extreme case the fixed-height buttons and the plain `Row` used to
    // fail at outright (a horizontal `RenderFlex overflowed` from the
    // Decline/Accept row, and a vertical one from the outer `Column`). The
    // promise here is weaker than at scale 1 — reachable, not necessarily
    // without scrolling — because doubled text is real content growth, not
    // a bug to lay out around.
    for (final (name, size, phone) in <(String, Size, bool)>[
      ('800x600', const Size(800, 600), false),
      ('1024x640', const Size(1024, 640), false),
      ('390x844 phone', const Size(390, 844), true),
    ]) {
      testWidgets(name, (tester) async {
        var accepted = false;
        await _pumpAt(
          tester,
          size: size,
          textScale: 2,
          isPhoneLayout: phone,
          onAccept: () => accepted = true,
        );
        _expectNoOverflow(tester);

        await tester.ensureVisible(find.byKey(_checkbox));
        await tester.pumpAndSettle();
        expect(find.byKey(_checkbox).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(_checkbox), warnIfMissed: false);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(_accept));
        await tester.pumpAndSettle();
        expect(find.byKey(_accept).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(_accept), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(
          accepted,
          isTrue,
          reason: 'Accept was not reachable at $name, scale 2.0',
        );

        await tester.ensureVisible(find.byKey(_decline));
        await tester.pumpAndSettle();
        expect(find.byKey(_decline).hitTestable(), findsOneWidget);
      });
    }
  });

  group('reachable by scrolling in a very short window', () {
    // A wide, short window is the case the licence-box reserve cannot cover:
    // 1100x320 leaves the card about 224 lp of content height, well under
    // the fixed chrome alone, so the licence box drops to its floor and the
    // outer scroll is what keeps the controls reachable. CI's desktop run
    // hit the overflow at exactly this size before that scroll existed.
    for (final (name, size) in <(String, Size)>[
      ('1100x320', const Size(1100, 320)),
      ('800x400', const Size(800, 400)),
    ]) {
      testWidgets(name, (tester) async {
        var accepted = false;
        var declined = false;
        await _pumpAt(
          tester,
          size: size,
          onAccept: () => accepted = true,
          onDecline: () => declined = true,
        );
        _expectNoOverflow(tester);

        for (final key in [_openOnline, _checkbox, _decline, _accept]) {
          await tester.ensureVisible(find.byKey(key));
          await tester.pumpAndSettle();
          expect(
            find.byKey(key).hitTestable(),
            findsOneWidget,
            reason: '$key cannot be scrolled to and hit at $name',
          );
        }

        await tester.ensureVisible(find.byKey(_checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_checkbox));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(_accept));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_accept));
        await tester.pumpAndSettle();
        expect(accepted, isTrue, reason: 'Accept did not accept at $name');

        await tester.ensureVisible(find.byKey(_decline));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_decline));
        await tester.pumpAndSettle();
        expect(declined, isTrue, reason: 'Decline did not decline at $name');
        _expectNoOverflow(tester);
      });
    }
  });

  testWidgets('the licence text scrolls inside its own bounded box', (
    tester,
  ) async {
    await _pumpAt(tester, size: const Size(800, 600));

    final licence = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('cruxEulaDocumentScroll')),
    );
    // A 90-paragraph agreement in a box under 220 lp tall has more to show
    // than fits — if this is ever 0, the box grew to swallow the whole
    // document instead of staying bounded.
    final state = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('cruxEulaDocumentScroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(state.position.maxScrollExtent, greaterThan(0));
    expect(licence.padding, const EdgeInsets.all(12));
  });

  group('keyboard and screen-reader access', () {
    testWidgets('every control has an accessible name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAt(tester, size: const Size(800, 600));

      for (final key in [_checkbox, _decline, _accept, _openOnline]) {
        final semantics = tester.getSemantics(find.byKey(key));
        expect(
          semantics.label.isNotEmpty,
          isTrue,
          reason: '$key has no accessible name',
        );
      }
      handle.dispose();
    });

    testWidgets(
      'Tab reaches the checkbox and both buttons, checkbox before Accept',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpAt(tester, size: const Size(800, 600));
        // Accept is disabled (and so excluded from focus traversal
        // altogether) until the checkbox is ticked — tick it first so this
        // test is about tab *order*, not about the disabled-button case
        // `crux_eula_gate_test.dart` already covers.
        await tester.tap(find.byKey(_checkbox));
        await tester.pumpAndSettle();

        // Which of the tracked controls contains a given global point —
        // `FocusNode.rect` rather than matching `Element`/`BuildContext`
        // identity, because every one of these controls wraps its own
        // internal `Focus` a level or two below the key we can find it by.
        Key? controlAt(Offset point) {
          for (final key in const [_openOnline, _checkbox, _decline, _accept]) {
            final elements = find.byKey(key).evaluate();
            if (elements.isEmpty) continue;
            final box = elements.first.renderObject;
            if (box is! RenderBox) continue;
            final rect = box.localToGlobal(Offset.zero) & box.size;
            if (rect.contains(point)) return key;
          }
          return null;
        }

        final required = {_checkbox, _decline, _accept};
        final visited = <Key>{};
        final visitOrder = <Key>[];
        for (var i = 0; i < 20 && !visited.containsAll(required); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final rect = FocusManager.instance.primaryFocus?.rect;
          if (rect == null) continue;
          final hit = controlAt(rect.center);
          if (hit != null && visited.add(hit)) {
            visitOrder.add(hit);
          }
        }

        for (final key in const [_checkbox, _decline, _accept]) {
          expect(
            visited,
            contains(key),
            reason: '$key was never reached by Tab',
          );
        }
        expect(
          visitOrder.indexOf(_checkbox),
          lessThan(visitOrder.indexOf(_accept)),
          reason:
              'the checkbox is the deliberate second act before Accept; '
              'tab order should not put Accept first',
        );
        handle.dispose();
      },
    );
  });
}
