// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `tabBar.background`, `tabBar.selected` and `tabBar.label` are offered in
// Settings → Appearance and set by presets, theme packs and the editor-host
// theme bridge. They used to reach no widget, so an edit silently did
// nothing. Each test sets a token to a colour nothing else uses, through the
// token editor's own write path (`applyOverrides`) into a MaterialApp built
// the way every product builds its own (`applyChromeTokens`), and asserts the
// document tab bar paints it. The last group pins the other half: an unedited
// preset paints exactly what the bar painted before the tokens were wired.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_theme/crux_theme.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _strip = Color(0xFF2B4A6F);
const _selected = Color(0xFF6F2B4A);
const _label = Color(0xFFF2C14E);

const _boundaryKey = ValueKey<String>('tabBarBoundary');

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'v': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['v'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

ThemeData _seeded(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4650C8),
    brightness: brightness,
  ),
);

void main() {
  late Directory tempDir;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_theme_');
    final service = WorkspaceService<String>(
      codec: const _StringCodec(),
      directoryFactory: () async => tempDir,
      logger: (_) {},
    );
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        );
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Pumps a two-tab bar ('alpha' behind, 'beta' active) under a MaterialApp
  /// whose theme is rebuilt from `cruxColorThemeProvider` through
  /// `applyChromeTokens`, as the products' `app.dart` does.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    CruxColorTheme? preset,
    ThemeData Function(Brightness)? base,
  }) async {
    final container = ProviderContainer(
      overrides: [
        cruxColorThemeProvider.overrideWith(
          () =>
              CruxColorThemeNotifier(initial: preset ?? defaultBuiltinPreset()),
        ),
      ],
    );
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    await notifier.openTab(displayName: 'alpha', payload: 'a');
    await notifier.openTab(displayName: 'beta', payload: 'b');

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
                body: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: ViewerTabBar<String>(
                      paneId: ws.activePaneId,
                      provider: provider,
                    ),
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

  Future<void> edit(
    WidgetTester tester,
    ProviderContainer container,
    Map<String, Color> overrides,
  ) async {
    container.read(cruxColorThemeProvider.notifier).applyOverrides(overrides);
    await tester.pumpAndSettle();
  }

  Color? stripColor(WidgetTester tester) {
    final strip = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(ViewerTabBar<String>),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (strip.decoration as BoxDecoration).color;
  }

  Color? chipColor(WidgetTester tester, String title) {
    final chip = tester.widget<Container>(
      find
          .ancestor(of: find.text(title), matching: find.byType(Container))
          .first,
    );
    return (chip.decoration! as BoxDecoration).color;
  }

  TextStyle? titleStyle(WidgetTester tester, String title) =>
      tester.widget<Text>(find.text(title)).style;

  Future<Set<int>> renderedColors(WidgetTester tester) async {
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

  group('ViewerTabBar paints the chrome theme', () {
    testWidgets('tabBar.background fills the strip', (tester) async {
      final container = await pump(tester);
      expect(stripColor(tester), isNull);

      await edit(tester, container, {
        'chrome.${ChromeTokens.tabBarBackground}': _strip,
      });
      expect(stripColor(tester), _strip);
      expect(await renderedColors(tester), contains(_strip.toARGB32()));
    });

    testWidgets('tabBar.selected fills the active tab only', (tester) async {
      final container = await pump(tester);
      await edit(tester, container, {
        'chrome.${ChromeTokens.tabBarSelected}': _selected,
      });
      expect(chipColor(tester, 'beta'), _selected);
      expect(chipColor(tester, 'alpha'), isNull);
      expect(await renderedColors(tester), contains(_selected.toARGB32()));
    });

    testWidgets('tabBar.label colours every tab title', (tester) async {
      final container = await pump(tester);
      await edit(tester, container, {
        'chrome.${ChromeTokens.tabBarLabel}': _label,
      });
      expect(titleStyle(tester, 'beta')?.color, _label);
      expect(titleStyle(tester, 'alpha')?.color, _label);
      expect(await renderedColors(tester), contains(_label.toARGB32()));
    });

    testWidgets('a theme change repaints the bar', (tester) async {
      final container = await pump(tester);
      await edit(tester, container, {
        'chrome.${ChromeTokens.tabBarBackground}': _strip,
        'chrome.${ChromeTokens.tabBarSelected}': _selected,
        'chrome.${ChromeTokens.tabBarLabel}': _label,
      });
      final painted = await renderedColors(tester);
      expect(
        painted,
        containsAll([
          _strip.toARGB32(),
          _selected.toARGB32(),
          _label.toARGB32(),
        ]),
      );

      container
          .read(cruxColorThemeProvider.notifier)
          .activate(defaultBuiltinPreset());
      await tester.pumpAndSettle();
      final after = await renderedColors(tester);
      expect(after, isNot(contains(_strip.toARGB32())));
      expect(after, isNot(contains(_selected.toARGB32())));
      expect(after, isNot(contains(_label.toARGB32())));
    });
  });

  // Before the tokens were wired the strip had no fill, the active tab was
  // `surfaceContainerHighest` and every title took `bodyMedium`'s colour, all
  // from whatever theme the product built with `applyChromeTokens`. Every
  // preset, over each kind of base a product uses, must still paint exactly
  // that.
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
          await pump(tester, preset: preset, base: base.value);
          final theme = Theme.of(tester.element(find.text('beta')));

          expect(stripColor(tester), isNull);
          expect(
            chipColor(tester, 'beta'),
            theme.colorScheme.surfaceContainerHighest,
          );
          expect(chipColor(tester, 'alpha'), isNull);
          expect(titleStyle(tester, 'beta'), theme.textTheme.bodyMedium);
          expect(titleStyle(tester, 'alpha'), theme.textTheme.bodyMedium);
        });
      }
    }
  });
}
