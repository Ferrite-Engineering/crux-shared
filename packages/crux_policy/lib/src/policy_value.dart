// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One settable value from the policy file, and whether the user may change it.
///
/// Every settable key (<https://edacrux.app/policy-reference#lock>) takes either the bare form — a value the user
/// may still change — or the object form `{"value": …, "locked": true}`. The
/// bare form is sugar for `locked: false`, and a parser must accept both.
@immutable
class PolicyValue<T extends Object> {
  /// Creates a value.
  const PolicyValue(this.value, {this.locked = false});

  /// The value the organization set.
  final T value;

  /// Whether the user is forbidden from changing it.
  final bool locked;

  @override
  bool operator ==(Object other) =>
      other is PolicyValue<T> && other.value == value && other.locked == locked;

  @override
  int get hashCode => Object.hash(value, locked);

  @override
  String toString() => 'PolicyValue($value, locked: $locked)';
}

/// Why a key in the file was not applied.
///
/// An invalid key (<https://edacrux.app/policy-reference#invalid>) is **skipped**, resolution continues at the next
/// level down, and the skip is **reported** — because a silently-ignored lock
/// is a policy the administrator believes is in force and is not.
@immutable
class PolicyDiagnostic {
  /// Creates a diagnostic.
  const PolicyDiagnostic({required this.key, required this.reason});

  /// Dotted path of the offending key, e.g. `suite.updateChannel`.
  final String key;

  /// What was wrong, for a human reading `crux-policy lint`.
  final String reason;

  @override
  String toString() => '$key: $reason';
}
