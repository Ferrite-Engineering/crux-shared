// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The leaf's own contract: what it reports through its callbacks, that the
// disclosure copy is on screen, and that "off" is never harder to reach than
// "on". Wiring to the consent store and the visibility gate is
// `telemetry_consent_gate_test.dart`.
//
// No locale sweep here — this package carries no ARB files, so per-locale
// rendering is the consuming product's test. What is swept instead is the
// *string set*: a product whose translations run long must not push the switch
// or Continue off screen.

const CruxTelemetryStringsEn _en = CruxTelemetryStringsEn(
  productName: 'TestCrux',
);

late List<bool> decisions;
late int learnMoreTaps;

Widget _wrap({
  bool isPhoneLayout = false,
  CruxTelemetryStrings strings = _en,
  CruxTelemetryConsentMetrics metrics = const CruxTelemetryConsentMetrics(),
  TextDirection? textDirection,
  double textScale = 1,
  bool initialEnabled = true,
}) {
  decisions = <bool>[];
  learnMoreTaps = 0;
  return MaterialApp(
    home: Directionality(
      textDirection: textDirection ?? TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: TelemetryConsentDisclosure(
          strings: strings,
          initialEnabled: initialEnabled,
          metrics: metrics,
          isPhoneLayout: isPhoneLayout,
          onContinue: decisions.add,
          onLearnMore: () => learnMoreTaps++,
        ),
      ),
    ),
  );
}

Finder get _switch => find.byKey(const Key('telemetryConsentSwitch'));
Finder get _continue => find.byKey(const Key('telemetryConsentContinueButton'));
Finder get _learnMore =>
    find.byKey(const Key('telemetryConsentLearnMoreButton'));

void main() {
  testWidgets('reports true when Continue is tapped untouched', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(_continue);
    expect(decisions, [true]);
  });

  testWidgets('reports false after the switch is turned off', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(_switch);
    await tester.pumpAndSettle();
    await tester.tap(_continue);

    expect(decisions, [false]);
  });

  testWidgets('reports the link tap without reporting a decision', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    await tester.tap(_learnMore);
    await tester.pumpAndSettle();

    expect(learnMoreTaps, 1);
    expect(decisions, isEmpty);
  });

  testWidgets('states what is never collected, and routes to the full list', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The prose no longer carries the exhaustive lists, so these two are what
    // is left of the disclosure: the never-collect claim, and a live route to
    // the page that substantiates it. A build that renders the ask without
    // the link is an advertisement.
    expect(find.text(_en.consentBody), findsOneWidget);
    expect(_learnMore, findsOneWidget);
  });

  testWidgets('the ask fits without scrolling at desktop size', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // Two nested `SingleChildScrollView`s now: the body's own bounded
    // viewport (still checked directly, by key, for the reason below), and
    // an outer one that exists purely as a last-resort escape valve for a
    // window too small or a text scale too large for the fixed chrome to
    // fit — see `_content`. Neither should need to move at this size.
    for (final finder in [
      find.byKey(const Key('telemetryConsentBodyScroll')),
      find.byType(SingleChildScrollView).first,
    ]) {
      final state = tester.state<ScrollableState>(
        find.descendant(of: finder, matching: find.byType(Scrollable)).first,
      );
      expect(
        state.position.maxScrollExtent,
        0,
        reason:
            'The whole point of shortening the copy. If this fails, the '
            'prose grew back and the dialog is a wall of text again.',
      );
    }
  });

  testWidgets('names the product supplied by the host', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(find.text('Help make TestCrux better'), findsOneWidget);
  });

  testWidgets('the toggle arrives pre-armed on', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
  });

  testWidgets('the toggle arrives off where the host says opt-in', (
    tester,
  ) async {
    // The consent-first regions. The
    // widget does not decide the region — it is handed the answer — so what
    // is under test here is that it honours it rather than falling back to
    // the default-on position.
    await tester.pumpWidget(_wrap(initialEnabled: false));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(_switch).value, isFalse);
  });

  testWidgets('an untouched opt-in prompt reports false', (tester) async {
    // The consequence that matters: in an opt-in region, a user who reads the
    // dialog and taps Continue without touching anything has *not* consented.
    await tester.pumpWidget(_wrap(initialEnabled: false));
    await tester.pumpAndSettle();

    await tester.tap(_continue);
    await tester.pumpAndSettle();

    expect(decisions, [false]);
  });

  testWidgets('opt-in regions can still turn it on in one tap', (tester) async {
    await tester.pumpWidget(_wrap(initialEnabled: false));
    await tester.pumpAndSettle();

    await tester.tap(_switch);
    await tester.pumpAndSettle();
    await tester.tap(_continue);
    await tester.pumpAndSettle();

    expect(decisions, [true]);
  });

  testWidgets(
    'off is exactly as reachable as on — one visible switch, one button, '
    'both on screen without scrolling',
    (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // No "advanced", no second confirmation step, no hidden affordance:
      // declining is flip-then-Continue, accepting is Continue.
      expect(_switch, findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester.getRect(_switch).overlaps(tester.getRect(_continue)),
        isFalse,
      );
    },
  );

  testWidgets('the system back gesture cannot dismiss it unanswered', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(isPhoneLayout: true));
    await tester.pumpAndSettle();

    final popScope = tester.widget<PopScope<dynamic>>(
      find.byType(PopScope<dynamic>),
    );
    expect(popScope.canPop, isFalse);
    expect(decisions, isEmpty);
  });

  group('presentation', () {
    testWidgets('phone layout renders the full-screen sheet', (tester) async {
      await tester.pumpWidget(_wrap(isPhoneLayout: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentSheet')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentDialog')), findsNothing);
    });

    testWidgets('otherwise renders the dialog card', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentSheet')), findsNothing);
    });
  });

  group('the 44 dp floor', () {
    for (final (name, metrics) in const <(String, CruxTelemetryConsentMetrics)>[
      ('the package default', CruxTelemetryConsentMetrics()),
      // A desktop host whose own metric set drops to 28 dp. The floor exists
      // precisely so this cannot make "off" harder to reach than "on".
      ('a 28 dp desktop host', CruxTelemetryConsentMetrics(touchTarget: 28)),
      ('a touch host', CruxTelemetryConsentMetrics(iconSize: 24)),
    ]) {
      for (final phone in <bool>[true, false]) {
        testWidgets(
          'every control clears 44 dp with $name '
          '(${phone ? 'sheet' : 'dialog'})',
          (tester) async {
            await tester.pumpWidget(
              _wrap(metrics: metrics, isPhoneLayout: phone),
            );
            await tester.pumpAndSettle();

            for (final target in [_switch, _continue, _learnMore]) {
              final size = tester.getSize(target);
              expect(
                size.height,
                greaterThanOrEqualTo(kTelemetryConsentMinTarget),
                reason: '$target is under the 44 dp floor',
              );
              expect(
                size.width,
                greaterThanOrEqualTo(kTelemetryConsentMinTarget),
              );
            }
          },
        );
      }
    }

    test('the metrics bundle floors the target rather than replacing it', () {
      expect(
        const CruxTelemetryConsentMetrics(
          touchTarget: 28,
        ).effectiveTouchTarget,
        kTelemetryConsentMinTarget,
      );
      // A host with a *larger* target keeps it.
      expect(
        const CruxTelemetryConsentMetrics(
          touchTarget: 56,
        ).effectiveTouchTarget,
        56,
      );
    });
  });

  group('string-set and directionality sweep', () {
    testWidgets('renders right-to-left without exceptions', (tester) async {
      await tester.pumpWidget(_wrap(textDirection: TextDirection.rtl));
      await tester.pumpAndSettle();

      expect(find.byType(TelemetryConsentDisclosure), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders long strings without exceptions', (tester) async {
      // Stands in for the locale sweep a product runs over its own ARB: the
      // lists scroll, and the switch and Continue stay pinned below them.
      await tester.pumpWidget(_wrap(strings: const _LongStrings()));
      await tester.pumpAndSettle();

      expect(_switch, findsOneWidget);
      expect(_continue, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at 2x text scale without exceptions', (tester) async {
      await tester.pumpWidget(_wrap(textScale: 2, isPhoneLayout: true));
      await tester.pumpAndSettle();

      expect(_switch, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The regression this guards: `RenderFlex overflowed` from this Column at
  // CI's default runner window size, the same defect found in the EULA
  // dialog it follows on first launch — see
  // `crux_eula/test/src/widgets/eula_acceptance_dialog_test.dart`, which this
  // mirrors.
  group('window sizes', () {
    Future<void> pumpAt(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
      bool isPhoneLayout = false,
    }) async {
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(isPhoneLayout: isPhoneLayout, textScale: textScale),
      );
      await tester.pumpAndSettle();
    }

    for (final (name, size, phone) in <(String, Size, bool)>[
      ('800x600', const Size(800, 600), false),
      ('1024x640', const Size(1024, 640), false),
      ('390x844 phone', const Size(390, 844), true),
    ]) {
      testWidgets('$name: no overflow, switch and Continue reachable', (
        tester,
      ) async {
        await pumpAt(tester, size: size, isPhoneLayout: phone);
        expect(tester.takeException(), isNull);

        for (final finder in [_switch, _continue, _learnMore]) {
          expect(
            finder.hitTestable(),
            findsOneWidget,
            reason: '$finder is not reachable without scrolling at $name',
          );
        }

        await tester.tap(_switch);
        await tester.pumpAndSettle();
        await tester.tap(_continue);
        expect(decisions, [false]);
      });
    }

    for (final (name, size, phone) in <(String, Size, bool)>[
      ('800x600', const Size(800, 600), false),
      ('1024x640', const Size(1024, 640), false),
      ('390x844 phone', const Size(390, 844), true),
    ]) {
      testWidgets('$name at text scale 2.0: no overflow, Continue reachable', (
        tester,
      ) async {
        await pumpAt(tester, size: size, textScale: 2, isPhoneLayout: phone);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(_continue);
        await tester.pumpAndSettle();
        expect(_continue.hitTestable(), findsOneWidget);
        await tester.tap(_continue, warnIfMissed: false);
        expect(
          decisions,
          [true],
          reason: 'Continue was not reachable at $name, scale 2.0',
        );
      });
    }

    // A wide, short window: 1100x320 leaves the card about 224 lp of content
    // height, less than the title, body floor, link, switch and Continue
    // need together, so the outer scroll is what keeps "off" reachable. CI's
    // desktop run hit the EULA dialog's overflow at exactly this size.
    for (final (name, size) in <(String, Size)>[
      ('1100x320', const Size(1100, 320)),
      ('800x400', const Size(800, 400)),
    ]) {
      testWidgets('$name: no overflow, every control reachable by scrolling', (
        tester,
      ) async {
        await pumpAt(tester, size: size);
        expect(tester.takeException(), isNull);

        for (final finder in [_learnMore, _switch, _continue]) {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(
            finder.hitTestable(),
            findsOneWidget,
            reason: '$finder cannot be scrolled to and hit at $name',
          );
        }

        await tester.ensureVisible(_switch);
        await tester.pumpAndSettle();
        await tester.tap(_switch);
        await tester.pumpAndSettle();
        await tester.ensureVisible(_continue);
        await tester.pumpAndSettle();
        await tester.tap(_continue);
        expect(
          decisions,
          [false],
          reason: 'turning it off was not reachable at $name',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// A string set whose scrolling content is long enough to wrap several times —
/// the package's stand-in for a verbose translation.
///
/// The *pinned* strings (title, toggle label, button) are left at a plausible
/// translated length rather than made absurd. That is the design under test:
/// the body scrolls, and the switch and Continue stay on screen behind
/// it. A title long enough to fill the card would overflow, and rightly —
/// no product ships one.
class _LongStrings extends CruxTelemetryStringsEn {
  const _LongStrings();

  static const String _long =
      'This sentence exists to be long enough that it wraps across several '
      'lines at every width this surface supports, which is what a verbose '
      'translation of the same string does in practice.';

  @override
  String get consentBody => '$_long $_long $_long';
}
