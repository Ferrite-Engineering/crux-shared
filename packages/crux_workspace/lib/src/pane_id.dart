// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// Unique identity for a workspace pane.
///
/// Wraps a UUID v4 string. Equality and hash are value-based so [PaneId]
/// can be used as a [Map] key, in [Set] operations, and survive serialization
/// to / from the workspace document.
///
/// Pure Dart — no Flutter imports.
@immutable
class PaneId {
  const PaneId._(this._value);

  /// Generates a new unique [PaneId] using UUID v4.
  factory PaneId.generate() => PaneId._(_uuid.v4());

  /// Recreates a [PaneId] from a previously-serialized UUID string.
  ///
  /// No validation is performed — the caller is responsible for supplying
  /// a well-formed UUID string.
  factory PaneId.fromString(String value) => PaneId._(value);

  /// A fixed sentinel value used as the implicit "primary pane" id for live
  /// tabs created before a workspace has been hydrated. Useful so per-product
  /// in-memory tab models can declare `paneId` as a required, non-null field
  /// with a safe default for tests and synthetic placeholders. Concrete
  /// workspace panes always carry a freshly-generated id; this sentinel is
  /// never actually persisted into a workspace document.
  static const PaneId primary = PaneId._(_primaryUuid);
  static const String _primaryUuid = '00000000-0000-0000-0000-000000000001';

  final String _value;
  static const _uuid = Uuid();

  /// The underlying UUID string.
  String get value => _value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaneId &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'PaneId($_value)';
}
