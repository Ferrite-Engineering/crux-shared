// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Standard duration for informational snack bars shown by
/// [showCruxInfoSnack].
const Duration kCruxInfoSnackDuration = Duration(seconds: 4);

/// Standard duration for error snack bars shown by [showCruxErrorSnack].
/// Longer than the info duration so the user has time to read a failure.
const Duration kCruxErrorSnackDuration = Duration(seconds: 6);

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

/// Shows the suite-standard informational snack bar: floating behavior,
/// four-second duration, and a polite screen-reader announcement.
///
/// A no-op when no [ScaffoldMessenger] is in scope, so callers on
/// messenger-less test scaffolds degrade silently instead of throwing.
/// The caller supplies an already-localized [message].
void showCruxInfoSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  announceCrux(context, message);
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      // The four-second standard is this helper's contract, pinned by test;
      // it must not drift if the framework's default ever changes.
      // ignore: avoid_redundant_argument_values
      duration: kCruxInfoSnackDuration,
    ),
  );
}

/// Shows the suite-standard error snack bar: floating behavior, six-second
/// duration, error-container colors so a failure is visually distinct from
/// routine feedback, and an assertive screen-reader announcement.
///
/// A no-op when no [ScaffoldMessenger] is in scope. The caller supplies an
/// already-localized [message].
void showCruxErrorSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final colorScheme = Theme.of(context).colorScheme;
  announceCrux(context, message, assertive: true);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
      backgroundColor: colorScheme.errorContainer,
      behavior: SnackBarBehavior.floating,
      duration: kCruxErrorSnackDuration,
    ),
  );
}

/// Shows the suite-standard destructive-action confirmation dialog and
/// resolves to whether the user confirmed.
///
/// Layout convention: [cancelLabel] on the left as a plain [TextButton],
/// [confirmLabel] on the right as a [FilledButton] in the theme's error
/// colors, so the destructive choice is visually marked and sits in the
/// default-action position. Dismissing the dialog any other way (barrier
/// tap, escape) resolves `false`.
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        key: dialogKey,
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            key: cancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
