// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accessibility guidelines for `crux_dock`, the panel model every product
/// in the suite uses.
///
/// ## Why this is the first one
///
/// A suite-wide audit graded accessibility **D** — the one quality dimension in
/// the suite that had never been started. Not "thin": *zero* accessibility
/// tests across nine repos, while `flutter_test` ships four guideline matchers
/// for free. Every other dimension here is guarded; this one was guarded by
/// nothing, which is how 22 interactive controls drifted to unlabelled without
/// anyone noticing.
///
/// `crux_dock` goes first because its blast radius is the largest: it is the
/// docking model in all four products, so one regression here reaches every
/// one of them.
///
/// ## What the four matchers actually check
///
/// * `androidTapTargetGuideline` — 48x48 dp minimum hit area.
/// * `iOSTapTargetGuideline` — 44x44 dp minimum.
/// * `textContrastGuideline` — WCAG AA contrast for rendered text.
/// * `labeledTapTargetGuideline` — every tappable node has a non-empty label.
///
/// The last one is the audit's finding rendered as a test: an `IconButton`
/// with neither `tooltip` nor a `Semantics` wrapper is announced as "button",
/// and nothing but a human reading the widget tree used to catch that.
///
/// ## Both themes, deliberately
///
/// Contrast is a property of the colour pair, not the widget, so a surface can
/// pass in light and fail in dark. Running each case twice costs almost
/// nothing and is the only way the assertion means what it appears to mean.
Widget _host(Widget child, {required Brightness brightness}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4650C8),
      brightness: brightness,
    ),
  ),
  home: Scaffold(body: SizedBox(width: 900, height: 500, child: child)),
);

CruxDockEntry _entry(String id, {VoidCallback? onClose}) => CruxDockEntry(
  id: id,
  icon: Icons.table_chart_outlined,
  label: 'Panel $id',
  onClose: onClose,
  // The content pane is the HOST's surface — crux_dock owns the strip and
  // renders whatever the host hands back. Excluded from semantics so this
  // guard measures the dock's own chrome rather than a placeholder: the first
  // run reported a 1.28:1 contrast ratio for the fixture's own `Text` and said
  // nothing at all about the dock. A guard that measures its own harness is
  // worse than no guard, because it looks like coverage.
  builder: (_) => const ExcludeSemantics(child: SizedBox.expand()),
);

void main() {
  for (final brightness in Brightness.values) {
    group('CruxDock accessibility (${brightness.name})', () {
      testWidgets('meets the tap-target, contrast and labelling guidelines', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [
                _entry('a', onClose: () {}),
                _entry('b', onClose: () {}),
              ],
              activeId: 'a',
              onSelect: (_) {},
            ),
            brightness: brightness,
          ),
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        handle.dispose();
      });

      testWidgets('a single pinned entry still meets them', (tester) async {
        // The charter's one-tab case renders as an auto-hiding titled header
        // rather than a one-tab bar, so it is a different widget tree and
        // needs its own assertion.
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            CruxDock(
              entries: [_entry('only')],
              activeId: 'only',
              onSelect: (_) {},
            ),
            brightness: brightness,
          ),
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        handle.dispose();
      });
    });
  }
}
