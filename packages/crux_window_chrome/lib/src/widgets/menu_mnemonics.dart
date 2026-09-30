// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Tracks whether the Windows/Linux menu-bar mnemonic underlines should be
/// shown, mirroring the native "Alt access key" behaviour:
///
/// - **Alt held** → underlines show while the key is down (`altHeld`).
/// - **Menu mode latched** → after a bare Alt *tap* (press + release with no
///   other key), the menu bar enters "menu mode": underlines stay shown and
///   the first top-level menu takes keyboard focus until the user exits
///   (Esc, another Alt tap, or focus leaving the menu bar). This is the latch
///   Flutter's built-in `MenuAcceleratorLabel` lacks — it only reacts to the
///   physical Alt state, which is why a tap looked flaky.
///
/// [visible] (the union of the two) drives [MnemonicLabel]; it is a single
/// deterministic source of truth, so the underline no longer toggles on
/// alternate presses.
class MnemonicsController extends ChangeNotifier {
  bool _altHeld = false;
  bool _latched = false;

  /// Whether the mnemonic underlines should currently be drawn.
  bool get visible => _altHeld || _latched;

  /// Whether menu mode is latched (persists after Alt is released).
  bool get latched => _latched;

  /// Whether the Alt key is currently physically held.
  bool get altHeld => _altHeld;

  set altHeld(bool value) {
    if (_altHeld == value) return;
    final before = visible;
    _altHeld = value;
    if (visible != before) notifyListeners();
  }

  /// Latches menu mode on (underlines stay shown after Alt is released).
  void latch() {
    if (_latched) return;
    final before = visible;
    _latched = true;
    if (visible != before) notifyListeners();
  }

  /// Releases the menu-mode latch (exits menu mode).
  void unlatch() {
    if (!_latched) return;
    final before = visible;
    _latched = false;
    if (visible != before) notifyListeners();
  }
}

/// Provides the [MnemonicsController] to descendant [MnemonicLabel]s and
/// rebuilds them when underline visibility changes.
class MnemonicsScope extends InheritedNotifier<MnemonicsController> {
  /// Creates a scope exposing [notifier] to descendant [MnemonicLabel]s.
  const MnemonicsScope({
    required MnemonicsController super.notifier,
    required super.child,
    super.key,
  });

  /// Whether mnemonic underlines should be shown for the nearest scope.
  static bool visibleOf(BuildContext context) {
    final controller = context
        .dependOnInheritedWidgetOfExactType<MnemonicsScope>()
        ?.notifier;
    return controller?.visible ?? false;
  }
}

/// A menu-title label that renders an Alt-accelerator mnemonic: the character
/// following the `&` marker is underlined — with a small **gap** between the
/// glyph and the line (the native look Flutter's `MenuAcceleratorLabel` can't
/// produce) — whenever the enclosing [MnemonicsScope] is
/// [MnemonicsScope.visibleOf].
///
/// When no marker is present, or underlines are hidden, it renders as plain
/// text. The `&` is never displayed.
class MnemonicLabel extends StatelessWidget {
  /// Creates a mnemonic label rendering [label] (with an optional `&` marker).
  const MnemonicLabel(this.label, {super.key});

  /// The label, optionally containing a single `&` before the accelerator
  /// character (e.g. `&File`, `ファイル(&F)`).
  final String label;

  @override
  Widget build(BuildContext context) {
    final markerIndex = label.indexOf('&');
    // Display text has the marker removed; the accelerator char is the one
    // that was immediately after the '&'.
    final display = markerIndex < 0
        ? label
        : label.substring(0, markerIndex) + label.substring(markerIndex + 1);
    final style = DefaultTextStyle.of(context).style;

    final hasMnemonic = markerIndex >= 0 && markerIndex < display.length;
    if (!hasMnemonic || !MnemonicsScope.visibleOf(context)) {
      return Text(display, style: style);
    }

    final before = display.substring(0, markerIndex);
    final mnemonicChar = display.substring(markerIndex, markerIndex + 1);
    final after = display.substring(markerIndex + 1);

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _UnderlinedChar(mnemonicChar, style: style),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }
}

/// A single character with a thin underline drawn a couple of logical pixels
/// **below** the glyph, giving the native gap between letter and line.
class _UnderlinedChar extends StatelessWidget {
  const _UnderlinedChar(this.char, {required this.style});

  final String char;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final color = style.color ?? DefaultTextStyle.of(context).style.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: color ?? const Color(0xFFFFFFFF)),
        ),
      ),
      // The bottom padding sits between the glyph and the border line, which
      // is what produces the visible gap.
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1.5),
        child: Text(char, style: style),
      ),
    );
  }
}
