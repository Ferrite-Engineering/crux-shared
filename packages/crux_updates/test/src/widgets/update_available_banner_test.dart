// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in for a product's ARB-backed adapter, with deliberately different
/// copy from the English default. The package ships no ARB files, so the
/// locale sweep is expressed as a *strings* sweep: the per-locale ARB sweep
/// belongs to the consuming product's own widget tests.
class _AltStrings extends CruxUpdateStrings {
  const _AltStrings();

  @override
  String bannerMessage(String version) => 'ALT $version ALT';

  @override
  String get viewChangesAction => 'ALT-changes';

  @override
  String get updateNowAction => 'ALT-now';

  @override
  String get dismissLabel => 'ALT-dismiss';

  @override
  String get checkInProgress => 'ALT-checking';

  @override
  String checkUpToDate(String version) => 'ALT-current';

  @override
  String get checkFailed => 'ALT-failed';
}

void _noop() {}

Widget _wrap({
  String version = '1.2.0',
  bool mandatory = false,
  CruxUpdateStrings strings = const CruxUpdateStringsEn(
    productName: 'NetCrux',
  ),
  CruxUpdateBannerMetrics metrics = const CruxUpdateBannerMetrics(),
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
  VoidCallback? onUpdateNow,
  VoidCallback? onViewChanges = _noop,
  VoidCallback? onDismiss = _noop,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: direction,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: UpdateAvailableBanner(
            version: version,
            mandatory: mandatory,
            strings: strings,
            metrics: metrics,
            onUpdateNow: onUpdateNow ?? _noop,
            onViewChanges: onViewChanges,
            onDismiss: onDismiss,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('rendering sweep', () {
    for (final direction in TextDirection.values) {
      for (final scale in <double>[1, 1.5, 2]) {
        testWidgets('renders without exceptions in $direction at $scale x', (
          tester,
        ) async {
          await tester.pumpWidget(
            _wrap(direction: direction, textScale: scale),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('renders a product string set unchanged', (tester) async {
      await tester.pumpWidget(_wrap(strings: const _AltStrings()));
      await tester.pumpAndSettle();
      expect(find.text('ALT 1.2.0 ALT'), findsOneWidget);
      expect(find.text('ALT-changes'), findsOneWidget);
      expect(find.text('ALT-now'), findsOneWidget);
    });
  });

  testWidgets('shows the version in the message', (tester) async {
    await tester.pumpWidget(_wrap(version: '3.4.5'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3.4.5'), findsOneWidget);
  });

  testWidgets('non-mandatory shows a dismiss affordance', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('mandatory hides the dismiss affordance', (tester) async {
    await tester.pumpWidget(_wrap(mandatory: true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('mandatory hides dismissal even when onDismiss is supplied', (
    tester,
  ) async {
    var dismissals = 0;
    await tester.pumpWidget(
      _wrap(mandatory: true, onDismiss: () => dismissals++),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IconButton), findsNothing);
    expect(dismissals, 0);
  });

  testWidgets('hides the dismiss affordance when onDismiss is null', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(onDismiss: null));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('hides View Changes when onViewChanges is null', (tester) async {
    await tester.pumpWidget(_wrap(onViewChanges: null));
    await tester.pumpAndSettle();
    const strings = CruxUpdateStringsEn();
    expect(find.text(strings.viewChangesAction), findsNothing);
    expect(find.text(strings.updateNowAction), findsOneWidget);
  });

  testWidgets('Update Now and View Changes invoke their callbacks', (
    tester,
  ) async {
    var updates = 0;
    var views = 0;
    await tester.pumpWidget(
      _wrap(onUpdateNow: () => updates++, onViewChanges: () => views++),
    );
    await tester.pumpAndSettle();
    const strings = CruxUpdateStringsEn();

    await tester.tap(find.text(strings.updateNowAction));
    await tester.tap(find.text(strings.viewChangesAction));
    expect(updates, 1);
    expect(views, 1);
  });

  testWidgets('dismiss button fires onDismiss', (tester) async {
    var dismissals = 0;
    await tester.pumpWidget(_wrap(onDismiss: () => dismissals++));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    expect(dismissals, 1);
  });

  testWidgets('the dismiss button carries an accessible name', (tester) async {
    await tester.pumpWidget(_wrap(strings: const _AltStrings()));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('ALT-dismiss'),
      findsAtLeastNWidgets(1),
    );
  });

  group('touch targets', () {
    testWidgets('the dismiss button meets the 44x44 minimum by default', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('the action buttons meet the 44x44 minimum by default', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        final size = tester.getSize(find.byWidget(button));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('host metrics widen the targets on a touch device', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          metrics: const CruxUpdateBannerMetrics(
            touchTarget: 56,
            iconSize: 24,
            bodyFontSize: 16,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(56));
      expect(size.height, greaterThanOrEqualTo(56));
    });
  });
}
