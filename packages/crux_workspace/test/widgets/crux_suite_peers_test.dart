// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

List<CruxSuitePeerEntry> _entriesFor(CruxSuiteProduct host) => [
  for (final peer in host.peers)
    CruxSuitePeerEntry(product: peer, blurb: 'what ${peer.slug} does for you'),
];

void main() {
  group('CruxSuiteProduct', () {
    test('names the same four products as the licensing enum, in order', () {
      // The two enumerations exist for different reasons and must not drift.
      // `crux_license` is a dev dependency precisely so this can be asserted
      // without `crux_workspace` depending on licensing at runtime.
      expect(
        CruxSuiteProduct.values.map((p) => p.displayName).toList(),
        CruxProduct.values.map((p) => p.displayName).toList(),
      );
    });

    test('slugs are the lower-case display names', () {
      for (final product in CruxSuiteProduct.values) {
        expect(product.slug, product.displayName.toLowerCase());
      }
    });

    test('peers is the other three, and never the host', () {
      for (final product in CruxSuiteProduct.values) {
        expect(product.peers, hasLength(3));
        expect(product.peers, isNot(contains(product)));
      }
    });
  });

  group('CruxSuitePeers', () {
    testWidgets('renders a row per peer, named and described', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CruxSuitePeers(
            heading: 'MORE FROM EDACRUX',
            entries: _entriesFor(CruxSuiteProduct.waveCrux),
            onOpenPeer: (_) {},
          ),
        ),
      );

      expect(find.text('MORE FROM EDACRUX'), findsOneWidget);
      for (final peer in CruxSuiteProduct.waveCrux.peers) {
        expect(find.text(peer.displayName), findsOneWidget);
        expect(find.text('what ${peer.slug} does for you'), findsOneWidget);
      }
      // The host product never offers itself.
      expect(find.text('WaveCrux'), findsNothing);
    });

    testWidgets('each row reports which peer was chosen', (tester) async {
      final opened = <CruxSuiteProduct>[];
      await tester.pumpWidget(
        _wrap(
          CruxSuitePeers(
            heading: 'MORE FROM EDACRUX',
            entries: _entriesFor(CruxSuiteProduct.simCrux),
            onOpenPeer: opened.add,
          ),
        ),
      );

      await tester.tap(
        find.byKey(CruxSuitePeers.rowKeyFor(CruxSuiteProduct.lintCrux)),
      );
      expect(opened, [CruxSuiteProduct.lintCrux]);
    });

    testWidgets('a row is one focusable link, not a tappable paragraph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CruxSuitePeers(
            heading: 'MORE FROM EDACRUX',
            entries: _entriesFor(CruxSuiteProduct.waveCrux),
            onOpenPeer: (_) {},
          ),
        ),
      );

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(
          find.byKey(CruxSuitePeers.rowKeyFor(CruxSuiteProduct.netCrux)),
        ),
        matchesSemantics(
          label: 'NetCrux\nwhat netcrux does for you',
          isLink: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('EmptyCanvasState stacks it above the footer line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EmptyCanvasState(
            title: 'Welcome to TestCrux',
            primaryActions: [
              FilledButton(onPressed: () {}, child: const Text('Open File…')),
            ],
            peers: CruxSuitePeers(
              heading: 'MORE FROM EDACRUX',
              entries: _entriesFor(CruxSuiteProduct.waveCrux),
              onOpenPeer: (_) {},
            ),
            footer: CruxSuiteFooter(
              label: 'A member of the EDACrux suite of products — edacrux.app',
              onTap: () {},
            ),
          ),
        ),
      );

      final peersBottom = tester
          .getBottomLeft(find.text('MORE FROM EDACRUX'))
          .dy;
      final footerTop = tester
          .getTopLeft(find.byKey(CruxSuiteFooter.rowKey))
          .dy;
      expect(peersBottom, lessThan(footerTop));
      expect(
        tester.getBottomLeft(find.text('Open File…')).dy,
        lessThan(peersBottom),
      );
    });

    testWidgets('renders nothing at all when there are no entries', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CruxSuitePeers(
            heading: 'MORE FROM EDACRUX',
            entries: const [],
            onOpenPeer: (_) {},
          ),
        ),
      );
      expect(find.text('MORE FROM EDACRUX'), findsNothing);
    });
  });
}
