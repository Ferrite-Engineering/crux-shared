// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Copy for the acceptance surface.
///
/// **English only, and unlike every other shared surface in the suite this one
/// is not wired to a product's ARB bundle.** The agreement itself is executed
/// in English and is not translated: a translated EULA is a second legal text
/// to keep in step with counsel, in nine languages, each of which could drift
/// from the one that actually binds. Since the document on screen is English,
/// framing it in a localized chrome would imply a localized agreement, so the
/// chrome stays English too — the honest presentation of an English contract.
///
/// The class exists rather than a wall of literals so a host *can* substitute
/// copy (a product-specific decline label, say), and so the strings are
/// reachable from a test without matching against hardcoded prose.
@immutable
class CruxEulaStrings {
  /// Creates a copy bundle. Every field defaults to the shipped English.
  const CruxEulaStrings({
    this.title = 'End User License Agreement',
    this.subtitle = 'Please read and accept to continue.',
    this.acceptCheckboxLabel =
        'I have read and accept the End User License Agreement.',
    this.acceptButton = 'Accept',
    this.declineButton = 'Decline and quit',
    this.openOnline = 'Read it on edacrux.app',
    this.openSourceNote =
        'Accepting is not a condition of any open-source licence. The source '
        'code released under the Apache License 2.0 stays available on the '
        'same terms from our public repository whether or not you accept '
        'this agreement (section 3).',
    this.updatedNotice =
        'This agreement has changed since you last accepted it. Please review '
        'it again.',
    this.documentLabel = 'Agreement text',
  });

  /// Dialog title.
  final String title;

  /// One line under the title, above the document.
  final String subtitle;

  /// Label beside the checkbox that arms [acceptButton].
  final String acceptCheckboxLabel;

  /// Label for the affirmative button.
  final String acceptButton;

  /// Label for the button that ends the session.
  final String declineButton;

  /// Label for the link to the published agreement.
  final String openOnline;

  /// The section 3 promise, restated where the user is deciding.
  ///
  /// **Load-bearing, not reassurance.** Section 3's final paragraph says no
  /// in-application dialog conditions an open-source right on accepting this
  /// agreement. A blocking dialog over a free, Apache-licensed application
  /// reads exactly like such a condition unless it says otherwise, so this
  /// sentence is what keeps the surface consistent with the document it is
  /// presenting.
  final String openSourceNote;

  /// Shown instead of [subtitle] when a *previous, different* version was
  /// accepted — the section 2.3 re-acceptance case.
  final String updatedNotice;

  /// What a screen reader announces when keyboard focus reaches the scrolling
  /// agreement, which is a Tab stop so it can be scrolled from the keyboard.
  ///
  /// It names the region rather than repeating [title]: the dialog is already
  /// announced by its title as focus enters it.
  final String documentLabel;

  /// Returns a copy with the given fields replaced.
  CruxEulaStrings copyWith({
    String? title,
    String? subtitle,
    String? acceptCheckboxLabel,
    String? acceptButton,
    String? declineButton,
    String? openOnline,
    String? openSourceNote,
    String? updatedNotice,
    String? documentLabel,
  }) {
    return CruxEulaStrings(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      acceptCheckboxLabel: acceptCheckboxLabel ?? this.acceptCheckboxLabel,
      acceptButton: acceptButton ?? this.acceptButton,
      declineButton: declineButton ?? this.declineButton,
      openOnline: openOnline ?? this.openOnline,
      openSourceNote: openSourceNote ?? this.openSourceNote,
      updatedNotice: updatedNotice ?? this.updatedNotice,
      documentLabel: documentLabel ?? this.documentLabel,
    );
  }
}
