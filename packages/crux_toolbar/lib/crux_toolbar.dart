// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite application toolbar for the EDACrux suite.
///
/// One geometry token set, one button, one divider, one overflow strategy,
/// shared by WaveCrux, NetCrux, LintCrux and SimCrux. Each product supplies
/// only its own item lists and its `isEnabled` / `onAction` / `shortcutOf`
/// callbacks — everything structural lives here so the four toolbars cannot
/// drift apart again the moment someone adds a button.
///
/// - `CruxToolbar` — the `[common] │ [specific]` strip with a stable
///   auto-hiding overflow slot and a trailing edge fade.
/// - `CruxToolbarMetrics` — height / icon / button / divider tokens, desktop
///   and touch.
/// - `CruxToolbarItem` and its variants — the declarative item model.
/// - `CruxToolbarButton` / `CruxToolbarDivider` — the primitives.
/// - `CruxToolbarSplitButton` — a Photoshop-style grouped tool button, so a
///   cluster of related commands earns one slot instead of none.
/// - `CruxToolbarOverflowMenu` — the trailing three-dot affordance, and the
///   mobile stand-in for the menu bar Flutter does not bridge to iOS/Android.
/// - `CruxRunStopButton` — one control that morphs between Run and Cancel.
/// - `cruxToolbarTooltip` — label plus the user's *live* binding, so a
///   rebound shortcut can never make a tooltip lie.
library;

export 'src/crux_toolbar.dart';
export 'src/run_stop_button.dart';
export 'src/toolbar_button.dart';
export 'src/toolbar_item.dart';
export 'src/toolbar_metrics.dart';
export 'src/toolbar_overflow_menu.dart';
export 'src/toolbar_split_button.dart';
