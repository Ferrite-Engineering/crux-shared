// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite Settings panel shell for the EDACrux suite.
///
/// Provides the domain-neutral *chrome* of a Settings panel — the
/// responsive master-detail layout (`CruxSettingsMasterDetail`, a category
/// rail beside a scrolling detail pane that collapses to a list → detail
/// single column on narrow viewports) plus the grouped-row building blocks
/// (`CruxSettingsCard`, `CruxSettingsControlTile`, `CruxSettingsSliderTile`)
/// used to compose each category's content.
///
/// The host product supplies the category list
/// (`CruxSettingsCategory`) and wires the panel into its own dialog / route
/// chrome. Nothing here knows about any product domain (waveforms, netlists,
/// …); all labels and content arrive via constructor parameters.
library;

export 'src/crux_auto_reload_setting_tile.dart';
export 'src/crux_locale_setting_tile.dart';
export 'src/crux_policy_lock_note.dart';
export 'src/crux_settings_card.dart';
export 'src/crux_settings_category.dart';
export 'src/crux_settings_control_tile.dart';
export 'src/crux_settings_extra_category.dart';
export 'src/crux_settings_master_detail.dart';
export 'src/crux_settings_section_card.dart';
export 'src/crux_settings_shell.dart';
export 'src/crux_settings_slider_tile.dart';
