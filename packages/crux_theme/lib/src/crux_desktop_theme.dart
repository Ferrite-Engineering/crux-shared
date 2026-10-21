// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxDesktopTokens;
import 'package:crux_theme/src/crux_focus_ring_borders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Whether a host gets the Crux Desktop layer: macOS, Windows, Linux and
/// every web build get it at any window size; iOS and Android keep the
/// product's Material 3 theme.
///
/// Keyed on the host platform, never on the window size: a desktop window
/// narrowed below a phone's width is still a desktop window, and a theme
/// keyed on size would swap every control mid-resize.
bool cruxUsesDesktopLayer({TargetPlatform? platform, bool isWeb = kIsWeb}) {
  if (isWeb) return true;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => false,
  };
}

/// The one place a product's theme is chosen: [cruxDesktopTheme] over
/// [colorScheme] where [cruxUsesDesktopLayer] says so, else [mobile] (the
/// product's existing phone and tablet theme, built on demand).
///
/// Call it once per `MaterialApp` theme slot (light, dark, and the two
/// high-contrast slots), then layer the product's own extensions and
/// `applyChromeTokens` on the result.
ThemeData cruxThemeForDevice({
  required ColorScheme colorScheme,
  required bool highContrast,
  required ThemeData Function() mobile,
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  if (!cruxUsesDesktopLayer(platform: platform, isWeb: isWeb)) return mobile();
  return cruxDesktopTheme(colorScheme, highContrast: highContrast);
}

/// The Crux Desktop `ThemeData` over [scheme]: every component theme set to
/// the desktop tokens, so a stock Material control reads as a desktop
/// control without a per-site change.
///
/// - **Size.** Buttons, text fields, dropdowns and icon buttons are 28 px;
///   segmented buttons 26 px; list rows 24 px single line. Three tokens are
///   below what a theme can reach on the stock widget, so the theme gets as
///   close as the widget allows and the rest is a usage rule: a chip has a
///   32 px floor less the density adjustment (it renders 30 px, not 22); a
///   two-line list holds each row at `CruxDesktopTokens.twoLineRowHeight`
///   (40 px) itself, because a dense two-line `ListTile` sizes to its text
///   and a theme `minTileHeight` would also raise the single-line rows; and
///   a checkbox
///   or radio paints its 18 px box in a shrink-wrapped 24 px hit area.
/// - **Shape.** 4 px controls, 6 px menus, toasts and cards (a card is a
///   group box, `CruxDesktopTokens.groupRadius`), 8 px dialogs. Surfaces
///   are a 1 px `outlineVariant` border with one shadow; `surfaceTint` is
///   transparent, so elevation never tints.
/// - **Type.** 13 px body, 12 px secondary, 14 px semibold titles, in the
///   operating system's UI font: no `fontFamily` is set. Products that use a
///   monospace face for technical values (signal values, times, paths) set
///   those text slots themselves, after this.
///   Values and menu items are regular weight. Material's `DropdownButton`
///   draws its value in `titleMedium`, the heading slot, which no theme can
///   lighten without lightening every heading: the desktop replacement is
///   `CruxPopUpButton`.
/// - **Feedback.** Hover and pressed overlays, no ink ripple. A filled
///   (accent) button darkens on hover and press in both brightnesses. The
///   outlined button is the neutral secondary button: `onSurface` text on a
///   flat face, never the accent.
/// - **Focus.** On keyboard focus, the ring the owned controls draw
///   (`CruxFocusRing`): a primary stroke, 1.5 px or 2.5 px when
///   [highContrast], 2 px outside the control. Buttons draw it through their
///   shape ([CruxFocusRingShape]), text fields through their focused border
///   ([CruxFocusRingInputBorder]), so it never moves layout.
/// - **Scrim.** 18 % black behind a blocking dialog.
///
/// The result carries [CruxDesktopTokens]. Colour stays the product's: its
/// seed, surfaces and canvas tokens arrive through [scheme], and
/// `applyChromeTokens` still layers theme-pack chrome colours on top. A
/// product adding its own extensions keeps this one:
/// `theme.copyWith(extensions: [...theme.extensions.values, mine])`.
ThemeData cruxDesktopTheme(ColorScheme scheme, {required bool highContrast}) {
  final tokens = highContrast
      ? const CruxDesktopTokens.highContrast()
      : const CruxDesktopTokens();
  final colorScheme = scheme.copyWith(surfaceTint: Colors.transparent);
  final isDark = colorScheme.brightness == Brightness.dark;
  final ring = tokens.focusRingWidth;
  final controlRadius = BorderRadius.circular(tokens.controlRadius);
  final menuRadius = BorderRadius.circular(tokens.menuRadius);
  final disabled = colorScheme.onSurface.withValues(alpha: 0.38);

  // The platform's own typography (its UI font and colours) under the desktop
  // sizes, merged here rather than left to ThemeData, so the component
  // styles below are built from the same styles the text theme ends up with.
  final typography = Typography.material2021(
    platform: defaultTargetPlatform,
    colorScheme: colorScheme,
  );
  final platformText = isDark ? typography.white : typography.black;
  final textTheme = platformText.merge(
    TextTheme(
      displayLarge: const TextStyle(fontSize: 32, fontWeight: FontWeight.w400),
      displayMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
      displaySmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w400),
      headlineLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
      headlineMedium: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      headlineSmall: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      titleLarge: TextStyle(
        fontSize: tokens.titleFontSize,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        fontSize: tokens.titleFontSize,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        fontSize: tokens.bodyFontSize,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(fontSize: tokens.bodyFontSize),
      bodyMedium: TextStyle(fontSize: tokens.bodyFontSize),
      bodySmall: TextStyle(fontSize: tokens.secondaryFontSize),
      labelLarge: TextStyle(
        fontSize: tokens.bodyFontSize,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontSize: tokens.secondaryFontSize,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    ),
  );
  final body = textTheme.bodyMedium;

  // Hover and pressed overlays, the same on every button family.
  WidgetStateProperty<Color?> overlay(Color base) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return base.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return base.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.focused)) {
          return base.withValues(alpha: 0.06);
        }
        return null;
      });

  // The keyboard-focus ring: the shape the owned controls draw with
  // `CruxFocusRing`, a [ring] px primary stroke 2 px outside the control,
  // painted by the button's shape so it stays out of layout. The control's
  // own border is unchanged under it.
  final focusRing = BorderSide(color: colorScheme.primary, width: ring);
  WidgetStateProperty<OutlinedBorder?> focusShape() =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused) &&
            !states.contains(WidgetState.disabled)) {
          return CruxFocusRingShape(
            ring: focusRing,
            borderRadius: controlRadius,
          );
        }
        return RoundedRectangleBorder(borderRadius: controlRadius);
      });

  ButtonStyle buttonStyle({
    required Color overlayBase,
    WidgetStateProperty<BorderSide?>? side,
    WidgetStateProperty<Color?>? foregroundColor,
    WidgetStateProperty<Color?>? backgroundColor,
    double minWidth = 64,
  }) => ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(minWidth, tokens.controlHeight)),
    fixedSize: WidgetStatePropertyAll(Size.fromHeight(tokens.controlHeight)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12),
    ),
    shape: focusShape(),
    textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
    overlayColor: overlay(overlayBase),
    side: side,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    elevation: const WidgetStatePropertyAll(0),
  );

  // A neutral push button's face: white with a border in light (it reads as
  // a button on Windows, GNOME, KDE and macOS alike), the highest container
  // in dark.
  final neutralFace = isDark
      ? colorScheme.surfaceContainerHighest
      : colorScheme.surfaceContainerLowest;

  final outlineBorder = OutlineInputBorder(
    borderRadius: controlRadius,
    borderSide: BorderSide(color: colorScheme.outlineVariant),
  );
  // Keyboard focus on a field: the primary outline plus the shared ring.
  final focusedField = CruxFocusRingInputBorder(
    borderRadius: controlRadius,
    borderSide: BorderSide(color: colorScheme.primary),
    ring: focusRing,
  );
  // Values and menu items are regular weight, whatever the platform
  // typography's body weight.
  final value = body?.copyWith(fontWeight: FontWeight.w400);

  final menuSurface = isDark
      ? colorScheme.surfaceContainerHighest
      : colorScheme.surface;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
    focusColor: colorScheme.primary.withValues(alpha: 0.12),

    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      toolbarHeight: 40,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
    ),

    // 1 px panel separators.
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // A card is a group box: one step above a control's radius, the same
      // as a menu's (`CruxDesktopTokens.groupRadius`).
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.groupRadius),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
    ),

    // 24 px single-line rows, 40 px two-line.
    listTileTheme: ListTileThemeData(
      dense: true,
      // Standard density, so `minTileHeight` is the height: a density
      // adjustment would be subtracted from it.
      visualDensity: VisualDensity.standard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minVerticalPadding: 2,
      minTileHeight: tokens.rowHeight,
      minLeadingWidth: 20,
      horizontalTitleGap: 8,
      iconColor: colorScheme.onSurface.withValues(alpha: 0.7),
      titleTextStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
      ),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),

    iconTheme: IconThemeData(
      size: 18,
      color: colorScheme.onSurface.withValues(alpha: 0.8),
    ),

    // 28 px fields, 13 px text, label-left forms: no floating label. The
    // fill is a neutral control's face, so a field and a pop-up button side
    // by side match (white in light, the highest container in dark).
    inputDecorationTheme: InputDecorationThemeData(
      isDense: true,
      constraints: BoxConstraints(minHeight: tokens.controlHeight),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      // A search glyph inside a field keeps the field at 28 px rather than
      // the 48 px touch box an icon slot defaults to.
      prefixIconConstraints: BoxConstraints.tightFor(
        width: tokens.controlHeight,
        height: tokens.controlHeight,
      ),
      suffixIconConstraints: BoxConstraints.tightFor(
        width: tokens.controlHeight,
        height: tokens.controlHeight,
      ),
      border: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: outlineBorder,
      disabledBorder: outlineBorder,
      focusedBorder: focusedField,
      errorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: CruxFocusRingInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: colorScheme.error),
        ring: BorderSide(color: colorScheme.error, width: ring),
      ),
      filled: true,
      fillColor: neutralFace,
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: tokens.bodyFontSize,
      ),
      helperStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: tokens.secondaryFontSize,
      ),
      errorStyle: TextStyle(
        color: colorScheme.error,
        fontSize: tokens.secondaryFontSize,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: buttonStyle(overlayBase: colorScheme.primary, minWidth: 48),
    ),
    // The accent face darkens on hover and press in both brightnesses:
    // black over the light theme's dark accent, the dark on-primary over the
    // dark theme's light accent. A white overlay would lighten a pressed
    // light-theme button.
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle(
        overlayBase: isDark ? colorScheme.onPrimary : Colors.black,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: buttonStyle(overlayBase: colorScheme.primary),
    ),
    // The secondary push button (Browse…, Cancel beside a primary): neutral,
    // never accent-coloured. The (c) normal button: a flat face, a 1 px
    // outlineVariant border lifting to outline on hover and press.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle(
        overlayBase: colorScheme.onSurface,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? disabled
              : colorScheme.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? neutralFace.withValues(alpha: neutralFace.a * 0.5)
              : neutralFace,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            );
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return BorderSide(
              color: highContrast ? colorScheme.onSurface : colorScheme.outline,
            );
          }
          return BorderSide(
            color: highContrast
                ? colorScheme.outline
                : colorScheme.outlineVariant,
          );
        }),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(
          Size.square(tokens.controlHeight),
        ),
        maximumSize: WidgetStatePropertyAll(
          Size.square(tokens.controlHeight),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        iconSize: const WidgetStatePropertyAll(18),
        shape: focusShape(),
        overlayColor: overlay(colorScheme.onSurface),
        // The size above is the size: a density adjustment would take
        // another 8 px off it.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
        fixedSize: const WidgetStatePropertyAll(Size.fromHeight(26)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: controlRadius),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        overlayColor: overlay(colorScheme.onSurface),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colorScheme.primary, width: ring);
          }
          return BorderSide(color: colorScheme.outline);
        }),
        // SegmentedButton sizes itself as 40 px plus the density
        // adjustment and ignores minimumSize and fixedSize, so 26 px is
        // reached through density: 40 + 4 x -3.5.
        visualDensity: const VisualDensity(horizontal: -2, vertical: -3.5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: controlRadius,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      side: BorderSide(color: colorScheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      labelStyle: textTheme.labelMedium,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      iconTheme: const IconThemeData(size: 14),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: value,
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        constraints: BoxConstraints.tightFor(height: tokens.controlHeight),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: focusedField,
        filled: true,
        fillColor: neutralFace,
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuSurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: menuRadius,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashRadius: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: colorScheme.primary, width: ring + 0.5);
        }
        if (states.contains(WidgetState.selected)) {
          return BorderSide(color: colorScheme.primary, width: 1.5);
        }
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: disabled, width: 1.5);
        }
        return BorderSide(color: colorScheme.outline, width: 1.5);
      }),
      overlayColor: overlay(colorScheme.onSurface),
    ),
    radioTheme: RadioThemeData(
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashRadius: 0,
      overlayColor: overlay(colorScheme.onSurface),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return colorScheme.onSurface.withValues(alpha: 0.4);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary.withValues(alpha: 0.3);
        }
        return colorScheme.onSurface.withValues(alpha: 0.15);
      }),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashRadius: 0,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      thumbColor: colorScheme.primary,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: colorScheme.onSurfaceVariant,
      collapsedIconColor: colorScheme.onSurfaceVariant,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowHeight: 28,
      dataRowMinHeight: 24,
      dataRowMaxHeight: 28,
      horizontalMargin: 8,
      columnSpacing: 16,
      headingTextStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      dataTextStyle: textTheme.bodyMedium,
      dividerThickness: 1,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      barrierColor: tokens.scrimColor,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.dialogRadius),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: colorScheme.onSurface,
      ),
      contentTextStyle: body?.copyWith(color: colorScheme.onSurfaceVariant),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.surfaceContainerHighest,
      contentTextStyle: body?.copyWith(color: colorScheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: menuRadius,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      width: tokens.toastMaxWidth,
      elevation: 6,
    ),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        colorScheme.onSurface.withValues(alpha: isDark ? 0.3 : 0.2),
      ),
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(2),
      crossAxisMargin: 2,
    ),

    // Compact dark tooltips, the same in both brightnesses for legibility.
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35),
        borderRadius: controlRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      textStyle: textTheme.bodySmall?.copyWith(
        color: const Color(0xFFE1E1E8),
      ),
      waitDuration: const Duration(milliseconds: 600),
      showDuration: const Duration(seconds: 4),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: menuSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: menuRadius,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      textStyle: value?.copyWith(color: colorScheme.onSurface),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => value?.copyWith(
          color: states.contains(WidgetState.disabled)
              ? disabled
              : colorScheme.onSurface,
        ),
      ),
    ),

    // The in-window menu bar on Windows and Linux (macOS draws its own and
    // ignores this): a flat, full-bleed strip with regular-weight 13 px
    // items and a clear hover.
    menuBarTheme: MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 4),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(value),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabled;
          return colorScheme.onSurface;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabled;
          return colorScheme.onSurface.withValues(alpha: 0.8);
        }),
        // A clearly visible hover and focus fill: Material's default overlay
        // is nearly invisible on a dark surface.
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return colorScheme.onSurface.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return colorScheme.onSurface.withValues(alpha: 0.08);
          }
          return null;
        }),
        // Keyboard-focused menu items get the primary frame, so arrow-key
        // traversal is obvious; the pointer relies on the fill above.
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: colorScheme.primary, width: ring);
          }
          return BorderSide.none;
        }),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
        visualDensity: VisualDensity.compact,
        alignment: Alignment.centerLeft,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuSurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: menuRadius,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    ),

    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}
