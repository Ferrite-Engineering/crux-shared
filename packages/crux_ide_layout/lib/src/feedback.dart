// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/src/crux_desktop_tokens.dart';
import 'package:crux_ide_layout/src/crux_dialog.dart';
import 'package:crux_ide_layout/src/crux_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Standard duration for informational snack bars shown by
/// [showCruxInfoSnack].
const Duration kCruxInfoSnackDuration = Duration(seconds: 4);

/// The nominal reading time for a failure. [showCruxErrorSnack] no longer
/// times out: an error stays until it is dismissed.
const Duration kCruxErrorSnackDuration = Duration(seconds: 6);

/// How long an informational message that carries an action stays: long
/// enough to reach the action (it also never leaves while hovered or
/// focused).
const Duration kCruxActionSnackDuration = Duration(seconds: 8);

/// The announcement for [message] with [action]: the message, then the
/// action's label, so a screen-reader user knows there is something to do.
String _spoken(String message, CruxToastAction? action) =>
    action == null ? message : '$message ${action.label}';

/// Speaks [message] through the platform screen reader.
///
/// A [SnackBar] marks itself as a live region, but the desktop accessibility
/// bridges (Windows, macOS, Linux) ignore the live-region flag, so a status
/// change shown only visually is never heard. An announcement is delivered
/// on every platform. Use [assertive] for failures the user must hear before
/// continuing; polite announcements wait for current speech to finish.
///
/// A no-op when [context] has no enclosing [View].
void announceCrux(
  BuildContext context,
  String message, {
  bool assertive = false,
}) {
  final view = View.maybeOf(context);
  if (view == null) return;
  // Fire and forget: the platform channel's reply carries nothing.
  unawaited(
    SemanticsService.sendAnnouncement(
      view,
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
      assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
    ),
  );
}

/// Shows the suite-standard informational message, with a polite
/// screen-reader announcement.
///
/// Under a Crux Desktop theme (one carrying `CruxDesktopTokens`, which
/// `cruxThemeForDevice` installs on macOS, Windows, Linux and the web) it is
/// a toast, bottom-right above the status bar: one visible at a time, a new
/// one replacing it, gone after [kCruxInfoSnackDuration]. Under any other
/// theme (phone and tablet) it is a floating Material snack bar of the same
/// duration.
///
/// A no-op when there is nowhere to show it (no root `Overlay` on desktop, no
/// [ScaffoldMessenger] otherwise), so callers on bare test scaffolds degrade
/// silently instead of throwing. The caller supplies an already-localized
/// [message]. [key] lands on the toast or the snack bar, for tests.
///
/// [action] adds one button ("Undo"): reachable with Tab, announced with the
/// message, and closing the message when chosen. A message with an action
/// stays for [kCruxActionSnackDuration], and on desktop never leaves while
/// the pointer is over it or focus is in it. On phone and tablet it is the
/// snack bar's `SnackBarAction`.
void showCruxInfoSnack(
  BuildContext context,
  String message, {
  Key? key,
  CruxToastAction? action,
}) {
  final duration = action == null
      ? kCruxInfoSnackDuration
      : kCruxActionSnackDuration;
  if (CruxDesktopTokens.isDesktop(context)) {
    if (CruxToasts.show(
      context,
      message,
      error: false,
      infoDuration: duration,
      key: key,
      action: action,
    )) {
      announceCrux(context, _spoken(message, action));
    }
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  announceCrux(context, _spoken(message, action));
  messenger.showSnackBar(
    SnackBar(
      key: key,
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      // Four seconds (eight with an action) is this helper's contract,
      // pinned by test, never the framework's default.
      duration: duration,
      // Without this the framework keeps a snack bar that has an action
      // until the action is chosen, ignoring [duration].
      persist: false,
      action: _snackBarAction(action),
    ),
  );
}

SnackBarAction? _snackBarAction(CruxToastAction? action) => action == null
    ? null
    : SnackBarAction(
        key: const ValueKey('cruxToastAction'),
        label: action.label,
        onPressed: action.onPressed,
      );

/// Shows the suite-standard error message, with an assertive screen-reader
/// announcement.
///
/// Under a Crux Desktop theme it is a toast like [showCruxInfoSnack]'s, in
/// the error colour, that **stays until the user closes it** (or a newer
/// toast replaces it): a failure that vanishes while the user looks elsewhere
/// was never reported. Under any other theme it is a floating snack bar in
/// error-container colours that likewise stays until it is dismissed (its
/// close icon, its action, or a swipe), with or without an action.
///
/// A no-op when there is nowhere to show it. The caller supplies an
/// already-localized [message]. [key] lands on the toast or the snack bar,
/// for tests. [action] is as for [showCruxInfoSnack] ("Retry").
void showCruxErrorSnack(
  BuildContext context,
  String message, {
  Key? key,
  CruxToastAction? action,
}) {
  if (CruxDesktopTokens.isDesktop(context)) {
    if (CruxToasts.show(
      context,
      message,
      error: true,
      infoDuration: kCruxInfoSnackDuration,
      key: key,
      action: action,
    )) {
      announceCrux(context, _spoken(message, action), assertive: true);
    }
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final colorScheme = Theme.of(context).colorScheme;
  announceCrux(context, _spoken(message, action), assertive: true);
  messenger.showSnackBar(
    SnackBar(
      key: key,
      content: Text(
        message,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
      backgroundColor: colorScheme.errorContainer,
      behavior: SnackBarBehavior.floating,
      // A failure stays until the user dismisses it, as on desktop; the
      // close icon is the dismissal for a message with no action.
      persist: true,
      showCloseIcon: true,
      action: _snackBarAction(action),
    ),
  );
}

/// Removes the message [showCruxInfoSnack] or [showCruxErrorSnack] is
/// showing over [context], if any: for a "working on it" message whose
/// outcome needs no message of its own. A no-op when nothing is showing.
void hideCruxSnack(BuildContext context) {
  if (CruxDesktopTokens.isDesktop(context)) {
    CruxToasts.hide(context);
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}

/// Shows the suite-standard destructive-action confirmation dialog and
/// resolves to whether the user confirmed.
///
/// A [CruxDialog] through [showCruxDialog]: [cancelLabel] first, holding
/// focus when the dialog opens so Enter or Space on arrival cancels, then
/// [confirmLabel] as a filled button in the theme's error colours, so the
/// destructive choice is visibly marked and never the default. Dismissing the
/// dialog any other way (barrier tap, Escape) resolves `false`.
///
/// All four strings are caller-supplied and already localized. The optional
/// [dialogKey]/[cancelKey]/[confirmKey] let host apps keep stable widget
/// keys for tests.
Future<bool> confirmCruxDestructiveAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  Key? dialogKey,
  Key? cancelKey,
  Key? confirmKey,
}) async {
  final confirmed = await showCruxDialog<bool>(
    context: context,
    builder: (dialogContext) => CruxDialog(
      key: dialogKey,
      title: title,
      width: 400,
      content: Text(body),
      actions: <Widget>[
        CruxDialogAction(
          key: cancelKey,
          label: cancelLabel,
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        CruxDialogAction(
          key: confirmKey,
          label: confirmLabel,
          role: CruxDialogActionRole.destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
