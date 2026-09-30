// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the muted help icon with the supplied tooltip and '
      'fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CruxHelpLink(
            url: 'https://wavecrux.app/docs/interface',
            tooltip: 'Learn more',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Learn more',
    );
    await tester.tap(find.byIcon(Icons.help_outline));
    expect(tapped, isTrue);
  });
}
