// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Browsable categories used to group `CruxAction` values in each product's
/// desktop menu bar, mobile overflow action menu, and (optionally) command
/// palette.
///
/// `app` is the host-application menu — on macOS / iPadOS the FIRST menu in
/// `PlatformMenuBar` becomes the system app menu and is renamed to the bundle
/// name (e.g. "WaveCrux"). It conventionally hosts About /
/// Preferences / Hide / Quit on macOS; on Linux and Windows the same category
/// renders as a regular branded menu in front of File, matching
/// cross-platform IDE behavior.
enum ActionCategory {
  /// Host-application menu (rendered as the macOS app menu or the
  /// branded leading menu on Linux/Windows).
  app,

  /// File operations (open, close, save, export, workspace management).
  file,

  /// Editing operations (undo/redo, clipboard, selection).
  ///
  /// Ordered between [file] and [view] to match the VS Code / native menu
  /// order. A product with no editing actions simply renders no Edit menu —
  /// the shared menu bar collapses empty categories away.
  edit,

  /// View operations (zoom, panel visibility toggles, theme).
  view,

  /// Navigation (pan, jump-to, cursor and marker placement).
  navigate,

  /// Search and find operations.
  search,

  /// Tools and analyses (diagnostics, format setters, advisors).
  tools,

  /// Help (About, command palette, settings, documentation).
  help,
}
