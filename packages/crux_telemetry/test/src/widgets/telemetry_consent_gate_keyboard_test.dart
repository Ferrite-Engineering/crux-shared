// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The consent disclosure on a first launch, as a keyboard and a screen reader
// meet it.
//
// Before, it was stacked over the app with nothing but a barrier: focus
// stayed on the app behind it, Tab walked controls the user could not see
// (each one silent, because the barrier blocks their semantics), nothing
// ever landed inside the disclosure, and Enter could press a hidden button.
//
// The transcript in goldens/telemetry_consent_gate.txt is what NVDA reads,
// one Tab at a time; `flutter test --update-goldens` rewrites it, and the
// diff is the review.
//
// MUTATION: dropping the ExcludeFocus from CruxModalGate turns "nothing
// behind the disclosure can be reached" red; dropping the disclosure text's
// autofocus turns "focus opens on the disclosure text" red.

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

late InMemoryTelemetryStorage _storage;
late FocusNode _behind;
final List<String> _pressed = <String>[];

Widget _app() {
  return ProviderScope(
    overrides: [
      cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
      telemetryStorageProvider.overrideWithValue(_storage),
      telemetryBetaPeriodProvider.overrideWithValue(false),
      telemetryDevModeProvider.overrideWithValue(false),
      telemetryPlatformLocalesProvider.overrideWithValue(const [
        Locale('en', 'US'),
      ]),
      telemetryUrlLauncherProvider.overrideWithValue((uri) async {
        _pressed.add('opened $uri');
        return true;
      }),
    ],
    child: MaterialApp(
      home: TelemetryConsentGate(
        child: Scaffold(
          body: Column(
            children: [
              ElevatedButton(
                focusNode: _behind,
                autofocus: true,
                onPressed: () => _pressed.add('behind: open'),
                child: const Text('Open design'),
              ),
              ElevatedButton(
                onPressed: () => _pressed.add('behind: save'),
                child: const Text('Save design'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
}

TelemetryConsentState _stored() =>
    TelemetryConsentState.tryParse(
      _storage.values[TelemetryConsentStore.storageKey],
    ) ??
    TelemetryConsentState.unset;

void main() {
  setUp(() {
    _storage = InMemoryTelemetryStorage();
    _behind = FocusNode(debugLabel: 'behind');
    _pressed.clear();
  });
  tearDown(() => _behind.dispose());

  testWidgets('focus opens on the disclosure text, inside the named dialog', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    final strings = CruxTelemetryStringsEn(
      productName: testTelemetryConfig.userAgentName,
    );
    expect(
      describeFocus(tester).line,
      '[${strings.consentTitle} grouping] ${strings.consentBody} text',
    );
    expect(
      tester.getSemantics(find.byType(CruxModalSurface)),
      matchesSemantics(
        label: strings.consentTitle,
        scopesRoute: true,
        namesRoute: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('Tab walks the disclosure and never the app behind it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(walk.transcript, isNot(contains(' design button')));
    expectFocusWalkGolden(walk, 'test/src/goldens/telemetry_consent_gate.txt');

    final back = await walkFocus(tester, reverse: true);
    expectCleanFocusWalk(back);
    expect(back.transcript, isNot(contains(' design button')));
    handle.dispose();
  });

  testWidgets('nothing behind the disclosure can be reached', (tester) async {
    await _launch(tester);

    // The app behind grabbing focus once it has loaded, as a canvas or a
    // palette does, after the disclosure is already up.
    _behind.requestFocus();
    await tester.pump();
    expect(_behind.hasFocus, isFalse);

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(_pressed, isNot(contains('behind: open')));
    expect(_stored(), TelemetryConsentState.unset);
  });

  testWidgets('Escape does not dismiss it', (tester) async {
    await _launch(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
    expect(_stored(), TelemetryConsentState.unset);
  });

  testWidgets('it is answered with the keyboard alone, and focus moves to '
      'the app', (tester) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    Future<void> tabTo(String name) async {
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (describeFocus(tester).name.contains(name)) return;
      }
      fail('Tab never reached "$name"');
    }

    // Turn sharing off, then continue: the answer the keyboard gave is the
    // one stored.
    await tabTo('Share anonymous usage statistics');
    expect(describeFocus(tester).states, contains('on'));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(describeFocus(tester).states, contains('off'));

    await tabTo('Continue');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('telemetryConsentDialog')), findsNothing);
    expect(_stored(), TelemetryConsentState.disabled);
    expectFocusAnnounced(tester, named: 'Open design');
    handle.dispose();
  });
}
