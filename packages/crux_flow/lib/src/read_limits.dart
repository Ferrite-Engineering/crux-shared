// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Why a flow input could not be read.
enum FlowReadFailure {
  /// The input is larger than [FlowInputLimits.maxBytes].
  tooLarge,

  /// The JSON nests deeper than [FlowInputLimits.maxJsonDepth].
  tooDeep,

  /// The bytes are not UTF-8, not JSON, or not the shape the reader expects.
  malformed,

  /// A number the reader needs is not finite (`1e999` decodes to infinity).
  nonFinite,
}

/// A flow input that could not be read, and why.
///
/// Every reader and every `fromJson` in this package throws this and nothing
/// else for bad input, so a caller that catches it has caught every way a
/// hostile or truncated file can fail. It is a [FormatException], so code
/// that already catches those keeps working.
class FlowReadException extends FormatException {
  /// Creates the exception. [message] names the field where one is known and
  /// never repeats more than a short prefix of the offending input.
  const FlowReadException(this.failure, super.message);

  /// The class of failure.
  final FlowReadFailure failure;

  @override
  String toString() => 'FlowReadException(${failure.name}): $message';
}

/// The bounds every reader applies before it trusts an input.
///
/// A run directory is user-controlled and may come from someone else's CI
/// artifact, so nothing is read without a byte cap, and no JSON is decoded
/// without a depth cap.
@immutable
class FlowInputLimits {
  /// Creates limits.
  const FlowInputLimits({
    this.maxBytes = 64 * 1024 * 1024,
    this.maxJsonDepth = 64,
    this.maxMetricKeyLength = 256,
    this.maxLineLength = 64 * 1024,
  });

  /// The defaults: 64 MiB per file (a full-device `detailed_net_timings`
  /// reaches tens of megabytes), JSON nested 64 deep, metric keys of 256
  /// characters and log lines of 64 KiB.
  static const FlowInputLimits defaults = FlowInputLimits();

  /// The largest input read, in bytes.
  final int maxBytes;

  /// The deepest JSON nesting accepted; every report this package reads is
  /// under ten levels deep.
  final int maxJsonDepth;

  /// The longest metric key kept; longer keys are dropped and counted.
  final int maxMetricKeyLength;

  /// The longest log line considered; longer lines are skipped.
  final int maxLineLength;
}

/// The longest stretch of offending input a message repeats.
const int _maxEchoed = 64;

/// [value] described for an error message without repeating more than a
/// short prefix of it.
String describeFlowValue(Object? value) => switch (value) {
  null => 'null',
  final String s when s.length <= _maxEchoed => '"$s"',
  final String s =>
    '"${s.substring(0, _maxEchoed)}..." (${s.length} characters)',
  final num n => '$n',
  final bool b => '$b',
  final List<Object?> l => 'a list of ${l.length}',
  final Map<Object?, Object?> m => 'an object of ${m.length} keys',
  _ => 'a ${value.runtimeType}',
};

/// Throws [FlowReadFailure.tooDeep] when [text] nests JSON arrays or objects
/// deeper than [maxDepth].
///
/// Runs before decoding, in one pass and constant space, so a document of a
/// million opening brackets is refused without being parsed.
void checkJsonDepth(String text, int maxDepth) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == 0x5C) {
        escaped = true;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }
    if (c == 0x22) {
      inString = true;
    } else if (c == 0x5B || c == 0x7B) {
      depth++;
      if (depth > maxDepth) {
        throw FlowReadException(
          FlowReadFailure.tooDeep,
          'JSON nests deeper than $maxDepth levels',
        );
      }
    } else if (c == 0x5D || c == 0x7D) {
      depth--;
    }
  }
}

/// Decodes [bytes] as UTF-8, refusing anything over [limits]' byte cap.
String decodeFlowText(List<int> bytes, FlowInputLimits limits) {
  if (bytes.length > limits.maxBytes) {
    throw FlowReadException(
      FlowReadFailure.tooLarge,
      'input is ${bytes.length} bytes, over the cap of ${limits.maxBytes}',
    );
  }
  try {
    return utf8.decode(bytes);
  } on FormatException catch (e) {
    throw FlowReadException(
      FlowReadFailure.malformed,
      'input is not UTF-8: ${e.message}',
    );
  }
}

/// Decodes [text] as JSON after the byte and depth checks.
Object? decodeFlowJson(String text, FlowInputLimits limits) {
  if (text.length > limits.maxBytes) {
    throw FlowReadException(
      FlowReadFailure.tooLarge,
      'input is ${text.length} characters, over the cap of ${limits.maxBytes}',
    );
  }
  checkJsonDepth(text, limits.maxJsonDepth);
  try {
    return jsonDecode(text);
  } on FormatException catch (e) {
    throw FlowReadException(
      FlowReadFailure.malformed,
      'input is not JSON: ${e.message}',
    );
  }
}

/// Throws [FileSystemException] unless [path], its links followed, is a
/// regular file.
///
/// A run directory is someone else's files: a named pipe blocks the first
/// read for as long as nothing writes to it, and a link to a device such as
/// `/dev/zero` reports a length of zero and never ends. Neither is a report.
void requireRegularFlowFile(String path) {
  if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
    throw FileSystemException('not a regular file', path);
  }
}

/// At most `cap + 1` bytes of the regular file at [path], so a caller can
/// tell a file over [cap] from one at it without reading the rest, even when
/// the file grows after its length was taken.
///
/// Throws [FileSystemException] when [path] is not a regular file
/// ([requireRegularFlowFile]) or cannot be read.
List<int> readFlowBytesSync(String path, int cap) {
  requireRegularFlowFile(path);
  final raf = File(path).openSync();
  try {
    final builder = BytesBuilder(copy: false);
    while (builder.length <= cap) {
      final chunk = raf.readSync(cap + 1 - builder.length);
      if (chunk.isEmpty) break;
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    raf.closeSync();
  }
}

/// Reads the file at [path] whole, refusing it unread when it is larger than
/// [limits]' byte cap.
///
/// Throws [FileSystemException] when the file is absent, unreadable or not a
/// regular file ([requireRegularFlowFile]), which a reader reports as "not
/// run" rather than as a malformed input.
Future<String> readFlowFile(String path, FlowInputLimits limits) async {
  requireRegularFlowFile(path);
  final file = File(path);
  final length = await file.length();
  if (length > limits.maxBytes) {
    throw FlowReadException(
      FlowReadFailure.tooLarge,
      '$path is $length bytes, over the cap of ${limits.maxBytes}',
    );
  }
  // Read no further than one byte past the cap: the length was taken before
  // the read, and a file can grow in between.
  final builder = BytesBuilder(copy: false);
  await file.openRead(0, limits.maxBytes + 1).forEach(builder.add);
  return decodeFlowText(builder.takeBytes(), limits);
}

Never _wrongType(String field, Object? value, String expected) =>
    throw FlowReadException(
      FlowReadFailure.malformed,
      '"$field" is ${describeFlowValue(value)}, expected $expected',
    );

/// [value], read from [field], as a JSON object.
Map<String, Object?> requireObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  _wrongType(field, value, 'an object');
}

/// [value], read from [field], as a JSON object, or an empty one when absent.
Map<String, Object?> optionalObject(Object? value, String field) {
  if (value == null) return const <String, Object?>{};
  return requireObject(value, field);
}

/// [value], read from [field], as a JSON list.
List<Object?> requireList(Object? value, String field) {
  if (value is List<Object?>) return value;
  _wrongType(field, value, 'a list');
}

/// [value], read from [field], as a JSON list, or an empty one when absent.
List<Object?> optionalList(Object? value, String field) {
  if (value == null) return const <Object?>[];
  return requireList(value, field);
}

/// [value], read from [field], as a string.
String requireString(Object? value, String field) {
  if (value is String) return value;
  _wrongType(field, value, 'a string');
}

/// [value], read from [field], as a string, or null when absent.
String? optionalString(Object? value, String field) {
  if (value == null) return null;
  return requireString(value, field);
}

/// [value], read from [field], as an integer.
int requireInt(Object? value, String field) {
  if (value is int) return value;
  _wrongType(field, value, 'an integer');
}

/// [value], read from [field], as an integer, or null when absent.
int? optionalInt(Object? value, String field) {
  if (value == null) return null;
  return requireInt(value, field);
}

/// [value], read from [field], as a boolean.
bool requireBool(Object? value, String field) {
  if (value is bool) return value;
  _wrongType(field, value, 'a boolean');
}

/// [value], read from [field], as a finite number.
double requireFinite(Object? value, String field) {
  if (value is! num) _wrongType(field, value, 'a number');
  final d = value.toDouble();
  if (!d.isFinite) {
    throw FlowReadException(
      FlowReadFailure.nonFinite,
      '"$field" is not a finite number',
    );
  }
  return d;
}

/// [value], read from [field], as a list of strings.
List<String> requireStringList(Object? value, String field) => [
  for (final (i, item) in requireList(value, field).indexed)
    requireString(item, '$field[$i]'),
];

/// [value], read from [field], as a map of string to string.
Map<String, String> requireStringMap(Object? value, String field) => {
  for (final MapEntry(:key, value: item) in requireObject(value, field).entries)
    key: requireString(item, '$field.$key'),
};

/// Converts the [FlowReadException]s [body] throws for a nested field into
/// one naming [where], so an error deep in a document names its path.
T withFlowContext<T>(String where, T Function() body) {
  try {
    return body();
  } on FlowReadException catch (e) {
    throw FlowReadException(e.failure, '$where: ${e.message}');
  }
}
