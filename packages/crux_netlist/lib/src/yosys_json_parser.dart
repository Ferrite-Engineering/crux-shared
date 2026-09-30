// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_netlist/src/netlist_model.dart';

/// Thrown by [YosysJsonParser] when the raw output from `yosys -p
/// "write_json …"` cannot be decoded into a [NetlistModel].
///
/// Wraps the underlying [FormatException] / cast / type errors with a
/// short, user-actionable message. The original error (if any) is
/// retained via [cause] so the diagnostics panel can show stack details
/// in debug builds.
class YosysJsonParseException implements Exception {
  /// Creates a parse exception.
  const YosysJsonParseException(this.message, {this.cause});

  /// One-line explanation of what went wrong, suitable for surfacing as
  /// a snackbar or diagnostics-panel header.
  final String message;

  /// The underlying error that triggered this exception. May be `null`
  /// when the parser detected a logical inconsistency (e.g. missing
  /// `modules` key) rather than catching an error.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'YosysJsonParseException: $message'
      : 'YosysJsonParseException: $message (cause: $cause)';
}

/// Parses raw `write_json` output (from a `YosysRunSuccess`) into a typed
/// [NetlistModel].
///
/// The parser is intentionally thin: it decodes the JSON envelope, asserts
/// the top-level shape, and hands the resulting `Map` to
/// [NetlistModel.fromJson]. Any failure surfaces as a
/// [YosysJsonParseException] with a clear message — never a raw cast or
/// format error — so callers don't need to wrap calls in
/// `try`/`catch (Object)`.
class YosysJsonParser {
  /// Creates a parser. No state; instances are interchangeable.
  const YosysJsonParser();

  /// Parses [rawJson] into a [NetlistModel].
  ///
  /// Throws [YosysJsonParseException] when the input cannot be decoded
  /// as JSON, is not a JSON object, or violates the Yosys schema (e.g.
  /// missing `modules`). The exception's `message` is short enough to be
  /// rendered as a snackbar; the original [Object] is retained as
  /// `cause` for diagnostics.
  NetlistModel parse(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (e) {
      throw YosysJsonParseException(
        'Yosys output is not valid JSON',
        cause: e,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const YosysJsonParseException(
        'Yosys output is not a JSON object',
      );
    }
    try {
      return NetlistModel.fromJson(decoded);
    } on FormatException catch (e) {
      throw YosysJsonParseException(e.message, cause: e);
    } on Object catch (e) {
      // Yosys JSON whose nested objects don't match expected types
      // surfaces here as a `TypeError` from inside fromJson's casts.
      // We rewrap as a parse exception so callers don't have to catch
      // `Error` types directly.
      if (e is YosysJsonParseException) rethrow;
      throw YosysJsonParseException(
        'Yosys output has unexpected types: $e',
        cause: e,
      );
    }
  }
}
