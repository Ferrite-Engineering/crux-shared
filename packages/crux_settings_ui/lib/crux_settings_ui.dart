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
/// `CruxFormRow` / `CruxFormSection` are the desktop form rows every
/// Settings tile and dialog form is built from: label left, control right,
/// the label as the control's accessible name (and its click target for a
/// switch or checkbox), help text below.
///
/// The host product supplies the category list
/// (`CruxSettingsCategory`) and wires the panel into its own dialog / route
/// chrome. Nothing here knows about any product domain (waveforms, netlists,
/// …); all labels and content arrive via constructor parameters.
library;

export 'src/crux_auto_reload_setting_tile.dart';
export 'src/crux_form_row.dart'
    hide kCruxFormLabelWidth, kCruxFormSpreadControlMaxWidth;
export 'src/crux_locale_setting_tile.dart' hide kCruxSupportedLocales;
export 'src/crux_policy_lock.dart';
export 'src/crux_policy_lock_note.dart';
export 'src/crux_settings_card.dart';
export 'src/crux_settings_category.dart';
export 'src/crux_settings_control_tile.dart';
export 'src/crux_settings_extra_category.dart';
export 'src/crux_settings_master_detail.dart';
export 'src/crux_settings_section_card.dart';
export 'src/crux_settings_shell.dart';
export 'src/crux_settings_slider_tile.dart' hide kCruxSettingsSliderWidth;
