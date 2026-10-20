// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Whether keyboard focus is in a text field: an [EditableText] is the
/// primary focus or one of its ancestors.
///
/// A window-level shortcut whose chord a text field also uses (Shift+Enter
/// is a new line in a multi-line field, and a modified Enter is still Enter
/// to the field) must not fire while this is true, so the keystroke reaches
/// the field. `EditableText` attaches its focus node to an inner `Focus`, so
/// the primary focus's own widget is never the `EditableText`; walking the
/// ancestors finds it.
bool cruxTextInputFocused() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  if (focusContext.widget is EditableText) return true;
  var found = false;
  focusContext.visitAncestorElements((element) {
    if (element.widget is EditableText) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
