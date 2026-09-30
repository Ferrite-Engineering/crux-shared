// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/widgets/menu_mnemonics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// One top-level menu for [MnemonicMenuBar].
@immutable
class MnemonicMenuEntry {
  /// Creates a top-level menu entry.
  const MnemonicMenuEntry({
    required this.acceleratorLabel,
    required this.menuChildren,
  });

  /// The localized title with a single `&` accelerator marker (e.g. `&File`).
  final String acceleratorLabel;

  /// The dropdown contents ([MenuItemButton]s / dividers).
  final List<Widget> menuChildren;
}

/// A Material [MenuBar] that adds native Windows/Linux **Alt access-key**
/// behaviour on top of Flutter's built-in menu navigation:
///
/// - **Hold Alt** → mnemonic underlines appear (and stay while held).
/// - **Tap Alt** → "menu mode": underlines latch on and the first menu takes
///   focus. Flutter's own directional actions then handle Left/Right (move
///   between menus), Down/Enter (open + navigate items) and Esc (close).
/// - **Alt + letter** (from anywhere) → opens that menu directly.
/// - **In menu mode, a bare letter** → opens the matching menu.
/// - **Esc** or **another Alt tap** or **focus leaving the bar** → exits menu
///   mode (underlines off, focus released).
///
/// This deliberately replaces Flutter's `MenuAcceleratorLabel` (which only
/// reacts to the physical Alt state and can't latch or add an underline gap)
/// with [MnemonicLabel] driven by a single [MnemonicsController].
class MnemonicMenuBar extends StatefulWidget {
  /// Creates a mnemonic menu bar rendering [entries] left-to-right.
  const MnemonicMenuBar({required this.entries, super.key});

  /// The top-level menus, rendered in order.
  final List<MnemonicMenuEntry> entries;

  @override
  State<MnemonicMenuBar> createState() => _MnemonicMenuBarState();
}

class _MnemonicMenuBarState extends State<MnemonicMenuBar> {
  final MnemonicsController _mnemonics = MnemonicsController();
  late List<FocusNode> _focusNodes;
  late List<MenuController> _controllers;

  bool _altDown = false;
  bool _otherKeyDuringAlt = false;

  @override
  void initState() {
    super.initState();
    _allocate(widget.entries.length);
    HardwareKeyboard.instance.addHandler(_onKey);
    // A pointer press anywhere counts as "other input during Alt" — see
    // [_onGlobalPointer]. Global, because the press that matters lands far from
    // this menu bar: on the waveform canvas, in a tree this widget does not
    // wrap.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
  }

  /// Cancels the bare-Alt-tap latch when Alt is held during a pointer press.
  ///
  /// **Alt+click is a real gesture, not a tap of Alt.** WaveCrux authors an
  /// annotation with it. Before this, only *keys* cancelled the latch, so
  /// Alt+click looked identical to tapping Alt on its own: Alt down, a click
  /// the state machine could not see, Alt up with nothing recorded in between
  /// — and menu mode latched.
  ///
  /// The user then typed into the editor that had just opened and the first
  /// letter matching a menu mnemonic opened that menu and stole the focus, so
  /// the note committed mid-word. On Linux 'T' opened Tools immediately; on
  /// Windows it took however many characters until one matched. macOS was
  /// unaffected throughout — it uses the native `PlatformMenuBar` and never
  /// builds this widget at all.
  void _onGlobalPointer(PointerEvent event) {
    if (event is PointerDownEvent && _altDown) _otherKeyDuringAlt = true;
  }

  @override
  void didUpdateWidget(MnemonicMenuBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.length != widget.entries.length) {
      _disposeNodes();
      _allocate(widget.entries.length);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _disposeNodes();
    _mnemonics.dispose();
    super.dispose();
  }

  void _allocate(int count) {
    _focusNodes = List.generate(count, (_) => FocusNode());
    _controllers = List.generate(count, (_) => MenuController());
    for (final node in _focusNodes) {
      node.addListener(_onFocusChanged);
    }
  }

  void _disposeNodes() {
    for (final node in _focusNodes) {
      node
        ..removeListener(_onFocusChanged)
        ..dispose();
    }
  }

  /// Lowercase accelerator character for entry [i] (the char after its `&`).
  String? _mnemonicOf(int i) {
    final label = widget.entries[i].acceleratorLabel;
    final idx = label.indexOf('&');
    if (idx < 0 || idx + 1 >= label.length) return null;
    return label[idx + 1].toLowerCase();
  }

  int? _indexForKey(LogicalKeyboardKey key) {
    final pressed = key.keyLabel.toLowerCase();
    if (pressed.length != 1) return null;
    for (var i = 0; i < widget.entries.length; i++) {
      if (_mnemonicOf(i) == pressed) return i;
    }
    return null;
  }

  /// Whether a text field currently has focus.
  ///
  /// Typing into a text field must never open a menu, whatever this widget
  /// believes about Alt. Independent of the latch fix above on purpose: that
  /// one addresses a known way the state machine was misled, this one holds
  /// even when something else misleads it — a platform that drops an Alt
  /// key-up, a window that regains focus mid-chord.
  bool get _textEntryHasFocus =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    final key = event.logicalKey;
    final isAlt =
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.alt;
    final keyboard = HardwareKeyboard.instance;
    final ctrlOrMeta = keyboard.isControlPressed || keyboard.isMetaPressed;

    if (event is KeyDownEvent) {
      if (isAlt) {
        _altDown = true;
        _otherKeyDuringAlt = false;
        _mnemonics.altHeld = true;
        return false;
      }
      // Esc exits menu mode (but let Flutter close an open menu first).
      if (key == LogicalKeyboardKey.escape &&
          _mnemonics.latched &&
          !_anyMenuOpen) {
        _deactivate();
        return true;
      }
      // Alt + mnemonic letter (not Ctrl/Meta) opens that menu from anywhere —
      // except into a text field, where the letter is what the user is writing.
      if (_altDown && !ctrlOrMeta && !_textEntryHasFocus) {
        _otherKeyDuringAlt = true; // any key during Alt cancels the bare tap
        final index = _indexForKey(key);
        if (index != null) {
          _open(index);
          return true;
        }
        return false;
      }
      // In menu mode, a bare mnemonic letter opens the matching menu — again,
      // never while the letter is being typed into something.
      if (_mnemonics.latched && !ctrlOrMeta && !_textEntryHasFocus) {
        final index = _indexForKey(key);
        if (index != null) {
          _open(index);
          return true;
        }
      }
      return false;
    }

    if (event is KeyUpEvent && isAlt) {
      _altDown = false;
      _mnemonics.altHeld = false;
      if (!_otherKeyDuringAlt) {
        // A clean Alt tap toggles menu mode.
        if (_mnemonics.latched) {
          _deactivate();
        } else {
          _activate();
        }
      }
      return false;
    }
    return false;
  }

  bool get _anyMenuOpen => _controllers.any((c) => c.isOpen);

  void _activate() {
    _mnemonics.latch();
    if (_focusNodes.isNotEmpty) _focusNodes.first.requestFocus();
  }

  void _deactivate() {
    for (final c in _controllers) {
      if (c.isOpen) c.close();
    }
    _mnemonics.unlatch();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _open(int index) {
    _mnemonics.latch();
    // Switching menus: close any other open dropdown so two can't show at once.
    for (var i = 0; i < _controllers.length; i++) {
      if (i != index && _controllers[i].isOpen) _controllers[i].close();
    }
    _focusNodes[index].requestFocus();
    _controllers[index].open();
  }

  /// When focus leaves every top-level button and no menu is open, drop out of
  /// menu mode (e.g. the user clicked elsewhere). Deferred a frame so the
  /// transient focus gap while a submenu overlay opens doesn't trip it.
  void _onFocusChanged() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mnemonics.latched) return;
      final anyFocused = _focusNodes.any((n) => n.hasFocus);
      if (!anyFocused && !_anyMenuOpen) _mnemonics.unlatch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MnemonicsScope(
      notifier: _mnemonics,
      child: MenuBar(
        children: [
          for (var i = 0; i < widget.entries.length; i++)
            SubmenuButton(
              focusNode: _focusNodes[i],
              controller: _controllers[i],
              menuChildren: widget.entries[i].menuChildren,
              child: MnemonicLabel(widget.entries[i].acceleratorLabel),
            ),
        ],
      ),
    );
  }
}
