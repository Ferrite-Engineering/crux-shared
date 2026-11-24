// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A value that writes itself as JSON: an object whose members come in a
/// fixed order.
abstract interface class McpJsonValue {
  /// The JSON form: a map (members in insertion order), list, string,
  /// number, boolean or null, possibly holding further [McpJsonValue]s.
  Object? toJson();
}

/// [value] as the suite's documents write JSON: members in insertion order,
/// indented with two spaces, `": "` between a key and its value, an empty
/// array as `[]` and an empty object as `{}`, and no trailing newline.
///
/// Strings escape `"`, `\`, newline, carriage return and tab by name, any
/// other character below U+0020 as `\u00xx` in lower-case hex, and nothing
/// else: `/`, DEL and every non-ASCII character are written as they are.
/// These are the rules of the reference server's writer, so a document this
/// writes is byte for byte the one that writer makes from the same values.
///
/// Accepts null, [bool], [int], finite [double], [String], [List], [Map]
/// with [String] keys and [McpJsonValue]. Anything else, or a non-finite
/// number, throws an [ArgumentError]: a document that cannot be written is a
/// bug in the code that builds it, never something to guess at.
String mcpRenderJson(Object? value) {
  final out = StringBuffer();
  _write(value, 0, out);
  return out.toString();
}

/// [value] as one compact JSON line, for a protocol message.
///
/// The same escaping as [mcpRenderJson], with no white space between tokens.
String mcpRenderJsonLine(Object? value) {
  final out = StringBuffer();
  _write(value, -1, out);
  return out.toString();
}

void _write(Object? value, int depth, StringBuffer out) {
  final compact = depth < 0;
  switch (value) {
    case null:
      out.write('null');
    case final bool b:
      out.write(b ? 'true' : 'false');
    case final int n:
      out.write(n);
    case final double d:
      if (!d.isFinite) {
        throw ArgumentError.value(d, 'value', 'JSON has no non-finite number');
      }
      out.write(d.toString().replaceFirst('e+', 'e'));
    case final String s:
      _escape(s, out);
    case final McpJsonValue v:
      _write(v.toJson(), depth, out);
    case final List<Object?> items:
      if (items.isEmpty) {
        out.write('[]');
        return;
      }
      out.write(compact ? '[' : '[\n');
      for (var i = 0; i < items.length; i++) {
        if (!compact) _pad(depth + 1, out);
        _write(items[i], compact ? -1 : depth + 1, out);
        if (i + 1 < items.length) out.write(compact ? ',' : ',\n');
      }
      if (!compact) {
        out.write('\n');
        _pad(depth, out);
      }
      out.write(']');
    case final Map<Object?, Object?> members:
      if (members.isEmpty) {
        out.write('{}');
        return;
      }
      out.write(compact ? '{' : '{\n');
      var i = 0;
      for (final entry in members.entries) {
        final key = entry.key;
        if (key is! String) {
          throw ArgumentError.value(key, 'key', 'a JSON member name is text');
        }
        if (!compact) _pad(depth + 1, out);
        _escape(key, out);
        out.write(compact ? ':' : ': ');
        _write(entry.value, compact ? -1 : depth + 1, out);
        i++;
        if (i < members.length) out.write(compact ? ',' : ',\n');
      }
      if (!compact) {
        out.write('\n');
        _pad(depth, out);
      }
      out.write('}');
    default:
      throw ArgumentError.value(
        value,
        'value',
        'not a JSON value (${value.runtimeType})',
      );
  }
}

void _pad(int depth, StringBuffer out) {
  for (var i = 0; i < depth; i++) {
    out.write('  ');
  }
}

void _escape(String s, StringBuffer out) {
  out.write('"');
  for (final rune in s.runes) {
    switch (rune) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (rune < 0x20) {
          out
            ..write(r'\u')
            ..write(rune.toRadixString(16).padLeft(4, '0'));
        } else {
          out.writeCharCode(rune);
        }
    }
  }
  out.write('"');
}
