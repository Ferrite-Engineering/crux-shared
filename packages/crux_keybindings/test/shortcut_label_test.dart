// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS renders modifier glyphs with no separator', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final label = formatShortcutLabel(
      const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true),
    );
    expect(label, '⌘⇧P');
  });

  test('non-macOS renders words joined with +', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final label = formatShortcutLabel(
      const SingleActivator(
        LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
      ),
    );
    expect(label, 'Ctrl+Shift+P');
  });

  test('special keys use friendly symbols', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      formatShortcutLabel(const SingleActivator(LogicalKeyboardKey.arrowLeft)),
      '←',
    );
    expect(
      formatShortcutLabel(const SingleActivator(LogicalKeyboardKey.comma)),
      ',',
    );
  });

  test('null / non-SingleActivator returns the empty label', () {
    expect(formatShortcutLabel(null, emptyLabel: '—'), '—');
  });

  test('does not build its key-label table inside the function body', () {
    // `formatShortcutLabel` is the per-row label formatter for the command
    // palette, the overflow action menu and the key-bindings editor — all of
    // which rebuild every visible row on every keystroke. A key-label map
    // constructed inside the lookup helper therefore costs one map allocation
    // plus twelve hash insertions per row per keystroke, in every product.
    //
    // The map cannot be `const` (LogicalKeyboardKey overrides ==/hashCode),
    // but it can be a library-level `final`, initialized once. This guard
    // fails if it moves back inside a function body.
    final source = File(
      'lib/src/shortcut_label.dart',
    ).readAsStringSync();

    final mapDeclaration = RegExp(
      r'^final Map<LogicalKeyboardKey, String> \w+ = \{',
      multiLine: true,
    );
    expect(
      mapDeclaration.hasMatch(source),
      isTrue,
      reason:
          'The key-label table must be declared at library level so it is '
          'built once, not per call.',
    );

    // Nothing inside a function body may build a LogicalKeyboardKey-keyed
    // map: a body-local declaration is indented, a library-level one is not.
    final indentedMapLiteral = RegExp(
      r'^\s+.*<LogicalKeyboardKey, String>\s*\{',
      multiLine: true,
    );
    expect(
      indentedMapLiteral.hasMatch(source),
      isFalse,
      reason:
          'A LogicalKeyboardKey-keyed map is being constructed inside a '
          'function body — hoist it to a library-level final.',
    );
  });
}
