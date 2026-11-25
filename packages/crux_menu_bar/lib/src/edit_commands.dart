// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The standard Edit-menu commands: Cut, Copy, Paste and Select All.
///
/// They are not product actions on purpose. A product action is a command the
/// user can rebind, search for in a command palette and see in a toolbar
/// overflow menu; these four are the operating system's, fixed to their
/// conventional keys, and only ever reach the user through the macOS Edit menu
/// (see `CruxDesktopMenuBar.editCommands`).
///
/// Why the macOS Edit menu needs them at all: with no menu item claiming Cmd+C,
/// a key press the framework leaves unhandled falls through AppKit's responder
/// chain to the alert sound, and nothing copies. A menu item that claims the
/// key equivalent turns that fall-through into a call to
/// [performCruxEditCommand], which finds the copy for itself instead of relying
/// on the key having reached the right widget.
enum CruxEditCommand {
  /// Cut the selection (Cmd+X).
  cut(LogicalKeyboardKey.keyX),

  /// Copy the selection (Cmd+C).
  copy(LogicalKeyboardKey.keyC),

  /// Paste the clipboard (Cmd+V).
  paste(LogicalKeyboardKey.keyV),

  /// Select everything in the focused text (Cmd+A).
  selectAll(LogicalKeyboardKey.keyA);

  const CruxEditCommand(this.key);

  /// The key that, with Cmd, invokes the command.
  final LogicalKeyboardKey key;

  /// The Cmd+key chord the macOS menu shows and claims.
  SingleActivator get activator => SingleActivator(key, meta: true);

  /// The framework intent a focused text widget answers to.
  Intent get intent => switch (this) {
    CruxEditCommand.cut => const CopySelectionTextIntent.cut(
      SelectionChangedCause.keyboard,
    ),
    CruxEditCommand.copy => CopySelectionTextIntent.copy,
    CruxEditCommand.paste => const PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    CruxEditCommand.selectAll => const SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
  };
}

/// Opt-in configuration of the macOS Edit menu's standard commands, for
/// `CruxDesktopMenuBar.editCommands`.
///
/// The four commands lead the Edit menu in a group of their own, ahead of the
/// product's Edit actions, on macOS only. They are always enabled: a greyed
/// item is skipped as a key equivalent, and the key then falls through to the
/// alert sound the items exist to prevent. Windows and Linux are unchanged;
/// their in-window menu takes the focus when it opens, so a Copy there would
/// have no selection to copy, and the keys work in the focused widget already.
@immutable
class CruxEditCommands {
  /// Creates the Edit-commands option with the product's localized labels.
  const CruxEditCommands({
    required this.cutLabel,
    required this.copyLabel,
    required this.pasteLabel,
    required this.selectAllLabel,
    this.copyFallback,
  });

  /// Localized label of Cut.
  final String cutLabel;

  /// Localized label of Copy.
  final String copyLabel;

  /// Localized label of Paste.
  final String pasteLabel;

  /// Localized label of Select All.
  final String selectAllLabel;

  /// The per-app copy fallback: the text to copy when no widget in the focus
  /// chain answers Copy, or null when the app has none.
  ///
  /// Consulted after [CruxEditSelectionRegistry], so an app whose selectable
  /// areas report to the registry needs no callback.
  final String? Function()? copyFallback;

  /// The localized label of [command].
  String labelOf(CruxEditCommand command) => switch (command) {
    CruxEditCommand.cut => cutLabel,
    CruxEditCommand.copy => copyLabel,
    CruxEditCommand.paste => pasteLabel,
    CruxEditCommand.selectAll => selectAllLabel,
  };
}

/// Runs [command] against whatever the user is working in, and reports whether
/// anything took it.
///
/// First the focused widget: the intent is sent where the focus is, which is
/// what a Cmd+C that reached the framework would have done, so a text field, a
/// selectable note and any widget that handles the framework's text intents all
/// answer as they do to the key.
///
/// Then, for Copy only, the selection a selectable area last reported
/// ([CruxEditSelectionRegistry]) and then [copyFallback]. A selection that is
/// on screen is copied even when nothing in the focus chain answers, which is
/// the case the beep was.
///
/// Never throws and never beeps: a command nothing can take is a no-op.
bool performCruxEditCommand(
  CruxEditCommand command, {
  String? Function()? copyFallback,
}) {
  final intent = command.intent;
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus != null) {
    final action = Actions.maybeFind<Intent>(focus, intent: intent);
    if (action != null) {
      final (handled, _) = Actions.of(
        focus,
      ).invokeActionIfEnabled(action, intent);
      if (handled) return true;
    }
  }
  if (command == CruxEditCommand.copy) {
    final text =
        CruxEditSelectionRegistry.instance.text ?? copyFallback?.call();
    if (text != null && text.isNotEmpty) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
      return true;
    }
  }
  return false;
}

/// The text currently selected in the selectable areas that report to it.
///
/// A `SelectionArea` reports its selection through `onSelectionChanged`;
/// registering it here lets the Edit menu's Copy reach it without the focus
/// chain. An area reports `null` when its selection clears, which the framework
/// does when the area loses focus, so an entry is never older than the
/// highlight the user sees.
class CruxEditSelectionRegistry {
  CruxEditSelectionRegistry._();

  /// The registry the app uses.
  static final CruxEditSelectionRegistry instance =
      CruxEditSelectionRegistry._();

  // Insertion order is report order, so the latest reporter is the last.
  final Map<Object, String> _byOwner = <Object, String>{};

  /// Records that [owner]'s selection is now [text]; null or empty clears it.
  void report(Object owner, String? text) {
    if (text == null || text.isEmpty) {
      _byOwner.remove(owner);
      return;
    }
    _byOwner
      ..remove(owner)
      ..[owner] = text;
  }

  /// Forgets [owner], for when its area is disposed.
  void forget(Object owner) => _byOwner.remove(owner);

  /// The most recently reported selection, or null when none is selected.
  String? get text => _byOwner.isEmpty ? null : _byOwner.values.last;

  /// Clears every entry, for tests.
  @visibleForTesting
  void debugReset() => _byOwner.clear();
}
