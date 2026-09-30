// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The localized strings a `KeyBindingsEditor` needs, supplied by the host so
/// the package stays free of any product's localization system.
///
/// Each product writes a small adapter over its own `L10N`. All values are
/// already localized.
abstract interface class KeyBindingsEditorStrings {
  /// Intro line shown above the list.
  String get description;

  /// Note shown (when the host requests it) explaining shortcuts need a
  /// hardware keyboard. Only rendered when `showPhoneNote` is true.
  String get phoneNote;

  /// Label for the Import button.
  String get importLabel;

  /// Label for the Export button.
  String get exportLabel;

  /// Label for the Reset-all button (and the confirm action in its dialog).
  String get resetAllLabel;

  /// Placeholder shown for an unbound action.
  String get notBound;

  /// Tooltip for the per-row edit (start-capture) button.
  String get editTooltip;

  /// Tooltip for the per-row unbind button.
  String get unbindTooltip;

  /// Tooltip for the per-row reset button.
  String get resetTooltip;

  /// Prompt shown while capturing a new chord.
  String get capturePrompt;

  /// Conflict warning for a row whose chord collides with [actions]
  /// (an already-localized, comma-joined list of the other action labels).
  String conflict(String actions);

  /// Title of the reset-all confirmation dialog.
  String get resetAllTitle;

  /// Body of the reset-all confirmation dialog.
  String get resetAllBody;

  /// Cancel label in the reset-all confirmation dialog.
  String get resetAllCancel;
}

/// Localized strings for the editor's keyboard and screen-reader behaviour,
/// supplied alongside [KeyBindingsEditorStrings].
///
/// A separate object for the same reason as [KeyBindingsConflictMessages]:
/// hosts that `implements` [KeyBindingsEditorStrings] keep compiling. Without
/// it the editor still works from the keyboard, but the keys go unexplained
/// and an unbound row is announced with the visual placeholder.
abstract interface class KeyBindingsAccessibilityStrings {
  /// How to operate a row from the keyboard, announced once when focus
  /// enters the list and shown under the description, e.g. "Up and Down
  /// move between shortcuts. Enter changes one, Delete removes it, Shift+
  /// Delete restores its default."
  String get keyboardHint;

  /// What a screen reader says for an unbound action, e.g. "no shortcut".
  /// The visual placeholder is often a dash, which is not spoken.
  String get notBoundSpoken;
}

/// Localized message builders for the **asymmetric** conflict UI, supplied
/// alongside `KeyBindingsEditor.conflictDetails`.
///
/// This is a separate object rather than new members on
/// [KeyBindingsEditorStrings] so existing hosts (which `implements` that
/// interface) are not forced to add members; only hosts opting into the richer
/// conflict UI provide one. All values are already localized.
abstract interface class KeyBindingsConflictMessages {
  /// Warning for the row whose binding **wins** the chord but is also bound to
  /// [others] (an already-localized, comma-joined list of the shadowed action
  /// labels). This row's shortcut still fires.
  String wins(String others);

  /// Warning for a **shadowed** row whose binding will not fire because
  /// [winner] (an already-localized action label) holds the same chord. This is
  /// the row the user must reassign to resolve the conflict.
  String shadowedBy(String winner);

  /// Summary banner shown above the list when [count] chords are in conflict.
  String summary(int count);
}
