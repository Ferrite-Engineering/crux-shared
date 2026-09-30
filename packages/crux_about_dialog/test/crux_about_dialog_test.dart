// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

const _branding = ApplicationBranding(
  companyName: 'Ferrite Engineering',
  logoAssetPath: 'assets/logo.png',
  squareLogoAssetPath: 'assets/logo_square.png',
  copyrightYear: '2025',
  websiteUrl: 'https://example.com',
);

const _buildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitShortSha: 'abc1234',
  os: 'macOS 14.5',
  architecture: 'arm64',
  flutterSdkVersion: '3.27.0',
  dartSdkVersion: '3.12.0',
);

/// Pumps the About dialog body widget directly (route form) so the test does
/// not depend on the desktop/mobile platform branch in [CruxAboutDialog.show].
Future<void> _pumpDialog(
  WidgetTester tester, {
  AsyncValue<ApplicationBuildInfo> buildInfo = const AsyncData(_buildInfo),
  String editionLabel = 'Pro',
  List<AboutAction> actions = const [],
  List<AboutAttributionSection> attributions = const [],
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  bool? betaChipVisible,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('zh', 'CN'),
          Locale('ja'),
          Locale('ko'),
        ],
        home: CruxAboutDialog(
          title: 'About TestApp',
          tagline: 'A test product',
          companyTagline: 'Ferrite Engineering',
          appIcon: const FlutterLogo(size: 80),
          branding: _branding,
          buildInfo: buildInfo,
          editionLabel: editionLabel,
          strings: const CruxAboutStringsEn(),
          actions: actions,
          attributions: attributions,
          betaChipVisible: betaChipVisible,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Pumps a button that drives the real [CruxAboutDialog.show] entry point,
/// exercising the desktop/mobile presentation branch.
Future<void> _pumpShowHarness(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => CruxAboutDialog.show(
              context,
              title: 'About TestApp',
              tagline: 'A test product',
              companyTagline: 'Ferrite Engineering',
              appIcon: const FlutterLogo(size: 80),
              branding: _branding,
              buildInfo: const AsyncData(_buildInfo),
              editionLabel: '',
              strings: const CruxAboutStringsEn(),
              actions: const [],
            ),
            child: const Text('open-about'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('aboutVersionInfoText', () {
    test('includes every field and the edition line', () {
      final text = aboutVersionInfoText(
        appName: 'TestApp',
        editionLabel: 'Pro',
        info: _buildInfo,
      );
      expect(text, contains('TestApp 1.2.3 (build 42)'));
      expect(text, contains('Edition: Pro'));
      expect(text, contains('Git SHA: abc1234'));
      expect(text, contains('OS: macOS 14.5'));
      expect(text, contains('Architecture: arm64'));
      expect(text, contains('Flutter: 3.27.0'));
      expect(text, contains('Dart: 3.12.0'));
    });

    test('omits the edition line when the label is empty', () {
      final text = aboutVersionInfoText(
        appName: 'TestApp',
        editionLabel: '',
        info: _buildInfo,
      );
      expect(text, isNot(contains('Edition:')));
    });
  });

  group('CruxAboutDialog', () {
    testWidgets('renders title, tagline, and build info', (tester) async {
      await _pumpDialog(tester);
      expect(find.text('About TestApp'), findsWidgets);
      expect(find.text('A test product'), findsOneWidget);
      expect(find.text('1.2.3'), findsOneWidget);
      expect(find.text('abc1234'), findsOneWidget);
      expect(find.text('arm64'), findsOneWidget);
    });

    testWidgets('shows a spinner while build info is loading', (tester) async {
      await _pumpDialog(
        tester,
        buildInfo: const AsyncLoading<ApplicationBuildInfo>(),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders the edition chip when a label is supplied', (
      tester,
    ) async {
      await _pumpDialog(tester);
      expect(find.text('Pro'), findsOneWidget);
    });

    testWidgets('hides the edition chip when the label is empty', (
      tester,
    ) async {
      await _pumpDialog(tester, editionLabel: '');
      expect(find.text('Pro'), findsNothing);
    });

    testWidgets('shows the beta chip when the beta period is active', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(true)],
      );
      expect(find.text('Public Beta'), findsOneWidget);
    });

    testWidgets('hides the beta chip when the beta period is inactive', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(false)],
      );
      expect(find.text('Public Beta'), findsNothing);
    });

    // `betaChipVisible` lets a host suppress the chip for a distribution
    // channel that forbids pre-release software while the product is still in
    // beta elsewhere. WaveCrux passes false on iOS/Android: Apple cited the
    // "Public Beta" chip among the signals when rejecting 0.1.0 (2) under
    // Guideline 2.2, but the desktop build is a genuine public beta and must
    // keep saying so.
    testWidgets('betaChipVisible: false hides the chip during the beta', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(true)],
        betaChipVisible: false,
      );
      expect(find.text('Public Beta'), findsNothing);
    });

    testWidgets('betaChipVisible: true shows the chip outside the beta', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(false)],
        betaChipVisible: true,
      );
      expect(find.text('Public Beta'), findsOneWidget);
    });

    testWidgets('betaChipVisible: null defers to the beta-period provider', (
      tester,
    ) async {
      // The default must stay provider-driven so the other suite products,
      // which never pass the flag, are unaffected by this seam existing.
      await _pumpDialog(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(true)],
      );
      expect(find.text('Public Beta'), findsOneWidget);
    });

    testWidgets('renders the EDU badge at the edu tier', (tester) async {
      await _pumpDialog(
        tester,
        overrides: [
          licenseTierProvider.overrideWithValue(LicenseTier.edu),
        ],
      );
      expect(find.text('EDU'), findsOneWidget);
    });

    testWidgets(
      'renders action buttons and invokes onTap with dialog context',
      (tester) async {
        BuildContext? tappedContext;
        await _pumpDialog(
          tester,
          actions: [
            AboutAction(
              label: 'Do Thing',
              icon: Icons.star,
              onTap: (ctx) => tappedContext = ctx,
            ),
          ],
        );
        expect(find.text('Do Thing'), findsOneWidget);
        await tester.tap(find.text('Do Thing'));
        expect(tappedContext, isNotNull);
      },
    );

    testWidgets('disables an action with a null onTap', (tester) async {
      await _pumpDialog(
        tester,
        actions: const [
          AboutAction(label: 'Disabled', icon: Icons.block),
        ],
      );
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Disabled'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('expands an attribution license disclosure on tap', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        attributions: const [
          AboutAttributionSection(
            title: 'Wellen',
            description: 'A VCD/FST parser.',
            licenseHeader: 'BSD 3-Clause License',
            licenseText: 'PLACEHOLDER-LICENCE-BODY',
          ),
        ],
      );
      final licenseBody = find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == 'PLACEHOLDER-LICENCE-BODY',
      );
      expect(licenseBody, findsNothing);
      final disclosure = find.text('BSD 3-Clause License');
      await tester.ensureVisible(disclosure);
      await tester.pumpAndSettle();
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(licenseBody, findsOneWidget);
    });

    testWidgets('show() presents a modal dialog on a desktop platform', (
      tester,
    ) async {
      // On web, defaultTargetPlatform reports the HOST OS, so this branch
      // also covers a desktop-browser web session (the mobile slide-in there
      // was the bug this heuristic change fixed).
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _pumpShowHarness(tester);
      await tester.tap(find.text('open-about'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      // Dialog form has no app bar (the route form's scaffold does).
      expect(find.byType(AppBar), findsNothing);
      // Must be reset before the body ends — the binding's foundation-vars
      // invariant check runs before teardown callbacks.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('show() pushes a full-screen route on a mobile platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await _pumpShowHarness(tester);
      await tester.tap(find.text('open-about'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('renders without exceptions across the locale sweep', (
      tester,
    ) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await _pumpDialog(tester, locale: locale);
        expect(tester.takeException(), isNull, reason: 'locale $locale');
      }
    });
  });
}
