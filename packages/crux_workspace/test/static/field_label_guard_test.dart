// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: no text field in any package's `lib/` takes its label from
// `InputDecoration.labelText` (or `InputDecoration.label`).
//
// The Crux Desktop theme never floats a label (`FloatingLabelBehavior.never`),
// so a decoration label is drawn only while the field is empty. A field that
// holds a value, an issue summary, a licence key, a hex colour, then shows
// bare text with nothing to say what it is. The desktop idiom is a label in
// its own widget beside the field: `CruxFormRow` where the package can depend
// on `crux_settings_ui`, an equivalent label-left layout where it cannot, and
// a `hintText` plus an explicit `Semantics` label for a search box whose
// purpose stays obvious when it holds text.
//
// The scan reads syntax only (`parseString`), so a comment or a string that
// mentions the name is not a finding, and `labelTextStyle` (a popup-menu
// theme field) is a different name.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Sites that may keep a decoration label, as `path:line` relative to the
/// workspace root, each with the reason it is safe. Empty on purpose: an
/// entry is a field that loses its label while it holds a value.
const Map<String, String> _allowlist = <String, String>{};

/// One decoration label found in a source: its 1-based line and the argument
/// name.
class _Hit {
  const _Hit(this.line, this.name);

  final int line;
  final String name;
}

/// Every `labelText:` argument in [source], and every `label:` argument of an
/// `InputDecoration(...)` construction.
List<_Hit> _decorationLabels(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _LabelVisitor(result.lineInfo);
  result.unit.accept(visitor);
  return visitor.hits;
}

class _LabelVisitor extends RecursiveAstVisitor<void> {
  _LabelVisitor(this._lines);

  final LineInfo _lines;
  final List<_Hit> hits = <_Hit>[];

  @override
  void visitNamedExpression(NamedExpression node) {
    final name = node.name.label.name;
    if (name == 'labelText' || (name == 'label' && _inInputDecoration(node))) {
      hits.add(_Hit(_lines.getLocation(node.offset).lineNumber, name));
    }
    super.visitNamedExpression(node);
  }

  bool _inInputDecoration(NamedExpression node) {
    final call = node.parent?.parent;
    final callee = switch (call) {
      MethodInvocation() => call.methodName.name,
      InstanceCreationExpression() => call.constructorName.type.name.lexeme,
      _ => null,
    };
    return callee == 'InputDecoration';
  }
}

/// The crux-shared workspace root, found by walking up from the test's working
/// directory until the root `pubspec.yaml` naming the workspace is found.
String _workspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: crux_shared_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate the crux-shared workspace root from '
    '${Directory.current.path}',
  );
}

/// Every hand-written `.dart` file under a package `lib/`.
List<File> _libFiles(String root) {
  final packages = Directory(p.join(root, 'packages'));
  final files = <File>[
    for (final entry in packages.listSync())
      if (entry is Directory &&
          Directory(p.join(entry.path, 'lib')).existsSync())
        ...Directory(p.join(entry.path, 'lib'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void main() {
  group('the scanner', () {
    test('finds labelText: in code and nothing in prose or strings', () {
      const source = '''
// labelText: in a comment is prose.
const note = 'labelText: in a string is text';
final a = InputDecoration(labelText: 'Name');
final b = const InputDecoration(
  hintText: 'x',
  labelText: 'Other',
);
''';
      expect(_decorationLabels(source).map((h) => h.line), [3, 6]);
    });

    test('does not mistake another name for the label', () {
      const source = '''
final a = PopupMenuThemeData(labelTextStyle: null);
final b = TextButton.icon(label: Text('x'), icon: null, onPressed: null);
''';
      expect(_decorationLabels(source), isEmpty);
    });

    test('finds the widget label of an InputDecoration', () {
      const source = '''
final a = InputDecoration(label: Text('Name'));
''';
      expect(_decorationLabels(source).map((h) => h.name), ['label']);
    });
  });

  test('no text field labels itself with an InputDecoration label', () {
    final root = _workspaceRoot();
    final files = _libFiles(root);
    expect(
      files.length,
      greaterThan(100),
      reason: 'expected every package lib/ to be discovered',
    );

    final offenders = <String>[];
    for (final file in files) {
      final relative = p.posix.joinAll(
        p.split(p.relative(file.path, from: root)),
      );
      for (final hit in _decorationLabels(file.readAsStringSync())) {
        final site = '$relative:${hit.line}';
        if (!_allowlist.containsKey(site)) offenders.add('$site (${hit.name})');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A decoration label is drawn only while the field is empty under '
          'the Crux Desktop theme, so a field holding a value loses its '
          'label. Put the label in a CruxFormRow (crux_settings_ui), or in '
          'an equivalent always-visible label beside the field; for a search '
          'box, use hintText with an explicit Semantics label.\n'
          '${offenders.join('\n')}',
    );

    for (final entry in _allowlist.entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key} needs a reason');
    }
  });
}
