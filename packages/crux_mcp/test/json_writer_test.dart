// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:test/test.dart';

// Expected texts are written by hand from the reference writer's rules:
// two-space indent, `": "` after a key, `[]` and `{}` when empty, members in
// insertion order; `"`, `\`, newline, carriage return and tab escaped by
// name, other characters below U+0020 as `\u00xx` in lower-case hex, and
// nothing else escaped.
void main() {
  group('mcpRenderJson', () {
    test('indents, orders members as written, writes empties inline', () {
      final text = mcpRenderJson(<String, Object?>{
        'z': 1,
        'a': <Object?>[null, true, false],
        'e': <String, Object?>{},
        'l': <Object?>[],
        'n': <String, Object?>{'k': 'v'},
      });
      expect(
        text,
        '{\n'
        '  "z": 1,\n'
        '  "a": [\n'
        '    null,\n'
        '    true,\n'
        '    false\n'
        '  ],\n'
        '  "e": {},\n'
        '  "l": [],\n'
        '  "n": {\n'
        '    "k": "v"\n'
        '  }\n'
        '}',
      );
    });

    test('escapes exactly the reference set', () {
      expect(
        mcpRenderJson('q" b\\ n\n r\r t\t b\b f\f x\x01 y\x1f'),
        r'"q\" b\\ n\n r\r t\t b\u0008 f\u000c x\u0001 y\u001f"',
      );
    });

    test('leaves slash, DEL and non-ASCII as they are', () {
      expect(mcpRenderJson('/a\x7f µ ✓ 😀'), '"/a\x7f µ ✓ 😀"');
    });

    test('writes numbers in their shortest form', () {
      expect(
        mcpRenderJson(<Object?>[0, -3, 1.5, 1e21]),
        '[\n  0,\n  -3,\n'
        '  1.5,\n  1e21\n]',
      );
    });

    test('the compact form has no white space and parses back', () {
      final value = <String, Object?>{
        'a': <Object?>[1, 'x'],
        'b': <String, Object?>{'c': null},
      };
      final line = mcpRenderJsonLine(value);
      expect(line, '{"a":[1,"x"],"b":{"c":null}}');
      expect(jsonDecode(line), value);
    });

    test('a value that writes itself is written in place', () {
      expect(
        mcpRenderJsonLine(<Object?>[McpTime(5, McpTimeUnit.ns)]),
        '[{"at":5,"unit":"ns"}]',
      );
    });

    test('refuses what is not JSON', () {
      expect(() => mcpRenderJson(double.nan), throwsArgumentError);
      expect(
        () => mcpRenderJson(<Object?, Object?>{1: 2}),
        throwsArgumentError,
      );
      expect(() => mcpRenderJson(DateTime(2000)), throwsArgumentError);
    });
  });
}
