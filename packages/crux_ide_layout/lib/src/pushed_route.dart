// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Whether keyboard focus is inside a route pushed above the first page of
/// its navigator, or of any navigator around that one: a dialog, a sheet, a
/// popup menu.
///
/// A window-level key handler (a `HardwareKeyboard` handler, or a `Focus`
/// high in the tree) sees every key the focused control does not handle.
/// While a dialog is open on the root navigator the handler's own route is
/// not current, so `ModalRoute.of(context).isCurrent` was enough to keep it
/// quiet. A tab-modal dialog is pushed on the tab's own navigator, inside
/// the screen's route, which stays current: Escape pressed to close the
/// dialog would also reach the handler (clearing a selection, cancelling a
/// cursor). Such a handler returns early when this is true:
///
/// ```dart
/// bool _onKey(KeyEvent event) {
///   if (cruxFocusIsInPushedRoute()) return false;
///   ...
/// }
/// ```
///
/// [focus] defaults to the primary focus. False when nothing has focus.
bool cruxFocusIsInPushedRoute([FocusNode? focus]) {
  final node = focus ?? FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (context == null || !context.mounted) return false;
  BuildContext? at = context;
  while (at != null && at.mounted) {
    final route = ModalRoute.of(at);
    if (route == null) return false;
    if (!route.isFirst) return true;
    final navigator = route.navigator;
    if (navigator == null || !navigator.mounted) return false;
    at = navigator.context;
  }
  return false;
}
