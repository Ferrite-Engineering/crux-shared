// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite desktop menu bar for the EDACrux suite.
///
/// One declarative menu model, two renderers: the native macOS
/// `PlatformMenuBar` and the in-window VS Code-style Material menu bar on
/// Windows and Linux. Every product (WaveCrux, NetCrux, LintCrux, SimCrux)
/// supplies only its own layout table, label/shortcut lookups, and
/// visibility/enablement predicates — the ordering rules, separator grouping,
/// platform-idiomatic About/Settings/Quit placement, macOS application-menu
/// tail, Window menu, and native key-equivalent guard all live here so they
/// cannot drift apart per product again.
///
/// - `CruxDesktopMenuBar` — the widget every product's `DesktopMenuBar` wraps.
/// - `CruxMenuLayout` / `CruxAppMenuActions` — the declarative model.
/// - `cruxMenuLayoutActions` — the flattened action set each product's
///   conformance test compares against its menu-visible descriptor set.
/// - `nativeMenuShortcut` / `displayMenuShortcut` — the accelerator guards.
library;

export 'src/crux_desktop_menu_bar.dart';
export 'src/menu_layout.dart';
export 'src/menu_shortcut.dart';
