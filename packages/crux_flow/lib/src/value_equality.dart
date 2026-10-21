// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Deep equality and hashing for the models' list and map fields, so value
// equality holds after a JSON round trip, which rebuilds every collection.

/// Whether [a] and [b] hold equal elements in the same order.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!deepEquals(a[i], b[i])) return false;
  }
  return true;
}

/// Whether [a] and [b] hold equal entries in the same iteration order.
///
/// Order is part of the value: metric maps keep the order the tool wrote.
bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  final ea = a.entries.toList();
  final eb = b.entries.toList();
  for (var i = 0; i < ea.length; i++) {
    if (ea[i].key != eb[i].key) return false;
    if (!deepEquals(ea[i].value, eb[i].value)) return false;
  }
  return true;
}

/// Structural equality over JSON-shaped values.
bool deepEquals(Object? a, Object? b) {
  if (a is List<Object?> && b is List<Object?>) return listEquals(a, b);
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return mapEquals(a, b);
  }
  return a == b;
}

/// A hash consistent with [deepEquals].
int deepHash(Object? value) => switch (value) {
  final List<Object?> l => Object.hashAll(l.map(deepHash)),
  final Map<Object?, Object?> m => Object.hashAll(
    m.entries.map((e) => Object.hash(e.key, deepHash(e.value))),
  ),
  _ => value.hashCode,
};
