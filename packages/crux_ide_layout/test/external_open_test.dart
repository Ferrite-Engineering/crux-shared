// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A link no browser opens and a file no file manager shows used to do
// nothing at all: on a Linux host displayed remotely the user clicked, waited,
// and clicked again. These hold the notice that replaced the silence.

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_ide_layout/src/crux_toast.dart' show registerCruxToastHost;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers its overlay as a toast host, as the window chrome does.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  VoidCallback? _release;

  @override
  void initState() {
    super.initState();
    _release = registerCruxToastHost(context);
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Widget _app({Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  supportedLocales: const <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
  ],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData(
    extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
  ),
  home: const Scaffold(body: _Host()),
);

void main() {
  final address = Uri.parse('https://example.com/docs/page');
  const path = '/home/me/rtl/wave.vcd';

  testWidgets('a link that opens shows nothing', (tester) async {
    await tester.pumpWidget(_app());
    final opened = await cruxReportingUrlLauncher((_) async => true)(address);
    await tester.pump();

    expect(opened, isTrue);
    expect(find.textContaining('$address'), findsNothing);
  });

  // MUTATION: returning without reporting when the launch answers false
  // turns this red.
  testWidgets('a link nothing opens is named in an error toast with Copy', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_app());

    final opened = await cruxReportingUrlLauncher((_) async => false)(address);
    await tester.pump();

    expect(opened, isFalse);
    expect(
      find.text(CruxExternalOpenStrings.en.linkNotOpened('$address')),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, '$address');
  });

  testWidgets('a launcher that throws is reported, not rethrown', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    final opened = await cruxReportingUrlLauncher(
      (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    )(address);
    await tester.pump();

    expect(opened, isFalse);
    expect(find.textContaining('$address'), findsOneWidget);
  });

  // MUTATION: ignoring the reveal's answer turns this red.
  testWidgets('a file no file manager shows is named in an error toast', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    expect(await cruxRevealFile(path, reveal: (_) async => true), isTrue);
    await tester.pump();
    expect(find.textContaining(path), findsNothing);

    expect(await cruxRevealFile(path, reveal: (_) async => false), isFalse);
    await tester.pump();
    expect(
      find.text(CruxExternalOpenStrings.en.fileNotRevealed(path)),
      findsOneWidget,
    );
  });

  testWidgets("the notice is in the host window's language", (tester) async {
    await tester.pumpWidget(_app(locale: const Locale('ja')));

    await cruxRevealFile(path, reveal: (_) async => false);
    await tester.pump();

    expect(
      find.text(CruxExternalOpenStrings.ja.fileNotRevealed(path)),
      findsOneWidget,
    );
    expect(find.text(CruxExternalOpenStrings.ja.copy), findsOneWidget);
  });

  test('every locale names the address and the path, without em dashes', () {
    for (final locale in const <String>['en', 'zh', 'ja', 'ko']) {
      final strings = CruxExternalOpenStrings.forLocale(Locale(locale));
      final link = strings.linkNotOpened('https://x.test/a');
      final file = strings.fileNotRevealed('/tmp/a.vcd');
      expect(link, contains('https://x.test/a'), reason: locale);
      expect(file, contains('/tmp/a.vcd'), reason: locale);
      for (final text in <String>[link, file, strings.copy]) {
        expect(text, isNot(contains('—')), reason: locale);
      }
    }
    expect(
      CruxExternalOpenStrings.forLocale(const Locale('fr')),
      same(CruxExternalOpenStrings.en),
    );
  });
}
