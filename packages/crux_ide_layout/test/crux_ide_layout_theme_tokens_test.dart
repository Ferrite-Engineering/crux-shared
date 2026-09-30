// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `splitter` and `splitter.hover` are offered in Settings → Appearance and set
// by presets, theme packs and the editor-host theme bridge. They used to reach
// no widget, so an edit silently did nothing. Each test sets a token to a
// colour nothing else uses, through the token editor's own write path
// (`applyOverrides`) into a MaterialApp built the way every product builds its
// own (`applyChromeTokens`), and asserts the pane resizer paints it. The last
// group pins the other half: an unedited preset paints exactly what the
// resizers painted before the tokens were wired.

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';
// The resizer is what paints; `panes` does not export it.
import 'package:panes/src/resizer.dart' show Resizer;

const _rest = Color(0xFF7A3E1D);
const _active = Color(0xFF1DD3B0);

class _Layout implements IdePanelLayout {
  @override
  bool get leftVisible => true;
  @override
  bool get rightVisible => false;
  @override
  bool get bottomVisible => false;
  @override
  PaneSize? get leftSize => PaneSize.pixel(200);
  @override
  PaneSize? get rightSize => null;
  @override
  PaneSize? get bottomSize => null;
}

class _Sink implements IdePanelLayoutSink {
  @override
  void setLeftVisible({required bool visible}) {}
  @override
  void setRightVisible({required bool visible}) {}
  @override
  void setBottomVisible({required bool visible}) {}
  @override
  void setLeftSize(double pixels) {}
  @override
  void setRightSize(double pixels) {}
  @override
  void setBottomSize(double pixels) {}
}

ThemeData _seeded(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4650C8),
    brightness: brightness,
  ),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CruxColorTheme? preset,
  ThemeData Function(Brightness)? base,
  CruxIdeLayoutTheme layoutTheme = const CruxIdeLayoutTheme(),
}) async {
  final container = ProviderContainer(
    overrides: [
      cruxColorThemeProvider.overrideWith(
        () => CruxColorThemeNotifier(initial: preset ?? defaultBuiltinPreset()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final active = ref.watch(cruxColorThemeProvider);
          final chrome = CruxThemeExtension(theme: active);
          return MaterialApp(
            themeAnimationStyle: AnimationStyle.noAnimation,
            theme: applyChromeTokens(
              (base ?? _seeded)(
                active.brightness,
              ).copyWith(extensions: [chrome]),
              chrome,
            ),
            home: Scaffold(
              body: CruxIdeLayout(
                layout: _Layout(),
                sink: _Sink(),
                theme: layoutTheme,
                leftBuilder: (_, _) => const SizedBox.expand(),
                centerBuilder: (_, _) => const SizedBox.expand(),
                rightBuilder: (_, _) => const SizedBox.expand(),
                bottomBuilder: (_, _) => const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _edit(
  WidgetTester tester,
  ProviderContainer container,
  Map<String, Color> overrides,
) async {
  container.read(cruxColorThemeProvider.notifier).applyOverrides(overrides);
  await tester.pumpAndSettle();
}

final Finder _resizer = find.byType(Resizer).first;

/// The colour of the resizer's visible bar: the second of its three nested
/// containers (hit area, bar, inner line).
Color? _barColor(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(of: _resizer, matching: find.byType(Container)),
    )
    .elementAt(1)
    .color;

PaneThemeData _paneTheme(WidgetTester tester) =>
    tester.widget<PaneTheme>(find.byType(PaneTheme)).data;

Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(_resizer));
  await tester.pump();
  return mouse;
}

void main() {
  group('CruxIdeLayout resizers paint the chrome theme', () {
    testWidgets('splitter colours the resting resizer', (tester) async {
      final container = await _pump(tester);
      expect(_barColor(tester), isNot(_rest));

      await _edit(tester, container, {
        'chrome.${ChromeTokens.splitter}': _rest,
      });
      expect(_barColor(tester), _rest);
    });

    testWidgets('splitter.hover colours the hovered resizer', (tester) async {
      final container = await _pump(tester);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.splitterHover}': _active,
      });
      expect(_barColor(tester), isNot(_active), reason: 'at rest');

      await _hover(tester);
      expect(_barColor(tester), _active);
    });

    testWidgets('splitter.hover also marks a focused resizer', (tester) async {
      final container = await _pump(tester);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.splitterHover}': _active,
      });
      expect(_paneTheme(tester).resizerHoverColor, _active);
      expect(_paneTheme(tester).resizerFocusedColor, _active);
    });

    testWidgets('a theme change repaints the resizer', (tester) async {
      final container = await _pump(tester);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.splitter}': _rest,
      });
      expect(_barColor(tester), _rest);

      container
          .read(cruxColorThemeProvider.notifier)
          .activate(defaultBuiltinPreset());
      await tester.pumpAndSettle();
      final scheme = Theme.of(tester.element(_resizer)).colorScheme;
      expect(_barColor(tester), scheme.outlineVariant);
    });

    // A host that passes its own resizer colours opts out of the theme's.
    testWidgets('explicit CruxIdeLayoutTheme colours outrank the theme', (
      tester,
    ) async {
      const explicit = Color(0xFF445566);
      final container = await _pump(
        tester,
        layoutTheme: const CruxIdeLayoutTheme(
          resizerColor: explicit,
          resizerHoverColor: explicit,
          resizerFocusedColor: explicit,
        ),
      );
      await _edit(tester, container, {
        'chrome.${ChromeTokens.splitter}': _rest,
        'chrome.${ChromeTokens.splitterHover}': _active,
      });
      expect(_barColor(tester), explicit);
      expect(_paneTheme(tester).resizerHoverColor, explicit);
      expect(_paneTheme(tester).resizerFocusedColor, explicit);
    });
  });

  // Before the tokens were wired the resizers painted `outlineVariant` at rest
  // and `primary` on hover, drag and focus, from whatever theme the product
  // built with `applyChromeTokens`. Every preset, over each kind of base a
  // product uses, must still paint exactly that.
  group('an unedited preset paints what the resizers always painted', () {
    final bases = <String, ThemeData Function(Brightness)>{
      'seeded': _seeded,
      'high-contrast': (b) => ThemeData(
        colorScheme: b == Brightness.dark
            ? const ColorScheme.highContrastDark()
            : const ColorScheme.highContrastLight(),
      ),
    };
    for (final preset in builtinPresets().values) {
      for (final base in bases.entries) {
        testWidgets('${preset.id} over a ${base.key} base', (tester) async {
          await _pump(tester, preset: preset, base: base.value);
          final scheme = Theme.of(tester.element(_resizer)).colorScheme;

          expect(_barColor(tester), scheme.outlineVariant);
          expect(_paneTheme(tester).resizerHoverColor, scheme.primary);
          expect(_paneTheme(tester).resizerFocusedColor, scheme.primary);
          await _hover(tester);
          expect(_barColor(tester), scheme.primary);
        });
      }
    }
  });
}
