// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The line that turns a greyed control into an explanation.
///
/// A settings control disabled with no reason given is a support ticket.
/// *"Locked by your organization's policy file"* is not — the user stops
/// looking for the bug, and the person they would have called knows
/// immediately where to look instead.
///
/// Deliberately in `crux_settings_ui` rather than in `crux_policy`. That
/// package is pure Dart and must stay that way — the `lintcrux` CLI reads a
/// policy file from a bare Dart process — and a widget in it would be the
/// first Flutter import. It is also deliberately not four per-product copies:
/// the whole point is that a locked control looks and reads identically in all
/// four products.
///
/// Pair it with a disabled control, never instead of one. It explains a lock;
/// it does not create one.
class CruxPolicyLockNote extends StatelessWidget {
  /// Creates the lock note.
  const CruxPolicyLockNote({required this.message, this.source, super.key});

  /// The localized sentence, e.g. "Locked by your organization's policy file."
  ///
  /// Supplied by the host from its own ARB — this package holds no strings.
  final String message;

  /// Optionally where the file came from, for an administrator reading over
  /// somebody's shoulder. A path, never a value.
  final String? source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 14, color: colour),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              source == null ? message : '$message\n$source',
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}
