// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `toolbar.iconActive` is offered in Settings → Appearance and set by presets,
// theme packs and the editor-host theme bridge. It used to reach no widget, so
// an edit silently did nothing. These tests set it to a colour nothing else
// uses, through the token editor's own write path (`applyOverrides`) into a
// MaterialApp built the way every product builds its own
// (`applyChromeTokens`), and assert a toggled-on button's glyph paints it. The
// last group pins the other half: an unedited preset tints a toggled-on glyph
// exactly as before the token was wired.

import 'dart:ui' as ui;

import 'package:crux_theme/crux_theme.dart';
import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

enum _A { open, crossProbe, pinned, zoomIn, zoomOut }

const _activeTint = Color(0xFFD9480F);
const _boundaryKey = ValueKey<String>('toolbarBoundary');

ThemeData _seeded(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4650C8),
    brightness: brightness,
  ),
);

const _items = <CruxToolbarItem<_A>>[
  CruxToolbarButtonItem(action: _A.open, icon: Icons.folder, tooltip: 'Open'),
  // The cross-probe toggle, on: every product has one.
  CruxToolbarButtonItem(
    action: _A.crossProbe,
    icon: Icons.sensors_outlined,
    selectedIcon: Icons.sensors,
    tooltip: 'Cross-probe',
    isSelected: true,
  ),
  // On, but shown by its glyph alone.
  CruxToolbarButtonItem(
    action: _A.pinned,
    icon: Icons.push_pin_outlined,
    selectedIcon: Icons.push_pin,
    tooltip: 'Pinned',
    isSelected: true,
    tintWhenSelected: false,
  ),
  // A split button whose face is on renders through the same button.
  CruxToolbarSplitItem(
    id: 'zoom',
    tooltip: 'Zoom',
    variants: [
      CruxToolbarButtonItem(
        action: _A.zoomIn,
        icon: Icons.zoom_in,
        tooltip: 'Zoom in',
        isSelected: true,
      ),
      CruxToolbarButtonItem(
        action: _A.zoomOut,
        icon: Icons.zoom_out,
        tooltip: 'Zoom out',
      ),
    ],
  ),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CruxColorTheme? preset,
  ThemeData Function(Brightness)? base,
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
              body: RepaintBoundary(
                key: _boundaryKey,
                child: CruxToolbar<_A>(
                  common: _items,
                  specific: const [],
                  isEnabled: (_) => true,
                  onAction: (_) {},
                  shortcutOf: (_) => null,
                  semanticsLabel: 'Toolbar',
                ),
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

Color? _glyphColor(WidgetTester tester, _A action) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byKey(ValueKey<_A>(action)),
        matching: find.byType(Icon),
      ),
    )
    .color;

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

void main() {
  group('CruxToolbar paints the chrome theme', () {
    testWidgets('toolbar.iconActive tints a toggled-on glyph', (tester) async {
      final container = await _pump(tester);
      expect(
        await _renderedColors(tester),
        isNot(contains(_activeTint.toARGB32())),
      );

      await _edit(tester, container, {
        'chrome.${ChromeTokens.toolbarIconActive}': _activeTint,
      });

      expect(_glyphColor(tester, _A.crossProbe), _activeTint);
      expect(await _renderedColors(tester), contains(_activeTint.toARGB32()));
    });

    testWidgets('toolbar.iconActive reaches a split button face', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.toolbarIconActive}': _activeTint,
      });
      expect(_glyphColor(tester, _A.zoomIn), _activeTint);
    });

    testWidgets('an off button, or one that opts out of the tint, is left '
        'alone', (tester) async {
      final container = await _pump(tester);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.toolbarIconActive}': _activeTint,
      });
      expect(_glyphColor(tester, _A.open), isNull);
      expect(_glyphColor(tester, _A.pinned), isNull);
    });

    testWidgets('a theme change repaints the glyph', (tester) async {
      final container = await _pump(tester);
      await _edit(tester, container, {
        'chrome.${ChromeTokens.toolbarIconActive}': _activeTint,
      });
      expect(await _renderedColors(tester), contains(_activeTint.toARGB32()));

      container
          .read(cruxColorThemeProvider.notifier)
          .activate(defaultBuiltinPreset());
      await tester.pumpAndSettle();
      expect(
        await _renderedColors(tester),
        isNot(contains(_activeTint.toARGB32())),
      );
      final scheme = Theme.of(
        tester.element(find.byKey(const ValueKey<_A>(_A.crossProbe))),
      ).colorScheme;
      expect(_glyphColor(tester, _A.crossProbe), scheme.primary);
    });
  });

  // Before the token was wired a toggled-on glyph was tinted `primary`, from
  // whatever theme the product built with `applyChromeTokens`. Every preset,
  // over each kind of base a product uses, must still tint it exactly that.
  group('an unedited preset tints what the toolbar always tinted', () {
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
          final scheme = Theme.of(
            tester.element(find.byKey(const ValueKey<_A>(_A.crossProbe))),
          ).colorScheme;
          expect(_glyphColor(tester, _A.crossProbe), scheme.primary);
          expect(_glyphColor(tester, _A.zoomIn), scheme.primary);
          expect(_glyphColor(tester, _A.open), isNull);
        });
      }
    }
  });
}
