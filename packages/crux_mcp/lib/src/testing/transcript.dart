// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/src/testing/scripted_client.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A conformance transcript: request lines in, the answers expected out.
///
/// Language neutral: a JSON file any implementation can replay. The file is
/// an object with `name`, `description` and `steps`. Each step sends one
/// line (`send`, with `{{name}}` replaced by an earlier binding) or a line
/// of `sendOversized` bytes of `x`, then reads one answer and matches it
/// against `expect`; an `expect` of null reads nothing, for a notification
/// that is not answered. `bind` names values taken from the answer, by JSON
/// pointer, or by an object of three pointers: `from` (an array), `where`
/// (a member that must exist in the element chosen, the first that has it)
/// and `take` (the value in that element).
///
/// A pattern is matched against the parsed answer: an object must have
/// exactly the pattern's members (a member whose name ends in `?` may be
/// absent), an array the same length, and a scalar must be equal. The
/// strings `$any`, `$string`, `$integer` and `$boolean` match any value of
/// that kind; `{"$each": p}` matches a non-empty array whose every element
/// matches `p`; `{"$json": p}` matches a string that parses as JSON matching
/// `p`, where the members of every object must also come in the pattern's
/// order.
@immutable
class McpTranscript {
  const McpTranscript._(this.name, this.description, this.steps);

  /// Reads a transcript from its JSON text.
  factory McpTranscript.parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) {
      throw const FormatException('a transcript is an object');
    }
    final name = json['name'];
    final steps = json['steps'];
    if (name is! String || steps is! List<Object?> || steps.isEmpty) {
      throw const FormatException('a transcript has a name and steps');
    }
    return McpTranscript._(
      name,
      json['description'] is String ? json['description']! as String : '',
      <Map<String, Object?>>[
        for (final step in steps)
          if (step is Map<String, Object?>)
            step
          else
            throw const FormatException('a step is an object'),
      ],
    );
  }

  /// Every `*.json` transcript in [directory], by file name.
  static List<McpTranscript> loadDirectory(String directory) {
    final files =
        Directory(directory)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return <McpTranscript>[
      for (final f in files) McpTranscript.parse(f.readAsStringSync()),
    ];
  }

  /// Its name.
  final String name;

  /// What it holds a server to.
  final String description;

  /// Its steps, as read.
  final List<Map<String, Object?>> steps;

  /// Replays the transcript through [client]. Returns every mismatch, each
  /// naming its step; empty when the server answered as expected.
  Future<List<String>> run(McpScriptedClient client) async {
    final bindings = <String, Object?>{};
    final problems = <String>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final where = '$name step ${i + 1}';
      final send = step['send'];
      final oversized = step['sendOversized'];
      if (send is String) {
        client.send(_substitute(send, bindings));
      } else if (oversized is int) {
        client.sendBytes(<int>[...List<int>.filled(oversized, 0x78), 0x0A]);
      } else {
        problems.add('$where: no send');
        continue;
      }
      if (!step.containsKey('expect') || step['expect'] == null) continue;
      final line = await client.next();
      if (line == null) {
        problems.add('$where: the server ended without answering');
        break;
      }
      final Object? actual;
      try {
        actual = jsonDecode(line);
      } on FormatException {
        problems.add('$where: the answer is not JSON: $line');
        continue;
      }
      final found = mcpMatchPattern(
        step['expect'],
        actual,
        bindings: bindings,
      );
      problems.addAll(found.map((m) => '$where: $m'));
      final bind = step['bind'];
      if (bind is Map<String, Object?>) {
        for (final entry in bind.entries) {
          final value = _select(actual, entry.value);
          if (value == null) {
            problems.add('$where: nothing to bind to ${entry.key}');
          } else {
            bindings[entry.key] = value;
          }
        }
      }
    }
    return problems;
  }
}

String _substitute(String text, Map<String, Object?> bindings) =>
    text.replaceAllMapped(RegExp(r'\{\{([a-z_]+)\}\}'), (m) {
      final value = bindings[m.group(1)];
      return value is String ? value : jsonEncode(value);
    });

Object? _pointer(Object? value, String pointer) {
  if (pointer.isEmpty) return value;
  var current = value;
  for (final raw in pointer.substring(1).split('/')) {
    final token = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map<String, Object?> && current.containsKey(token)) {
      current = current[token];
    } else if (current is List<Object?> &&
        int.tryParse(token) != null &&
        int.parse(token) < current.length) {
      current = current[int.parse(token)];
    } else {
      return null;
    }
  }
  return current;
}

Object? _select(Object? actual, Object? selector) {
  if (selector is String) return _pointer(actual, selector);
  if (selector is Map<String, Object?>) {
    final from = _pointer(actual, selector['from']! as String);
    if (from is! List<Object?>) return null;
    for (final element in from) {
      if (_pointer(element, selector['where']! as String) != null) {
        return _pointer(element, selector['take']! as String);
      }
    }
  }
  return null;
}

/// The ways [actual] does not match [pattern] (see [McpTranscript] for the
/// pattern language); empty when it matches. `{{name}}` in a pattern string
/// is replaced from [bindings] first.
List<String> mcpMatchPattern(
  Object? pattern,
  Object? actual, {
  Map<String, Object?> bindings = const <String, Object?>{},
  String path = r'$',
  bool ordered = false,
}) {
  final problems = <String>[];
  void fail(String why) => problems.add('$path: $why');
  switch (pattern) {
    case r'$any':
      break;
    case r'$string':
      if (actual is! String) fail('expected a string, found $actual');
    case r'$integer':
      if (actual is! int) fail('expected an integer, found $actual');
    case r'$boolean':
      if (actual is! bool) fail('expected a boolean, found $actual');
    case final String s:
      final want = _substitute(s, bindings);
      if (actual != want) {
        fail('expected ${jsonEncode(want)}, found ${jsonEncode(actual)}');
      }
    case final Map<String, Object?> m when m.containsKey(r'$json'):
      if (actual is! String) {
        fail('expected a JSON text, found $actual');
        break;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(actual);
      } on FormatException {
        fail('the text is not JSON');
        break;
      }
      problems.addAll(
        mcpMatchPattern(
          m[r'$json'],
          decoded,
          bindings: bindings,
          path: '$path<json>',
          ordered: true,
        ),
      );
    case final Map<String, Object?> m when m.containsKey(r'$each'):
      if (actual is! List<Object?> || actual.isEmpty) {
        fail('expected a non-empty array, found $actual');
        break;
      }
      for (var i = 0; i < actual.length; i++) {
        problems.addAll(
          mcpMatchPattern(
            m[r'$each'],
            actual[i],
            bindings: bindings,
            path: '$path[$i]',
            ordered: ordered,
          ),
        );
      }
    case final Map<String, Object?> m:
      if (actual is! Map<String, Object?>) {
        fail('expected an object, found ${jsonEncode(actual)}');
        break;
      }
      final wanted = <String>[];
      for (final key in m.keys) {
        final optional = key.endsWith('?');
        final name = optional ? key.substring(0, key.length - 1) : key;
        if (!actual.containsKey(name)) {
          if (!optional) fail('missing member "$name"');
          continue;
        }
        wanted.add(name);
        problems.addAll(
          mcpMatchPattern(
            m[key],
            actual[name],
            bindings: bindings,
            path: '$path.$name',
            ordered: ordered,
          ),
        );
      }
      for (final key in actual.keys) {
        if (!m.containsKey(key) && !m.containsKey('$key?')) {
          fail('unexpected member "$key"');
        }
      }
      if (ordered) {
        final order = actual.keys.where(wanted.contains).toList();
        if (order.join(',') != wanted.join(',')) {
          fail(
            'members in the order ${order.join(', ')}, not '
            '${wanted.join(', ')}',
          );
        }
      }
    case final List<Object?> l:
      if (actual is! List<Object?> || actual.length != l.length) {
        fail('expected ${l.length} elements, found ${jsonEncode(actual)}');
        break;
      }
      for (var i = 0; i < l.length; i++) {
        problems.addAll(
          mcpMatchPattern(
            l[i],
            actual[i],
            bindings: bindings,
            path: '$path[$i]',
            ordered: ordered,
          ),
        );
      }
    default:
      if (actual != pattern) {
        fail('expected ${jsonEncode(pattern)}, found ${jsonEncode(actual)}');
      }
  }
  return problems;
}
