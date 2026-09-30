// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `statusBar.background` and `statusBar.foreground` are offered in Settings →
// Appearance and set by presets, theme packs and the editor-host theme
// bridge. They used to reach no widget, so an edit silently did nothing. Each
// test here sets a token to a colour nothing else uses, through the token
// editor's own write path (`applyOverrides`) into a MaterialApp built the way
// every product builds its own (`applyChromeTokens` over the active theme),
// and asserts the bar paints it. The last group pins the other half: an
// unedited preset paints exactly what the bar painted before the tokens were
// wired.

import 'dart:ui' as ui;

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _background = Color(0xFF3A1F5C);
const _foreground = Color(0xFFE8D25A);

const _boundaryKey = ValueKey<String>('statusBarBoundary');

ThemeData _seeded(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4650C8),
    brightness: brightness,
  ),
);

/// Pumps [bar] under a MaterialApp whose theme is rebuilt from
/// `cruxColorThemeProvider` through `applyChromeTokens`, as the products'
/// `app.dart` does.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget bar, {
  CruxColorTheme? preset,
  ThemeData Function(Brightness)? base,
  bool animate = false,
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
            themeAnimationStyle: animate ? null : AnimationStyle.noAnimation,
            theme: applyChromeTokens(
              (base ?? _seeded)(
                active.brightness,
              ).copyWith(extensions: [chrome]),
              chrome,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  RepaintBoundary(key: _boundaryKey, child: bar),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
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

Color? _barColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(CruxStatusBar),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

/// The distinct ARGB values the bar's layer renders.
Future<Set<int>> _renderedColors(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  final colors = <int>{};
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      colors.add(
        (bytes[i + 3] << 24) |
            (bytes[i] << 16) |
            (bytes[i + 1] << 8) |
            bytes[i + 2],
      );
    }
  });
  return colors;
}

const _bar = CruxStatusBar(
  segments: [CruxStatusSegment('cpu.v'), CruxStatusSegment('42 cells')],
);

void main() {
  group('CruxStatusBar paints the chrome theme', () {
    testWidgets('statusBar.background fills the bar', (tester) async {
      final container = await _pump(tester, _bar);
      expect(
        await _renderedColors(tester),
        isNot(contains(_background.toARGB32())),
      );

      await _edit(tester, container, {
        'chrome.${ChromeTokens.statusBarBackground}': _background,
      });

      expect(_barColor(tester), _background);
      expect(await _renderedColors(tester), contains(_background.toARGB32()));
    });

    testWidgets('statusBar.foreground colours every default segment', (
      tester,
    ) async {
      final container = await _pump(tester, _bar);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.statusBarForeground}': _foreground,
      });

      expect(_textColor(tester, 'cpu.v'), _foreground);
      expect(_textColor(tester, '42 cells'), _foreground);
      expect(await _renderedColors(tester), contains(_foreground.toARGB32()));
      // The `|` separator keeps the divider colour; it is not status text.
      expect(_textColor(tester, '|'), isNot(_foreground));
    });

    // A host that sizes its own segments (WaveCrux scales them for touch)
    // starts from resolveTextStyle, so the token must arrive there too.
    testWidgets('resolveTextStyle carries statusBar.foreground to hosts', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        CruxStatusBar(
          segments: [
            Builder(
              builder: (context) => Text(
                'host',
                style: CruxStatusBar.resolveTextStyle(
                  context,
                )?.copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
      );
      await _edit(tester, container, {
        'chrome.${ChromeTokens.statusBarForeground}': _foreground,
      });
      expect(_textColor(tester, 'host'), _foreground);
    });

    testWidgets('a theme change repaints the bar', (tester) async {
      final container = await _pump(tester, _bar);
      final surface = tester.renderObject<RenderDecoratedBox>(
        find
            .descendant(
              of: find.byType(CruxStatusBar),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      container.read(cruxColorThemeProvider.notifier).applyOverrides({
        'chrome.${ChromeTokens.statusBarBackground}': _background,
      });
      await tester.pump(Duration.zero, EnginePhase.layout);
      final requested = surface.debugNeedsPaint;
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(requested, isTrue);
      expect(await _renderedColors(tester), contains(_background.toARGB32()));

      // A preset switch repaints it back.
      container
          .read(cruxColorThemeProvider.notifier)
          .activate(defaultBuiltinPreset());
      await tester.pump();
      expect(
        await _renderedColors(tester),
        isNot(contains(_background.toARGB32())),
      );
    });

    testWidgets('the bar lands on the new colour through the theme animation', (
      tester,
    ) async {
      final container = await _pump(tester, _bar, animate: true);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.statusBarBackground}': _background,
      });
      expect(_barColor(tester), _background);
    });

    testWidgets('an explicit backgroundColor outranks the theme', (
      tester,
    ) async {
      const explicit = Color(0xFF0F5F2F);
      final container = await _pump(
        tester,
        const CruxStatusBar(
          backgroundColor: explicit,
          segments: [CruxStatusSegment('x')],
        ),
      );
      await _edit(tester, container, {
        'chrome.${ChromeTokens.statusBarBackground}': _background,
      });
      expect(_barColor(tester), explicit);
    });
  });

  // Before the tokens were wired the bar painted `surfaceContainerHighest`
  // behind `onSurface` at 75 %, read from whatever theme the product built
  // with `applyChromeTokens`. Every preset, over each kind of base a product
  // uses, must still paint exactly that. Text reaches the engine as 32-bit
  // ARGB, so its colour is compared that way.
  //
  // One text colour changed on purpose: Solarized Dark's, whose 75 % blend
  // was 3.76:1 against WCAG AA's 4.5:1, now paints its declared opaque
  // #93A1A1 (5.61:1). It is checked against that value instead.
  const textChangedOnPurpose = <String, Color>{
    'solarized-dark': Color(0xFF93A1A1),
  };
  group('an unedited preset paints what the bar always painted', () {
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
          await _pump(tester, _bar, preset: preset, base: base.value);
          final scheme = Theme.of(
            tester.element(find.byType(CruxStatusBar)),
          ).colorScheme;

          expect(_barColor(tester), scheme.surfaceContainerHighest);
          expect(
            _textColor(tester, 'cpu.v')?.toARGB32(),
            (textChangedOnPurpose[preset.id] ??
                    scheme.onSurface.withValues(alpha: 0.75))
                .toARGB32(),
          );
        });
      }
    }
  });
}
