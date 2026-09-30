// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `theme_pack_browser.dart` was the worst-covered widget in the
/// repo (26.7%) because every test pumped exactly one frame and
/// asserted pre-resolution chrome — `pumpAndSettle` hung on a real
/// filesystem Future. The constraint was honestly documented but not
/// fixed.
///
/// The fix was a layering change: the widget now takes a
/// [ThemePackStore] instead of a `dart:io` `Directory`, so a test
/// supplies an in-memory store whose futures complete on the microtask
/// queue. `pumpAndSettle` works, and the list / activate / uninstall /
/// error states are all reachable.
const _strings = ThemeAppearanceStringsEn();

CruxColorTheme _activeTheme() => CruxColorTheme(
  id: 'active',
  displayName: 'Active',
  brightness: Brightness.dark,
  tokens: const {
    'chrome': {'scaffold.background': Color(0xFF111111)},
  },
);

ThemePack _packOf(String id, {Brightness brightness = Brightness.dark}) =>
    ThemePack(
      id: id,
      displayName: 'Pack $id',
      brightness: brightness,
      tokens: const {
        'chrome': {'scaffold.background': Color(0xFF222222)},
      },
    );

String _documentFor(String id) => jsonEncode({
  'schemaVersion': 1,
  'id': id,
  'displayName': 'Pack $id',
  'brightness': 'dark',
  'tokens': <String, Object?>{
    'chrome': {'scaffold.background': '#222222'},
  },
});

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        cruxColorThemeProvider.overrideWith(
          () => CruxColorThemeNotifier(initial: _activeTheme()),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpBrowser(
    WidgetTester tester, {
    required ThemePackStore store,
    PickPackDocument? pickPackDocument,
    SavePackDocument? savePackDocument,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ThemePackBrowser(
              store: store,
              pickPackDocument: pickPackDocument ?? () async => null,
              savePackDocument: savePackDocument ?? (_) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('chrome', () {
    testWidgets('renders import + export buttons and the list heading', (
      tester,
    ) async {
      await pumpBrowser(tester, store: InMemoryThemePackStore());
      expect(find.text(_strings.importThemePackButtonLabel), findsOneWidget);
      expect(
        find.text(_strings.exportCurrentThemeButtonLabel),
        findsOneWidget,
      );
      expect(find.text(_strings.installedPacksHeading), findsOneWidget);
    });

    testWidgets('shows the empty-state message when nothing is installed', (
      tester,
    ) async {
      await pumpBrowser(tester, store: InMemoryThemePackStore());
      expect(find.text(_strings.noInstalledPacksMessage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('pack list rendering', () {
    testWidgets('renders one row per installed pack', (tester) async {
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(
          initialPacks: [
            _packOf('midnight'),
            _packOf('daylight', brightness: Brightness.light),
          ],
        ),
      );
      expect(find.text('Pack midnight'), findsOneWidget);
      expect(find.text('midnight'), findsOneWidget);
      expect(find.text('Pack daylight'), findsOneWidget);
      expect(find.text(_strings.noInstalledPacksMessage), findsNothing);
    });

    testWidgets('shows a brightness icon matching each pack', (tester) async {
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(
          initialPacks: [
            _packOf('midnight'),
            _packOf('daylight', brightness: Brightness.light),
          ],
        ),
      );
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
    });

    testWidgets('every row offers activate and uninstall', (tester) async {
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(initialPacks: [_packOf('midnight')]),
      );
      expect(find.text(_strings.activatePackButtonLabel), findsOneWidget);
      expect(find.text(_strings.uninstallPackButtonLabel), findsOneWidget);
    });
  });

  group('activate', () {
    testWidgets('activating a pack replaces the active theme', (tester) async {
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(initialPacks: [_packOf('midnight')]),
      );
      expect(container.read(cruxColorThemeProvider).id, 'active');

      await tester.tap(find.text(_strings.activatePackButtonLabel));
      await tester.pumpAndSettle();

      final active = container.read(cruxColorThemeProvider);
      expect(active.id, 'midnight');
      expect(active.displayName, 'Pack midnight');
      expect(
        active.color('chrome', 'scaffold.background'),
        const Color(0xFF222222),
      );
    });

    testWidgets('a failing load surfaces a snackbar and leaves the active '
        'theme alone', (tester) async {
      final store = InMemoryThemePackStore(
        initialPacks: [_packOf('midnight')],
      );
      await pumpBrowser(tester, store: store);
      store.failWith = const FormatException('pack is corrupt');

      await tester.tap(find.text(_strings.activatePackButtonLabel));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(container.read(cruxColorThemeProvider).id, 'active');
    });
  });

  group('uninstall', () {
    testWidgets('confirming removes the pack and refreshes the list', (
      tester,
    ) async {
      final store = InMemoryThemePackStore(
        initialPacks: [_packOf('midnight')],
      );
      await pumpBrowser(tester, store: store);

      await tester.tap(find.text(_strings.uninstallPackButtonLabel));
      await tester.pumpAndSettle();
      expect(find.text(_strings.confirmUninstallDialogTitle), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          // The dialog's confirm label is the same word as the row's
          // own Uninstall button, so scope the tap to the dialog.
          matching: find.text(_strings.confirmUninstallConfirmLabel),
        ),
      );
      await tester.pumpAndSettle();

      expect(store.uninstalledIds, ['midnight']);
      expect(find.text('Pack midnight'), findsNothing);
      expect(find.text(_strings.noInstalledPacksMessage), findsOneWidget);
    });

    testWidgets('cancelling removes nothing', (tester) async {
      final store = InMemoryThemePackStore(
        initialPacks: [_packOf('midnight')],
      );
      await pumpBrowser(tester, store: store);

      await tester.tap(find.text(_strings.uninstallPackButtonLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_strings.confirmUninstallCancelLabel));
      await tester.pumpAndSettle();

      expect(store.uninstalledIds, isEmpty);
      expect(find.text('Pack midnight'), findsOneWidget);
    });

    testWidgets('a failing uninstall surfaces a snackbar', (tester) async {
      final store = InMemoryThemePackStore(
        initialPacks: [_packOf('midnight')],
      );
      await pumpBrowser(tester, store: store);
      await tester.tap(find.text(_strings.uninstallPackButtonLabel));
      await tester.pumpAndSettle();
      store.failWith = Exception('permission denied');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          // The dialog's confirm label is the same word as the row's
          // own Uninstall button, so scope the tap to the dialog.
          matching: find.text(_strings.confirmUninstallConfirmLabel),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Pack midnight'), findsOneWidget);
    });
  });

  group('import', () {
    testWidgets('cancelling the picker is a no-op', (tester) async {
      var calls = 0;
      final store = InMemoryThemePackStore();
      await pumpBrowser(
        tester,
        store: store,
        pickPackDocument: () async {
          calls++;
          return null;
        },
      );
      await tester.tap(find.text(_strings.importThemePackButtonLabel));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(store.installedDocuments, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a valid document installs and appears in the list', (
      tester,
    ) async {
      final store = InMemoryThemePackStore();
      await pumpBrowser(
        tester,
        store: store,
        pickPackDocument: () async => _documentFor('imported'),
      );
      await tester.tap(find.text(_strings.importThemePackButtonLabel));
      await tester.pumpAndSettle();

      expect(store.installedDocuments, hasLength(1));
      expect(find.text('Pack imported'), findsOneWidget);
      expect(
        find.text(_strings.importSucceededMessage('imported')),
        findsOneWidget,
      );
    });

    testWidgets('a malformed document reports an error and installs '
        'nothing', (tester) async {
      final store = InMemoryThemePackStore();
      await pumpBrowser(
        tester,
        store: store,
        pickPackDocument: () async => '{not json',
      );
      await tester.tap(find.text(_strings.importThemePackButtonLabel));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(_strings.noInstalledPacksMessage), findsOneWidget);
    });

    testWidgets('a path-traversal id is refused at the widget level too', (
      tester,
    ) async {
      // End-to-end confirmation that the decode-time guard protects the
      // real user-facing entry point, not just the codec API.
      final store = InMemoryThemePackStore();
      await pumpBrowser(
        tester,
        store: store,
        pickPackDocument: () async => _documentFor('../../../evil'),
      );
      await tester.tap(find.text(_strings.importThemePackButtonLabel));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(_strings.noInstalledPacksMessage), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('cancelling the destination picker shows no message', (
      tester,
    ) async {
      var calls = 0;
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(),
        savePackDocument: (_) async {
          calls++;
          return null;
        },
      );
      await tester.tap(find.text(_strings.exportCurrentThemeButtonLabel));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('exports the ACTIVE theme as a decodable document', (
      tester,
    ) async {
      String? written;
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(),
        savePackDocument: (document) async {
          written = document;
          return '/tmp/active.crux-theme.json';
        },
      );
      await tester.tap(find.text(_strings.exportCurrentThemeButtonLabel));
      await tester.pumpAndSettle();

      expect(written, isNotNull);
      final roundTripped = const ThemePackCodec().decode(written!);
      expect(roundTripped.id, 'active');
      expect(
        roundTripped.color('chrome', 'scaffold.background'),
        const Color(0xFF111111),
      );
      expect(
        find.text(
          _strings.exportSucceededMessage('/tmp/active.crux-theme.json'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failing write reports the error', (tester) async {
      await pumpBrowser(
        tester,
        store: InMemoryThemePackStore(),
        savePackDocument: (_) async => throw Exception('disk full'),
      );
      await tester.tap(find.text(_strings.exportCurrentThemeButtonLabel));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('the widget is web-renderable', () {
    // The layering guarantee, asserted statically: a consumer must be
    // able to render the Appearance panel on web, where constructing a
    // dart:io Directory is impossible. This is the guard that stops the
    // dependency creeping back in.
    const webFacing = <String>[
      'lib/src/widgets/theme_pack_browser.dart',
      'lib/src/widgets/theme_appearance_section.dart',
      'lib/src/theme_pack_store.dart',
    ];

    for (final path in webFacing) {
      test('$path does not import dart:io', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains("import 'dart:io'"),
          isFalse,
          reason:
              '$path is part of the web-renderable widget surface; the '
              'dart:io implementation belongs in '
              'directory_theme_pack_store.dart',
        );
      });
    }

    test('the dart:io implementation still exists for desktop/mobile', () {
      final source = File(
        'lib/src/directory_theme_pack_store.dart',
      ).readAsStringSync();
      expect(source.contains("import 'dart:io'"), isTrue);
    });
  });
}
