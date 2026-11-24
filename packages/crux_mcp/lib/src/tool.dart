// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_mcp/src/confinement.dart';
import 'package:crux_mcp/src/json_writer.dart';
import 'package:meta/meta.dart';

/// What a field holds, and so its JSON Schema and its check.
enum McpFieldKind {
  /// A string that is not empty and does not start with `-`, so it can never
  /// be read as a flag.
  text,

  /// A string naming a file or directory, held inside the root by
  /// [Confinement] and passed on as the absolute path that was checked.
  path,

  /// A whole number at or above the field's minimum (never negative).
  integer,

  /// `true` passes the flag alone; `false` passes nothing.
  boolean,

  /// A whole tick count, or a string in the link's time grammar: digits,
  /// optionally a fraction, then a unit (`1500ns`, `1.5us`), or digits alone
  /// for ticks.
  time,
}

/// One input property of a tool and the command-line flag it becomes.
@immutable
class McpField {
  /// A field named [name] of [kind] that becomes [flag] and its value, or a
  /// positional argument when [flag] is empty. [many] makes it a list (an
  /// array in the schema, the flag repeated per item). [description], when
  /// given, is sent in the schema and counts against the budget.
  /// [minimum] bounds an integer field (never below 0). [values], on a text
  /// field, lists the only values it accepts: the schema gains an `enum` and
  /// the check refuses any other.
  const McpField(
    this.name, {
    required this.kind,
    this.flag = '',
    this.many = false,
    this.description,
    this.minimum = 0,
    this.values,
  });

  /// The property name.
  final String name;

  /// What it holds.
  final McpFieldKind kind;

  /// The flag it becomes, or empty for a positional argument.
  final String flag;

  /// Whether it is a list.
  final bool many;

  /// What the schema says about it, when anything.
  final String? description;

  /// The least value of an integer field.
  final int minimum;

  /// The only values a text field accepts, in the order the schema lists
  /// them, or null for any value.
  final List<String>? values;

  /// The field's JSON Schema, members in a fixed order.
  Map<String, Object?> schema() {
    final scalar = switch (kind) {
      McpFieldKind.text => <String, Object?>{
        'type': 'string',
        if (values != null) 'enum': values,
      },
      McpFieldKind.path => <String, Object?>{'type': 'string'},
      McpFieldKind.integer => <String, Object?>{'type': 'integer'},
      McpFieldKind.boolean => <String, Object?>{'type': 'boolean'},
      McpFieldKind.time => <String, Object?>{
        'type': <String>['integer', 'string'],
      },
    };
    final schema = many
        ? <String, Object?>{'type': 'array', 'items': scalar}
        : scalar;
    if (description != null) schema['description'] = description;
    return schema;
  }
}

/// What [McpTool.check] made of one call's arguments.
@immutable
sealed class McpArgumentCheck {
  const McpArgumentCheck();
}

/// The arguments were refused; [message] says why, for a `usage_error`.
final class McpArgumentError extends McpArgumentCheck {
  /// A refusal saying [message].
  const McpArgumentError(this.message);

  /// One sentence naming the field and what is wrong.
  final String message;
}

/// The checked arguments of one call.
final class McpArguments extends McpArgumentCheck {
  /// The checked [values] by field name, and the [argv] they become.
  const McpArguments({required this.values, required this.argv});

  /// Each given field's checked value: a path field holds its confined
  /// absolute path (a list of them when it is a list), a time its text.
  final Map<String, Object?> values;

  /// The command-line arguments: each flag and its value, in field order,
  /// then the positional arguments.
  final List<String> argv;
}

/// The files a project names, checked before the command runs.
///
/// Reads [arguments]' project file, filelist or manifest the way the command
/// will, and returns `confinement.confineAll(...)` of every file it names:
/// null when all are inside the root, otherwise the refusal.
typedef McpNamedFileCheck =
    FutureOr<RefusedPath?> Function(
      McpArguments arguments,
      Confinement confinement,
    );

/// A tool: its name, its description, its typed fields and which are
/// required, and how its fields become an argument vector of the command of
/// the same name.
///
/// One table makes both the `inputSchema` a server lists and the command
/// line the server runs, so the two cannot disagree.
@immutable
class McpTool {
  /// A tool. Throws an [ArgumentError] when a name is malformed or repeated,
  /// a required name is not a field, a boolean field has no flag, or an
  /// integer minimum is negative, or a field's `values` are not a non-empty
  /// list of distinct words on a text field.
  McpTool({
    required this.name,
    required this.description,
    required this.fields,
    this.required = const <String>[],
    String? command,
    this.checkNamedFiles,
  }) : command = command ?? name {
    final valid = RegExp(r'^[a-z][a-z0-9_]*$');
    if (!valid.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'not a tool name');
    }
    final seen = <String>{};
    for (final f in fields) {
      if (!valid.hasMatch(f.name) || !seen.add(f.name)) {
        throw ArgumentError.value(f.name, 'fields', 'malformed or repeated');
      }
      if (f.kind == McpFieldKind.boolean && f.flag.isEmpty) {
        throw ArgumentError.value(f.name, 'fields', 'a boolean needs a flag');
      }
      if (f.minimum < 0) {
        throw ArgumentError.value(f.minimum, 'minimum', 'never negative');
      }
      final allowed = f.values;
      if (allowed != null &&
          (f.kind != McpFieldKind.text ||
              allowed.isEmpty ||
              allowed.toSet().length != allowed.length ||
              allowed.any((v) => v.isEmpty || v.startsWith('-')))) {
        throw ArgumentError.value(
          f.name,
          'fields',
          'values need a text field and distinct words that are not flags',
        );
      }
    }
    for (final r in required) {
      if (!seen.contains(r)) {
        throw ArgumentError.value(r, 'required', 'not a field');
      }
    }
  }

  /// The tool's name, as `tools/call` names it.
  final String name;

  /// What it returns and its limits.
  final String description;

  /// Its input properties, in schema and argument order.
  final List<McpField> fields;

  /// The fields a call must give.
  final List<String> required;

  /// The command it runs; the tool's name unless given.
  final String command;

  /// The product's expander for files that name files, when the tool takes
  /// one.
  final McpNamedFileCheck? checkNamedFiles;

  /// The definition `tools/list` sends: `name`, `description` and
  /// `inputSchema` generated from the fields.
  Map<String, Object?> definition() => <String, Object?>{
    'name': name,
    'description': description,
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        for (final f in fields) f.name: f.schema(),
      },
      'required': required,
    },
  };

  /// The definition's size: its compact JSON, in characters.
  int get definitionLength => mcpRenderJsonLine(definition()).length;

  static final RegExp _timeGrammar = RegExp(
    r'^(?:[0-9]+|[0-9]+(?:\.[0-9]+)?(?:fs|ps|ns|us|ms|s))$',
  );

  /// [arguments] checked against the fields, every path held inside
  /// [confinement]: the [McpArguments] to run, or an [McpArgumentError]
  /// saying what is wrong, for a `usage_error`. Nothing is opened but what
  /// the confinement check reads.
  ///
  /// Checked in this order, so one bad call always gets the same message:
  /// the arguments are one object; no unknown field; every required field
  /// given; then each field, in field order, for its type and its value.
  McpArgumentCheck check(Object? arguments, Confinement confinement) {
    final Map<String, Object?> given;
    switch (arguments) {
      case null:
        given = const <String, Object?>{};
      case final Map<String, Object?> m:
        given = m;
      default:
        return const McpArgumentError('the arguments are one object');
    }
    for (final key in given.keys) {
      if (!fields.any((f) => f.name == key)) {
        return McpArgumentError('unknown field `$key` for $name');
      }
    }
    for (final r in required) {
      if (!given.containsKey(r)) {
        return McpArgumentError('`$r` is required for $name');
      }
    }
    final values = <String, Object?>{};
    final flags = <String>[];
    final positional = <String>[];
    for (final f in fields) {
      if (!given.containsKey(f.name)) continue;
      final value = given[f.name];
      final List<Object?> items;
      if (f.many) {
        if (value is! List<Object?>) {
          return McpArgumentError('`${f.name}` is a list');
        }
        items = value;
      } else {
        items = <Object?>[value];
      }
      final checked = <Object?>[];
      for (final item in items) {
        final result = _checkItem(f, item, confinement);
        if (result is McpArgumentError) return result;
        checked.add(result);
        if (f.kind == McpFieldKind.boolean) {
          if (result == true) flags.add(f.flag);
          continue;
        }
        final text = '$result';
        if (f.flag.isEmpty) {
          positional.add(text);
        } else {
          flags
            ..add(f.flag)
            ..add(text);
        }
      }
      values[f.name] = f.many
          ? List<Object?>.unmodifiable(checked)
          : checked[0];
    }
    return McpArguments(
      values: Map<String, Object?>.unmodifiable(values),
      argv: List<String>.unmodifiable(<String>[...flags, ...positional]),
    );
  }

  /// The checked value of one item, or an [McpArgumentError].
  Object _checkItem(McpField f, Object? item, Confinement confinement) {
    switch (f.kind) {
      case McpFieldKind.text:
        if (item is! String) return McpArgumentError('`${f.name}` is text');
        if (item.isEmpty || item.startsWith('-')) {
          return McpArgumentError(
            '`$item` is not a valid value for ${f.name}',
          );
        }
        final allowed = f.values;
        if (allowed != null && !allowed.contains(item)) {
          // The wording a command gives for a flag value it does not know:
          // "`--kind x` is not cell, net, port or module".
          final head = allowed.length == 1
              ? allowed.single
              : '${allowed.sublist(0, allowed.length - 1).join(', ')} '
                    'or ${allowed.last}';
          final given = f.flag.isEmpty ? item : '${f.flag} $item';
          return McpArgumentError('`$given` is not $head');
        }
        return item;
      case McpFieldKind.path:
        if (item is! String) return McpArgumentError('`${f.name}` is text');
        return switch (confinement.confine(item)) {
          ConfinedPath(:final path) => path,
          RefusedPath(:final message) => McpArgumentError(message),
        };
      case McpFieldKind.integer:
        if (item is! int || item < f.minimum) {
          return McpArgumentError(
            '`${f.name}` is a whole number, ${f.minimum} or more',
          );
        }
        return item;
      case McpFieldKind.boolean:
        if (item is! bool) {
          return McpArgumentError('`${f.name}` is true or false');
        }
        return item;
      case McpFieldKind.time:
        if (item is int && item >= 0) return '$item';
        if (item is String && _timeGrammar.hasMatch(item)) return item;
        return McpArgumentError(
          '`${f.name}` is a tick count or a time such as 1500ns',
        );
    }
  }
}
