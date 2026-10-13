// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart' show PolicySource;
import 'package:crux_settings_ui/src/crux_policy_lock_note.dart';
import 'package:flutter/material.dart';

/// The English lock sentence, used when no [CruxPolicyLockScope] is mounted.
///
/// Written in the voice of the licence panel's refused-policy notice, so "your
/// organization set this" reads the same whether the file was refused or one
/// of its values is in force: what the file did, what that means here, and
/// who to ask.
const String kCruxPolicyLockNoteEn =
    "Your organization's policy file sets this, so it can't be changed here. "
    'Ask your administrator.';

/// Supplies the localized lock sentence to every [CruxPolicyLock] below it.
///
/// Mount it once, above the app's navigator (a `MaterialApp.builder` is the
/// natural place), so a locked control in a dialog reads the same sentence as
/// one in Settings. Without a scope the sentence is [kCruxPolicyLockNoteEn].
class CruxPolicyLockScope extends InheritedWidget {
  /// Provides [message] to the subtree.
  const CruxPolicyLockScope({
    required this.message,
    required super.child,
    super.key,
  });

  /// The localized lock sentence.
  final String message;

  /// The sentence in force at [context]: the nearest scope's, else English.
  static String messageOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CruxPolicyLockScope>()
          ?.message ??
      kCruxPolicyLockNoteEn;

  @override
  bool updateShouldNotify(CruxPolicyLockScope oldWidget) =>
      message != oldWidget.message;
}

/// Where a [CruxPolicyLock] puts its note relative to the control.
enum CruxPolicyLockNotePlacement {
  /// Above the control: for a block of controls, where a note under the block
  /// would be read last.
  above,

  /// Below the control, as a caption: for a single control in a row.
  below,
}

/// A setting whose value the organization's policy file may have locked.
///
/// Keyed on the resolved [source], which is what every policy-backed setting
/// already has in hand from the `crux_policy` resolver. While it is
/// [PolicySource.policyLocked], the control is shown dimmed and inert (no
/// pointer, no focus) and the lock note explains why. Every other source
/// renders [child] untouched.
///
/// This is the suite's one mount of [CruxPolicyLockNote]: a product hands over
/// the source and the control rather than building the note itself, so a
/// locked control looks, reads and behaves identically in all four products.
/// The sentence comes from [CruxPolicyLockScope].
///
/// Shown, not hidden: an engineer asking "what is my retention?" or "is the
/// server on?" needs the organization's value on screen.
class CruxPolicyLock extends StatelessWidget {
  /// Wraps [child] in the lock for [source].
  ///
  /// [child] may be omitted where there is nothing to disable and the lock is
  /// only a statement, for example a list of packs the organization made
  /// mandatory.
  const CruxPolicyLock({
    required this.source,
    this.child,
    this.detail,
    this.placement = CruxPolicyLockNotePlacement.above,
    super.key,
  });

  /// Where the value in force came from.
  final PolicySource source;

  /// The control the lock applies to.
  final Widget? child;

  /// One further sentence on what this particular lock does, when that is not
  /// obvious from the control, for example that locked packs outrank the
  /// user's own. Shown on its own line under the lock sentence. Never a value.
  final String? detail;

  /// Where the note goes relative to [child].
  final CruxPolicyLockNotePlacement placement;

  /// Whether the organization locked this setting.
  bool get isLocked => source == PolicySource.policyLocked;

  @override
  Widget build(BuildContext context) {
    final control = child;
    if (!isLocked) return control ?? const SizedBox.shrink();
    final sentence = CruxPolicyLockScope.messageOf(context);
    final note = CruxPolicyLockNote(
      message: detail == null ? sentence : '$sentence\n$detail',
    );
    if (control == null) return note;
    final inert = Opacity(
      opacity: 0.6,
      child: IgnorePointer(child: ExcludeFocus(child: control)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: placement == CruxPolicyLockNotePlacement.above
          ? [note, const SizedBox(height: 8), inert]
          : [inert, note],
    );
  }
}
