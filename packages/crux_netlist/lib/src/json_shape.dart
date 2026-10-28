// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Shape checks for the `fromJson` factories, so a wrong-typed field is the
// FormatException their documentation promises rather than a TypeError from a
// cast. Each names the field it was reading.

/// The longest stretch of offending input a message repeats.
const int _maxEchoed = 64;

/// [value] described for an error message, without repeating more than a
/// short prefix of it: a hostile netlist can carry a multi-megabyte value,
/// and the message is copied into logs, the issue reporter's buffer and the
/// interface.
String describeJsonValue(Object? value) => switch (value) {
  null => 'null',
  final String s when s.length <= _maxEchoed => '"$s"',
  final String s => '"${s.substring(0, _maxEchoed)}…" (${s.length} characters)',
  final num n => '$n',
  final bool b => '$b',
  final List<Object?> l => 'a list of ${l.length}',
  final Map<Object?, Object?> m => 'an object of ${m.length} keys',
  _ => 'a ${value.runtimeType}',
};

Never _wrongType(String field, Object? value, String expected) =>
    throw FormatException(
      '"$field" is ${describeJsonValue(value)}, expected $expected',
    );

/// The object at [field] of [json], or an empty one when it is absent.
Map<String, Object?> optionalJsonObject(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value == null) return const <String, Object?>{};
  if (value is Map<String, Object?>) return value;
  _wrongType(field, value, 'an object');
}

/// [value], which was read from [field], as an object.
Map<String, Object?> requireJsonObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  _wrongType(field, value, 'an object');
}

/// The list at [field] of [json], or an empty one when it is absent.
List<Object?> optionalJsonList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) return const <Object?>[];
  if (value is List<Object?>) return value;
  _wrongType(field, value, 'a list');
}

/// [value], which was read from [field], as a list.
List<Object?> requireJsonList(Object? value, String field) {
  if (value is List<Object?>) return value;
  _wrongType(field, value, 'a list');
}

/// The string at [field] of [json], which must be present.
String requireJsonString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) return value;
  _wrongType(field, value, 'a string');
}

/// [value], which was read from [field], as a string.
String requireJsonStringValue(Object? value, String field) {
  if (value is String) return value;
  _wrongType(field, value, 'a string');
}

/// The deepest list or object nesting an attribute, a cell parameter or the
/// creator may carry and still be kept as text.
const int maxJsonValueNesting = 32;

/// [value], which was read from [field], as the string the model keeps for
/// an attribute, a cell parameter or the creator: a string as it is, a
/// number or a boolean in its JSON spelling, null as empty, and a list or an
/// object as Dart prints it, as these always were.
///
/// A list or an object nested more than [maxJsonValueNesting] levels deep
/// is refused before anything prints it. Printing a collection costs time
/// quadratic in its depth (the core library's cycle check scans every
/// enclosing collection at each level), so a value nested a hundred thousand
/// deep either overflowed the stack or, on a thread whose stack held it,
/// spun for minutes. The depth is measured without recursion, and stops at
/// the cap. Yosys writes each of these values as a string or a number.
String jsonScalarString(Object? value, String field) => switch (value) {
  null => '',
  final String s => s,
  final num n => '$n',
  final bool b => '$b',
  _ when _nestedDeeperThan(value, maxJsonValueNesting) => throw FormatException(
    '"$field" is ${describeJsonValue(value)} nested more than '
    '$maxJsonValueNesting levels deep',
  ),
  _ => value.toString(),
};

/// Whether [value] holds lists or objects more than [limit] levels deep,
/// walked with an explicit stack so the walk itself cannot overflow.
bool _nestedDeeperThan(Object? value, int limit) {
  final pending = <(Object?, int)>[(value, 1)];
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeLast();
    final Iterable<Object?> children;
    if (node is List<Object?>) {
      children = node;
    } else if (node is Map<Object?, Object?>) {
      children = node.values;
    } else {
      continue;
    }
    if (depth > limit) return true;
    for (final child in children) {
      if (child is List<Object?> || child is Map<Object?, Object?>) {
        pending.add((child, depth + 1));
      }
    }
  }
  return false;
}

/// Yosys's `hide_name` flag at [json]: an integer, absent meaning 0.
bool readHideName(Map<String, Object?> json) {
  final value = json['hide_name'];
  if (value == null) return false;
  if (value is int) return value != 0;
  _wrongType('hide_name', value, 'an integer');
}

/// Runs [body], prefixing the message of any [FormatException] it throws
/// with [where], so an error deep in the document names its path.
T withJsonContext<T>(String where, T Function() body) {
  try {
    return body();
  } on FormatException catch (e) {
    throw FormatException('$where: ${e.message}');
  }
}
