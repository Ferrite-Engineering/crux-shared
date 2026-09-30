// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accessibility guidelines for `crux_status_bar`.
///
/// A suite-wide audit found ZERO accessibility tests
/// across nine repos, while `flutter_test` ships four guideline matchers for
/// free. Every other quality dimension in this estate is guarded; this one was
/// guarded by nothing.
///
/// The status bar is the suite's densest text surface — small type, muted
/// colours, one shared model across four products — which makes it the most
/// likely place for a contrast regression to land and the least likely place
/// for anyone to notice by eye.
///
/// Contrast is asserted in **both themes** because it is a property of the
/// colour pair, not the widget: a surface can pass in light and fail in dark,
/// and the suite ships both.
Widget _host(Widget child, {required Brightness brightness}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4650C8),
      brightness: brightness,
    ),
  ),
  home: Scaffold(
    body: Column(children: <Widget>[const Spacer(), child]),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    group('CruxStatusBar accessibility (${brightness.name})', () {
      testWidgets('segments meet the contrast and tap-target guidelines', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            const CruxStatusBar(
              segments: <Widget>[
                CruxStatusSegment('File: cpu.v'),
                CruxStatusSegment('Signals: 1,284'),
                CruxStatusSegment('Cursor: 2,575 ns'),
              ],
            ),
            brightness: brightness,
          ),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

        handle.dispose();
      });
    });
  }
}
