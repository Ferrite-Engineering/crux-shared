// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
/// product's Edit actions, on macOS only. Each is enabled when it would do
/// something, as in any Mac app (see [CruxEditAvailability]); a greyed item is
/// skipped as a key equivalent, so its key falls through to the alert sound,
/// the system's way of saying there is nothing to do. Windows and Linux are
/// unchanged: their in-window menu takes the focus when it opens, so a Copy
/// there would have no selection to copy, and the keys work in the focused
/// widget already.
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

  /// The per-app copy fallback: the text Copy puts on the clipboard when no
  /// text selection answers it, or null when the app has nothing selected.
  ///
  /// Read when the menu builds, to decide whether Copy is enabled (so the host
  /// rebuilds the menu bar when the answer flips between null and non-null),
  /// and again when Copy runs, so the text itself may change without a rebuild.
  /// Null itself means the app has no fallback.
  final String? Function()? copyFallback;

  /// The localized label of [command].
  String labelOf(CruxEditCommand command) => switch (command) {
    CruxEditCommand.cut => cutLabel,
    CruxEditCommand.copy => copyLabel,
    CruxEditCommand.paste => pasteLabel,
    CruxEditCommand.selectAll => selectAllLabel,
  };
}

/// What the focused widget offers the Edit commands.
///
/// Read from the focus rather than asked of the focused widget's actions: a
/// selectable area's copy action reports the key handled even when its
/// selection is empty, so asking it whether Copy would do anything always
/// answers yes. The nearest text widget above the primary focus decides: an
/// [EditableText] (a text field, or the read-only one under [SelectableText])
/// or a [SelectableRegion] (a rendered note).
@immutable
class CruxEditFocus {
  /// Creates a description of the focused text.
  const CruxEditFocus({
    this.editable = false,
    this.readOnly = false,
    this.obscured = false,
    this.hasTextSelection = false,
    this.selectable = false,
  });

  /// Describes the widget that has primary focus now.
  factory CruxEditFocus.current() {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return none;
    EditableTextState? editable;
    var selectable = false;
    bool visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        editable = element.state as EditableTextState;
        return false;
      }
      if (element.widget is SelectableRegion) {
        selectable = true;
        return false;
      }
      return true;
    }

    if (focus is Element && visit(focus)) focus.visitAncestorElements(visit);
    final field = editable;
    if (field != null) {
      final selection = field.textEditingValue.selection;
      return CruxEditFocus(
        editable: true,
        readOnly: field.widget.readOnly,
        obscured: field.widget.obscureText,
        hasTextSelection: selection.isValid && !selection.isCollapsed,
      );
    }
    return selectable ? const CruxEditFocus(selectable: true) : none;
  }

  /// Nothing text-like has focus.
  static const none = CruxEditFocus();

  /// The focused editable text's controller, for watching its selection.
  static TextEditingController? currentController() {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus
        ?.findAncestorStateOfType<EditableTextState>()
        ?.widget
        .controller;
  }

  /// Text that takes typing, or the read-only text of a [SelectableText].
  final bool editable;

  /// The [editable] text cannot be changed (Cut and Paste do nothing).
  final bool readOnly;

  /// The [editable] text is a password, which is never copied.
  final bool obscured;

  /// The [editable] text has a non-empty selection.
  final bool hasTextSelection;

  /// Focus is in a selectable area: a rendered note.
  final bool selectable;

  @override
  bool operator ==(Object other) =>
      other is CruxEditFocus &&
      other.editable == editable &&
      other.readOnly == readOnly &&
      other.obscured == obscured &&
      other.hasTextSelection == hasTextSelection &&
      other.selectable == selectable;

  @override
  int get hashCode =>
      Object.hash(editable, readOnly, obscured, hasTextSelection, selectable);
}

/// What Copy copies.
enum CruxCopySource {
  /// The selection in the focused text field, through its own copy action.
  focusedText,

  /// The text selected in a selectable area ([CruxEditSelectionRegistry]).
  selectedText,

  /// The app's own selection, [CruxEditCommands.copyFallback].
  fallback,
}

/// Which Edit commands would do something, and what Copy would copy.
///
/// The rules a Mac app's Edit menu follows: Copy with a selection to copy, Cut
/// with a selection in text that can change, Paste into text that can change,
/// Select All in text that can be selected.
@immutable
class CruxEditAvailability {
  /// Creates an availability; see [CruxEditAvailability.resolve].
  const CruxEditAvailability({
    this.canCut = false,
    this.copySource,
    this.canPaste = false,
    this.canSelectAll = false,
  });

  /// Works out the commands from the focused text, whether a selectable area
  /// has a selection, and whether the app has a selection of its own.
  ///
  /// Copy's precedence: a selection in the focused text field, then a selection
  /// in a selectable area, then the app's own. A focused text field with
  /// nothing selected in it keeps Copy for itself and has nothing to copy, as
  /// in any Mac app: a selection elsewhere in the app is not what Copy in a
  /// text field means.
  factory CruxEditAvailability.resolve({
    required CruxEditFocus focus,
    required bool hasSelectedText,
    required bool fallbackAvailable,
  }) {
    final copySource = switch (focus) {
      CruxEditFocus(
        editable: true,
        hasTextSelection: true,
        obscured: false,
      ) =>
        CruxCopySource.focusedText,
      _ when hasSelectedText => CruxCopySource.selectedText,
      CruxEditFocus(editable: true) => null,
      _ when fallbackAvailable => CruxCopySource.fallback,
      _ => null,
    };
    final changeable = focus.editable && !focus.readOnly;
    return CruxEditAvailability(
      canCut: changeable && focus.hasTextSelection && !focus.obscured,
      copySource: copySource,
      canPaste: changeable,
      canSelectAll: focus.editable || focus.selectable,
    );
  }

  /// The availability now, from the primary focus and
  /// [CruxEditSelectionRegistry].
  factory CruxEditAvailability.current({required bool fallbackAvailable}) =>
      CruxEditAvailability.resolve(
        focus: CruxEditFocus.current(),
        hasSelectedText: CruxEditSelectionRegistry.instance.text != null,
        fallbackAvailable: fallbackAvailable,
      );

  /// Cut would remove a selection from changeable text.
  final bool canCut;

  /// What Copy would copy, or null when there is nothing to copy.
  final CruxCopySource? copySource;

  /// Paste would insert into changeable text.
  final bool canPaste;

  /// Select All would select text.
  final bool canSelectAll;

  /// Whether [command] would do something.
  bool isEnabled(CruxEditCommand command) => switch (command) {
    CruxEditCommand.cut => canCut,
    CruxEditCommand.copy => copySource != null,
    CruxEditCommand.paste => canPaste,
    CruxEditCommand.selectAll => canSelectAll,
  };

  @override
  bool operator ==(Object other) =>
      other is CruxEditAvailability &&
      other.canCut == canCut &&
      other.copySource == copySource &&
      other.canPaste == canPaste &&
      other.canSelectAll == canSelectAll;

  @override
  int get hashCode => Object.hash(canCut, copySource, canPaste, canSelectAll);
}

/// Runs [command] against whatever the user is working in, and reports whether
/// anything took it.
///
/// [fallbackText] is what Copy puts on the clipboard for the app's own
/// selection, or null when it has none. Copy takes, in order: the selection in
/// the focused text field; the selection in a selectable area
/// ([CruxEditSelectionRegistry]), which is copied even when nothing in the
/// focus chain answers to it; the app's own. See
/// [CruxEditAvailability.resolve].
///
/// Cut, Paste and Select All are sent to the focused text widget, which is what
/// the key would have done had it reached it.
///
/// A command that would do nothing ([CruxEditAvailability.isEnabled] false) is
/// not sent at all, so an empty selection's copy action, which reports success
/// without copying, cannot stand in for the app's own. Never throws and never
/// beeps.
bool performCruxEditCommand(CruxEditCommand command, {String? fallbackText}) {
  final availability = CruxEditAvailability.current(
    fallbackAvailable: fallbackText != null,
  );
  if (!availability.isEnabled(command)) return false;
  if (command == CruxEditCommand.copy) {
    switch (availability.copySource) {
      case CruxCopySource.selectedText:
        final text = CruxEditSelectionRegistry.instance.text;
        if (text == null) return false;
        unawaited(Clipboard.setData(ClipboardData(text: text)));
        return true;
      case CruxCopySource.fallback:
        unawaited(Clipboard.setData(ClipboardData(text: fallbackText!)));
        return true;
      case CruxCopySource.focusedText:
      case null:
        break;
    }
  }
  return _invokeAtFocus(command.intent);
}

bool _invokeAtFocus(Intent intent) {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  final action = Actions.maybeFind<Intent>(focus, intent: intent);
  if (action == null) return false;
  final (handled, _) = Actions.of(focus).invokeActionIfEnabled(action, intent);
  return handled;
}

/// Watches what decides [CruxEditAvailability]: the primary focus, the
/// selection in a focused text field, and [CruxEditSelectionRegistry].
///
/// Notifies only when the focus description or whether a selectable area has a
/// selection changes, so a listener that rebuilds the menu does so when an item
/// would enable or grey, not on every keystroke or caret move. A change
/// reported while a frame is being built is passed on after the frame.
class CruxEditAvailabilityWatcher extends ChangeNotifier {
  /// Starts watching.
  CruxEditAvailabilityWatcher() {
    FocusManager.instance.addListener(_focusChanged);
    CruxEditSelectionRegistry.instance.addListener(_schedule);
    _focusChanged();
  }

  CruxEditFocus _focus = CruxEditFocus.none;
  bool _hasSelectedText = false;
  TextEditingController? _controller;
  bool _pending = false;
  bool _disposed = false;

  /// The availability now, with [fallbackAvailable] from the caller.
  CruxEditAvailability availability({required bool fallbackAvailable}) =>
      CruxEditAvailability.resolve(
        focus: _focus,
        hasSelectedText: _hasSelectedText,
        fallbackAvailable: fallbackAvailable,
      );

  void _focusChanged() {
    final controller = CruxEditFocus.currentController();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_schedule);
      _controller = controller?..addListener(_schedule);
    }
    _schedule();
  }

  void _schedule() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_pending) return;
      _pending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        _update();
      });
      return;
    }
    _update();
  }

  void _update() {
    if (_disposed) return;
    final focus = CruxEditFocus.current();
    final hasSelectedText = CruxEditSelectionRegistry.instance.text != null;
    if (focus == _focus && hasSelectedText == _hasSelectedText) return;
    _focus = focus;
    _hasSelectedText = hasSelectedText;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    FocusManager.instance.removeListener(_focusChanged);
    CruxEditSelectionRegistry.instance.removeListener(_schedule);
    _controller?.removeListener(_schedule);
    _controller = null;
    super.dispose();
  }
}

/// The text currently selected in the selectable areas that report to it.
///
/// A [SelectionArea] reports its selection through `onSelectionChanged`;
/// registering it here lets the Edit menu's Copy reach it without the focus
/// chain. An area reports `null` when its selection clears, which the framework
/// does when the area loses focus, so an entry is never older than the
/// highlight the user sees. Listeners hear every change, so the Edit menu can
/// enable Copy when a selection appears.
class CruxEditSelectionRegistry extends ChangeNotifier {
  CruxEditSelectionRegistry._();

  /// The registry the app uses.
  static final CruxEditSelectionRegistry instance =
      CruxEditSelectionRegistry._();

  // Insertion order is report order, so the latest reporter is the last.
  final Map<Object, String> _byOwner = <Object, String>{};

  /// Records that [owner]'s selection is now [text]; null or empty clears it.
  void report(Object owner, String? text) {
    if (text == null || text.isEmpty) {
      forget(owner);
      return;
    }
    if (_byOwner.keys.lastOrNull == owner && _byOwner[owner] == text) return;
    _byOwner
      ..remove(owner)
      ..[owner] = text;
    notifyListeners();
  }

  /// Forgets [owner], for when its area is disposed.
  void forget(Object owner) {
    if (_byOwner.remove(owner) != null) notifyListeners();
  }

  /// The most recently reported selection, or null when none is selected.
  String? get text => _byOwner.isEmpty ? null : _byOwner.values.last;

  /// Clears every entry, for tests.
  @visibleForTesting
  void debugReset() {
    if (_byOwner.isEmpty) return;
    _byOwner.clear();
    notifyListeners();
  }
}
