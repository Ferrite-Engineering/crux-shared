// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Unique identity for a workspace tab.
///
/// Wraps a UUID v4 string. Equality and hash are value-based (UUID string
/// comparison) so [TabId] can be used as a [Map] key and in [Set] operations,
/// and survives serialization to / from the workspace document.
///
/// Pure Dart — no Flutter imports.
@immutable
class TabId {
  /// Creates a [TabId] from an existing UUID string.
  ///
  /// Prefer [TabId.generate] for new tabs. Use [TabId.fromString] only when
  /// deserializing a previously-persisted id.
  const TabId._(this._value);

  /// Generates a new unique [TabId] using UUID v4.
  factory TabId.generate() => TabId._(_uuid.v4());

  /// Recreates a [TabId] from a previously-serialized UUID string.
  ///
  /// No validation is performed — the caller is responsible for supplying
  /// a well-formed UUID string.
  factory TabId.fromString(String value) => TabId._(value);

  final String _value;
  static const _uuid = Uuid();

  /// The underlying UUID string.
  String get value => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabId &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'TabId($_value)';
}
