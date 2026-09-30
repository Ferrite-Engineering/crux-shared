// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared half of the settings rail-order guard.
///
/// Each product owns the other half: a conformance test asserting that its own
/// settings screen emits ids in an order consistent with
/// [CruxSettingsCategoryId.canonicalOrder]. This file only guarantees the
/// vocabulary those tests key off — that the id list is internally coherent,
/// and that a Pro-contributed category carries its id through the conversion
/// so the product-side test can tell built-ins from extras.
void main() {
  group('CruxSettingsCategoryId', () {
    test('canonicalOrder has no duplicates', () {
      expect(
        CruxSettingsCategoryId.canonicalOrder.toSet().length,
        CruxSettingsCategoryId.canonicalOrder.length,
      );
    });

    test('every id is kebab-case and free of display punctuation', () {
      for (final id in CruxSettingsCategoryId.canonicalOrder) {
        expect(
          RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(id),
          isTrue,
          reason:
              '"$id" is identity, not display text — it must never be '
              'localized or title-cased.',
        );
      }
    });

    test('no canonical id collides with the Pro extension namespace', () {
      // `CruxSettingsExtraCategory` ids are `pro.*`. A built-in taking that
      // prefix would make the two indistinguishable in an assembled rail.
      for (final id in CruxSettingsCategoryId.canonicalOrder) {
        expect(id.startsWith('pro.'), isFalse);
      }
    });

    test('the product-defaults slot is a single id, not one per product', () {
      // Each product titles this slot differently. Giving each its own id
      // would put a single-product vocabulary in shared code, which
      // crux_workspace's charter-vocabulary guard rejects — and it would also
      // make the rail-order assertion unable to tell a product that omits the
      // slot from one that merely renamed it.
      expect(
        CruxSettingsCategoryId.canonicalOrder.where(
          (id) => id.contains('default'),
        ),
        <String>[CruxSettingsCategoryId.productDefaults],
      );
    });
  });

  group('CruxSettingsExtraCategory.toCategory', () {
    testWidgets('carries the pro id through to the assembled category', (
      tester,
    ) async {
      const extra = CruxSettingsExtraCategory(
        id: 'pro.collaboration',
        icon: Icons.group_outlined,
        labelBuilder: _label,
        bodyBuilder: _body,
      );

      late CruxSettingsCategory converted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              converted = extra.toCategory(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(converted.id, 'pro.collaboration');
      expect(converted.icon, Icons.group_outlined);
    });
  });
}

String _label(BuildContext context) => 'Collaboration';

Widget _body(BuildContext context) => const Text('collab-body');
