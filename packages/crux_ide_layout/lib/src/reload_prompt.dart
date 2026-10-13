// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/src/feedback.dart';
import 'package:flutter/material.dart';

/// Key on the [MaterialBanner] that [showCruxReloadPrompt] shows.
const Key kCruxReloadPromptKey = ValueKey<String>('cruxReloadPrompt');

/// Key on the prompt's Ignore button.
const Key kCruxReloadPromptIgnoreKey = ValueKey<String>(
  'cruxReloadPromptIgnore',
);

/// Key on the prompt's reload button.
const Key kCruxReloadPromptReloadKey = ValueKey<String>(
  'cruxReloadPromptReload',
);

/// The controller of the prompt each messenger is showing, so a second
/// change while one is up does not stack a second banner, and
/// [hideCruxReloadPrompt] closes this prompt and never someone else's banner.
final Expando<
  ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>
>
_shown =
    Expando<
      ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>
    >('cruxReloadPrompt');

/// Shows the suite's source-changed prompt: a [MaterialBanner] with
/// [message] and two buttons, [ignoreLabel] then [reloadLabel] (the reload
/// in the default-action position).
///
/// Every product asks the same question the same way when a watched file
/// changes and auto-reload is set to prompt. The banner stays until the user
/// chooses, because it holds an action, and it can always be declined:
/// [onIgnore] runs when Ignore is pressed, [onReload] when the reload button
/// is, and either hides the banner first. While a prompt is already showing,
/// a second call does nothing, so a burst of changes asks once.
///
/// [message] is also spoken through the screen reader when the banner
/// appears, because the desktop accessibility bridges do not announce live
/// regions. All labels are caller-supplied and already localized.
///
/// A no-op when no [ScaffoldMessenger] is in scope.
void showCruxReloadPrompt(
  BuildContext context, {
  required String message,
  required String reloadLabel,
  required String ignoreLabel,
  required VoidCallback onReload,
  required VoidCallback onIgnore,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (_shown[messenger] != null) return;
  void choose(VoidCallback callback) {
    _close(messenger);
    callback();
  }

  announceCrux(context, message);
  final controller = messenger.showMaterialBanner(
    MaterialBanner(
      key: kCruxReloadPromptKey,
      content: Text(message),
      actions: <Widget>[
        TextButton(
          key: kCruxReloadPromptIgnoreKey,
          onPressed: () => choose(onIgnore),
          child: Text(ignoreLabel),
        ),
        TextButton(
          key: kCruxReloadPromptReloadKey,
          onPressed: () => choose(onReload),
          child: Text(reloadLabel),
        ),
      ],
    ),
  );
  _shown[messenger] = controller;
  // However the banner goes (a choice, [hideCruxReloadPrompt], or the
  // messenger clearing it), the next change may ask again.
  unawaited(
    controller.closed.whenComplete(() {
      if (identical(_shown[messenger], controller)) _shown[messenger] = null;
    }),
  );
}

/// Hides the prompt [showCruxReloadPrompt] is showing in [context]'s
/// messenger, without running either callback. Leaves any other banner
/// alone. A no-op when no prompt is showing.
///
/// For a product whose pending change was settled elsewhere (a reload from
/// the menu, the file deleted, the project closed).
void hideCruxReloadPrompt(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _close(messenger);
}

void _close(ScaffoldMessengerState messenger) {
  final controller = _shown[messenger];
  if (controller == null) return;
  _shown[messenger] = null;
  controller.close();
}
