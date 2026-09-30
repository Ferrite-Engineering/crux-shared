// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _child = Key('routedContent');
const _dialog = Key('cruxEulaDialog');
const _checkbox = Key('cruxEulaAcceptCheckbox');
const _accept = Key('cruxEulaAcceptButton');
const _decline = Key('cruxEulaDeclineButton');
const _openOnline = Key('cruxEulaOpenOnlineButton');

Widget _app(
  CruxEulaStorage storage, {
  List<Override> extra = const [],
  bool presentAgreement = true,
}) {
  return ProviderScope(
    overrides: [
      cruxEulaStorageProvider.overrideWithValue(storage),
      ...extra,
    ],
    child: MaterialApp(
      home: CruxEulaGate(
        presentAgreement: presentAgreement,
        child: const SizedBox(key: _child),
      ),
    ),
  );
}

void main() {
  group('CruxEulaGate', () {
    testWidgets('presents the agreement on a first launch', (tester) async {
      await tester.pumpWidget(_app(InMemoryCruxEulaStorage()));
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsOneWidget);
      // The child is still mounted underneath — the gate stacks over it rather
      // than replacing it, so app state built during startup is not discarded
      // when the agreement is accepted.
      expect(find.byKey(_child), findsOneWidget);
    });

    testWidgets('presents nothing when the surface does not present it', (
      tester,
    ) async {
      // The embedded case: a VSCode webview, where the agreement belongs to
      // the host application rather than to a panel inside it.
      await tester.pumpWidget(
        _app(InMemoryCruxEulaStorage(), presentAgreement: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsNothing);
      expect(find.byKey(_child), findsOneWidget);
    });

    testWidgets('not presenting is not accepting', (tester) async {
      // The other way to make this dialog go away is to report an acceptance
      // that was never given. This asserts we did not: nothing is written, so
      // the same install still presents the agreement when it next runs
      // standalone.
      final storage = InMemoryCruxEulaStorage();
      await tester.pumpWidget(_app(storage, presentAgreement: false));
      await tester.pumpAndSettle();

      expect(
        await storage.read(kCruxEulaAcceptedVersionKey),
        isNull,
        reason: 'suppressing the surface must record no acceptance',
      );
    });

    testWidgets('renders the child untouched once accepted', (tester) async {
      await tester.pumpWidget(
        _app(
          InMemoryCruxEulaStorage({
            kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsNothing);
      expect(find.byKey(_child), findsOneWidget);
    });

    // Mounting on the store's synchronous `null` would flash a licence
    // agreement at a user who accepted it a year ago.
    testWidgets('does not flash at a returning user before the store loads', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          InMemoryCruxEulaStorage({
            kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
          }),
        ),
      );

      // First frame, before the async read has landed.
      await tester.pump();
      expect(find.byKey(_dialog), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsNothing);
    });

    testWidgets('re-presents when the accepted version is an older one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          InMemoryCruxEulaStorage({
            kCruxEulaAcceptedVersionKey: '0.9-superseded',
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsOneWidget);
      expect(
        find.text(const CruxEulaStrings().updatedNotice),
        findsOneWidget,
        reason: 'a returning user is told why they are being asked again',
      );
    });

    testWidgets('accepting dismisses the agreement and persists the version', (
      tester,
    ) async {
      final storage = InMemoryCruxEulaStorage();
      await tester.pumpWidget(_app(storage));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_accept));
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsNothing);
      expect(storage.values[kCruxEulaAcceptedVersionKey], kCruxEulaVersion);
    });
  });

  group('CruxEulaAcceptanceDialog', () {
    // The checkbox is the whole reason acceptance takes a deliberate second
    // act. If Accept were live without it, the tick would mean nothing.
    testWidgets('Accept is disabled until the checkbox is ticked', (
      tester,
    ) async {
      await tester.pumpWidget(_app(InMemoryCruxEulaStorage()));
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(find.byKey(_accept)).onPressed,
        isNull,
      );

      await tester.tap(find.byKey(_checkbox));
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(find.byKey(_accept)).onPressed,
        isNotNull,
      );
    });

    testWidgets('shows the agreement text itself, not a link to it', (
      tester,
    ) async {
      await tester.pumpWidget(_app(InMemoryCruxEulaStorage()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cruxEulaDocumentScroll')), findsOneWidget);
      expect(find.textContaining('1. Definitions'), findsWidgets);
    });

    // Section 3's promise, on the surface where it matters.
    testWidgets('states that accepting is not a condition of the open-source '
        'licence', (tester) async {
      await tester.pumpWidget(_app(InMemoryCruxEulaStorage()));
      await tester.pumpAndSettle();

      expect(
        find.text(const CruxEulaStrings().openSourceNote),
        findsOneWidget,
      );
    });

    // A dead control is worse than an absent one.
    testWidgets('hides Decline and the online link when unbound', (
      tester,
    ) async {
      await tester.pumpWidget(_app(InMemoryCruxEulaStorage()));
      await tester.pumpAndSettle();

      expect(find.byKey(_decline), findsNothing);
      expect(find.byKey(_openOnline), findsNothing);
    });

    testWidgets('shows Decline and the online link when bound', (tester) async {
      var declined = false;
      var opened = false;
      await tester.pumpWidget(
        _app(
          InMemoryCruxEulaStorage(),
          extra: [
            cruxEulaOnDeclineProvider.overrideWithValue(() => declined = true),
            cruxEulaOpenOnlineProvider.overrideWithValue(() async {
              opened = true;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_decline));
      await tester.pumpAndSettle();
      expect(declined, isTrue);

      await tester.tap(find.byKey(_openOnline));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    // Section 2.1 leaves no third outcome, so there is no way past this
    // surface that is not an answer.
    testWidgets('a back gesture does not dismiss the agreement', (
      tester,
    ) async {
      final storage = InMemoryCruxEulaStorage();
      await tester.pumpWidget(_app(storage));
      await tester.pumpAndSettle();

      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        popped,
        isTrue,
        reason: 'the route handled it rather than exiting',
      );
      expect(find.byKey(_dialog), findsOneWidget);
      expect(storage.values, isEmpty);
    });
  });
}
