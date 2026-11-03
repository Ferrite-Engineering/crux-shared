// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A menu opened from inside a nested navigator opens at the pointer.
///
/// The host mimics a tabbed workspace: a strip above the root navigator (the
/// licence-expiry strip), and below another strip a nested navigator (a tab's
/// own). The root overlay and the nested overlay have different origins, so a
/// menu whose position is measured against one and laid out in the other opens
/// that offset away from the click.
const double _rootStripHeight = 90;
const double _tabStripHeight = 85;
const double _tolerance = 4;

void main() {
  const entries = <CruxMenuEntry>[
    CruxMenuItem(label: 'Rename', onSelected: _noop),
    CruxMenuItem(label: 'Delete', onSelected: _noop),
  ];

  Widget host(Widget Function(BuildContext) body) => MaterialApp(
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
    ),
    builder: (context, child) => Column(
      children: <Widget>[
        const SizedBox(height: _rootStripHeight),
        Expanded(child: child!),
      ],
    ),
    home: Scaffold(
      body: Column(
        children: <Widget>[
          const SizedBox(height: _tabStripHeight),
          Expanded(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Material(child: body(context)),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// The menu's own surface: the nearest Material above an item's label.
  Rect menuRect(WidgetTester tester, String label) {
    final menu = find
        .ancestor(of: find.text(label), matching: find.byType(Material))
        .first;
    return tester.getRect(menu);
  }

  testWidgets('showCruxContextMenu opens at the click', (tester) async {
    late BuildContext inner;
    await tester.pumpWidget(
      host((context) {
        inner = context;
        return const SizedBox.expand();
      }),
    );
    const click = Offset(300, 400);

    unawaited(
      showCruxContextMenu(inner, globalPosition: click, entries: entries),
    );
    await tester.pumpAndSettle();

    final menu = menuRect(tester, 'Rename');
    expect((menu.left - click.dx).abs(), lessThan(_tolerance));
    expect((menu.top - click.dy).abs(), lessThan(_tolerance));
  });

  testWidgets('a right-click in a nested navigator opens at the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        (context) => const CruxContextMenuRegion(
          entries: entries,
          child: SizedBox.expand(),
        ),
      ),
    );
    const click = Offset(250, 350);

    final gesture = await tester.startGesture(
      click,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final menu = menuRect(tester, 'Delete');
    expect((menu.left - click.dx).abs(), lessThan(_tolerance));
    expect((menu.top - click.dy).abs(), lessThan(_tolerance));
  });

  testWidgets('the overflow button opens its menu under itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        (context) => const Align(
          alignment: Alignment.topLeft,
          child: CruxOverflowMenu(entries: entries, tooltip: 'More actions'),
        ),
      ),
    );
    final button = tester.getRect(find.byType(CruxOverflowMenu));

    await tester.tap(find.byType(CruxOverflowMenu));
    await tester.pumpAndSettle();

    final menu = menuRect(tester, 'Rename');
    expect((menu.top - button.bottom).abs(), lessThan(_tolerance));
    expect((menu.left - button.left).abs(), lessThan(button.width + 8));
  });

  testWidgets('a submenu opens beside its row inside a nested navigator', (
    tester,
  ) async {
    late BuildContext inner;
    await tester.pumpWidget(
      host((context) {
        inner = context;
        return const SizedBox.expand();
      }),
    );

    unawaited(
      showCruxContextMenu(
        inner,
        globalPosition: const Offset(200, 300),
        entries: <CruxMenuEntry>[
          CruxSubmenu(
            label: 'Send to',
            entries: <CruxMenuEntry>[
              CruxMenuItem(label: 'WaveCrux', onSelected: () {}),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final row = tester.getRect(find.text('Send to'));

    await tester.tap(find.text('Send to'));
    await tester.pumpAndSettle();

    final second = menuRect(tester, 'WaveCrux');
    expect((second.top - row.top).abs(), lessThan(row.height * 2));
  });
}

void _noop() {}
