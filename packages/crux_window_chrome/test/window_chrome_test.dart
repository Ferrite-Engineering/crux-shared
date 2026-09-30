// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:crux_window_chrome/src/widgets/window_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  // On the VM test target dart:io is available, so the facade resolves to the
  // real `window_chrome_io.dart` implementation. (The web stub is selected at
  // compile time by the conditional export and can't be exercised here.)
  group('window_chrome facade (dart:io impl)', () {
    test('buildWindowTitleBar returns a WindowTitleBar hosting the menu', () {
      const menu = SizedBox.shrink();
      final widget = buildWindowTitleBar(
        menuBar: menu,
        logo: const SizedBox.shrink(),
      );
      expect(widget, isA<WindowTitleBar>());
      expect((widget as WindowTitleBar).menuBar, same(menu));
    });

    test('buildWindowFrame wraps the child in a VirtualWindowFrame', () {
      const child = SizedBox.shrink();
      final widget = buildWindowFrame(child);
      expect(widget, isA<VirtualWindowFrame>());
      expect((widget as VirtualWindowFrame).child, same(child));
    });

    testWidgets(
      'buildWindowChrome renders a real MnemonicMenuBar with no Navigator '
      'above it, without the "No Overlay" error',
      (tester) async {
        // Deliberately NO MaterialApp/Navigator ancestor — only the ambient
        // widgets the chrome needs — so a missing Overlay would throw.
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Theme(
                data: ThemeData(),
                child: buildWindowChrome(
                  logo: const SizedBox.shrink(),
                  menuBar: const MnemonicMenuBar(
                    entries: [
                      MnemonicMenuEntry(
                        acceleratorLabel: '&File',
                        menuChildren: <Widget>[],
                      ),
                    ],
                  ),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(MnemonicMenuBar), findsOneWidget);
      },
    );

    testWidgets(
      'buildWindowChrome with no Navigator above it rebuilds the menu bar and '
      'child when the host rebuilds',
      (tester) async {
        // The regression: the chrome's own Overlay captured the first menu
        // bar, so a menu item enabled after launch stayed disabled.
        Widget host({required bool enabled, required String body}) =>
            MediaQuery(
              data: const MediaQueryData(size: Size(1200, 800)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Theme(
                  data: ThemeData(),
                  child: buildWindowChrome(
                    logo: const SizedBox.shrink(),
                    menuBar: MnemonicMenuBar(
                      entries: [
                        MnemonicMenuEntry(
                          acceleratorLabel: '&Search',
                          menuChildren: <Widget>[
                            MenuItemButton(
                              onPressed: enabled ? () {} : null,
                              child: const Text('Search…'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    child: Text(body),
                  ),
                ),
              ),
            );

        MenuItemButton searchItem() => tester.widget<MenuItemButton>(
          find.widgetWithText(MenuItemButton, 'Search…'),
        );

        await tester.pumpWidget(host(enabled: false, body: 'first'));
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        expect(searchItem().onPressed, isNull);

        await tester.pumpWidget(host(enabled: true, body: 'second'));
        await tester.pumpAndSettle();
        expect(searchItem().onPressed, isNotNull);
        expect(find.text('second'), findsOneWidget);
        expect(find.text('first'), findsNothing);
      },
    );

    test(
      'readCurrentWindowBounds returns null without a live window channel',
      () async {
        // No window_manager platform handler is registered under flutter_test,
        // so the underlying method-channel call fails; the facade swallows it
        // and returns null so the quit-time capture simply skips this session.
        TestWidgetsFlutterBinding.ensureInitialized();
        expect(await readCurrentWindowBounds(), isNull);
      },
    );

    testWidgets(
      'buildWindowGeometryPersister renders its child and mounts/unmounts the '
      'window listener cleanly',
      (tester) async {
        await tester.pumpWidget(
          buildWindowGeometryPersister(
            onChanged: (_) async {},
            child: const MaterialApp(home: Text('content')),
          ),
        );
        expect(find.text('content'), findsOneWidget);
        // Replacing the tree disposes the persister; addListener/removeListener
        // are local registrations (no channel), so this must not throw.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  });
}
