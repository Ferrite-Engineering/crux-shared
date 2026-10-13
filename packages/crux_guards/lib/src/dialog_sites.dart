// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// The functions that open a modal surface: `showDialog`,
/// `showModalBottomSheet` and `showGeneralDialog`, called without a target.
const Set<String> kCruxModalOpeners = <String>{
  'showDialog',
  'showModalBottomSheet',
  'showGeneralDialog',
};

/// The identifiers that mark a dialog as holding typed input.
const Set<String> kCruxTypedInputMarkers = <String>{
  'TextEditingController',
  'TextField',
  'TextFormField',
};

/// One call that opens a modal surface, as [cruxFindDialogSites] reports it.
@immutable
final class CruxDialogSite {
  /// Creates a site.
  const CruxDialogSite({
    required this.path,
    required this.line,
    required this.member,
    required this.opener,
    required this.guarded,
    required this.dismissible,
    required this.referencedTypes,
    required this.namesTypedInput,
  });

  /// The file, as the sources name it.
  final String path;

  /// The 1-based line of the opener's name.
  final int line;

  /// The method, function, constructor or variable that encloses the call:
  /// `show`, `_openSessionDialog`, `Foo.named`. A local function is not a
  /// member; its enclosing member is. `<unit>` when there is none.
  final String member;

  /// `showDialog`, `showModalBottomSheet` or `showGeneralDialog`.
  final String opener;

  /// Whether the call sits inside the arguments of a `ModalGuard.run(...)`
  /// call in the same file.
  final bool guarded;

  /// Whether a scrim click may close the surface: `false` only when the call
  /// passes `barrierDismissible: false` (or `isDismissible: false` to
  /// `showModalBottomSheet`).
  final bool dismissible;

  /// Every capitalised identifier in the call's text: the widget classes its
  /// builder names, among others.
  final Set<String> referencedTypes;

  /// Whether the call's own text names a [kCruxTypedInputMarkers] identifier.
  final bool namesTypedInput;

  /// `path#member`, the key allowances and known-form entries use.
  String get key => '$path#$member';

  @override
  String toString() => '$path:$line ($member, $opener)';
}

/// Every call to a [kCruxModalOpeners] function in [sources].
///
/// Reads the syntax tree of each source (no resolution), so a mention in a
/// comment or a string is not a call, and a `showDialog` wrapped by a
/// `ModalGuard.run` earlier in the file but outside its parentheses is not
/// guarded.
List<CruxDialogSite> cruxFindDialogSites(Iterable<CruxGuardSource> sources) {
  final sites = <CruxDialogSite>[];
  for (final file in sources) {
    parseString(
      content: file.source,
      throwIfDiagnostics: false,
    ).unit.accept(_SiteVisitor(file, sites));
  }
  return sites;
}

class _SiteVisitor extends RecursiveAstVisitor<void> {
  _SiteVisitor(this.file, this.sites);

  final CruxGuardSource file;
  final List<CruxDialogSite> sites;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.target == null && kCruxModalOpeners.contains(name)) {
      final types = <String>{};
      var typedInput = false;
      for (final token in tokensOf(node)) {
        if (token.type != TokenType.IDENTIFIER) continue;
        final lexeme = token.lexeme;
        if (kCruxTypedInputMarkers.contains(lexeme)) typedInput = true;
        if (isTypeName(lexeme)) types.add(lexeme);
      }
      sites.add(
        CruxDialogSite(
          path: file.path,
          line: lineOf(file.source, node.methodName.offset),
          member: enclosingMemberName(node),
          opener: name,
          guarded: _insideModalGuard(node),
          dismissible: !_passesFalse(
            node,
            name == 'showModalBottomSheet'
                ? 'isDismissible'
                : 'barrierDismissible',
          ),
          referencedTypes: types,
          namesTypedInput: typedInput,
        ),
      );
    }
    super.visitMethodInvocation(node);
  }
}

bool _insideModalGuard(AstNode node) {
  for (var p = node.parent; p != null; p = p.parent) {
    if (p is MethodInvocation &&
        p.methodName.name == 'run' &&
        (p.target?.toSource().endsWith('ModalGuard') ?? false)) {
      return true;
    }
  }
  return false;
}

bool _passesFalse(MethodInvocation node, String parameter) {
  for (final argument in node.argumentList.arguments) {
    if (argument is NamedExpression &&
        argument.name.label.name == parameter &&
        argument.expression is BooleanLiteral &&
        !(argument.expression as BooleanLiteral).value) {
      return true;
    }
  }
  return false;
}

/// The tokens from [node]'s first to its last.
Iterable<Token> tokensOf(AstNode node) sync* {
  Token? token = node.beginToken;
  final end = node.endToken;
  while (token != null) {
    yield token;
    if (identical(token, end) || token.type == TokenType.EOF) return;
    token = token.next;
  }
}

/// Whether [lexeme] is spelled like a type: capitalised, after an optional
/// leading underscore.
bool isTypeName(String lexeme) {
  final start = lexeme.startsWith('_') ? 1 : 0;
  if (lexeme.length <= start) return false;
  final c = lexeme.codeUnitAt(start);
  return c >= 0x41 && c <= 0x5A;
}

/// The name of the member that encloses [node], as [CruxDialogSite.member]
/// describes it.
String enclosingMemberName(AstNode node) {
  for (var p = node.parent; p != null; p = p.parent) {
    switch (p) {
      case MethodDeclaration():
        return p.name.lexeme;
      case FunctionDeclaration() when p.parent is CompilationUnit:
        return p.name.lexeme;
      case ConstructorDeclaration():
        final type = p.typeName?.name ?? '';
        final named = p.name?.lexeme;
        return named == null ? type : '$type.$named';
      case VariableDeclaration()
          when p.parent?.parent is FieldDeclaration ||
              p.parent?.parent is TopLevelVariableDeclaration:
        return p.name.lexeme;
      default:
        break;
    }
  }
  return '<unit>';
}

/// Every class declared in a set of sources, with whether it (or the `State`
/// its `createState` builds) names a [kCruxTypedInputMarkers] identifier.
@immutable
final class CruxClassIndex {
  /// Indexes [sources].
  factory CruxClassIndex(Iterable<CruxGuardSource> sources) {
    final classes = <String, List<_IndexedClass>>{};
    for (final file in sources) {
      final unit = parseString(
        content: file.source,
        throwIfDiagnostics: false,
      ).unit;
      for (final declaration in unit.declarations) {
        if (declaration is! ClassDeclaration) continue;
        var typedInput = false;
        for (final token in tokensOf(declaration)) {
          if (token.type == TokenType.IDENTIFIER &&
              kCruxTypedInputMarkers.contains(token.lexeme)) {
            typedInput = true;
            break;
          }
        }
        String? state;
        for (final member in declaration.body.members) {
          if (member is MethodDeclaration &&
              member.name.lexeme == 'createState') {
            for (final token in tokensOf(member.body)) {
              if (token.type == TokenType.IDENTIFIER &&
                  isTypeName(token.lexeme) &&
                  token.lexeme != 'State') {
                state = token.lexeme;
                break;
              }
            }
          }
        }
        classes
            .putIfAbsent(
              declaration.namePart.typeName.lexeme,
              () => <_IndexedClass>[],
            )
            .add(
              _IndexedClass(file.path, state, typedInput: typedInput),
            );
      }
    }
    return CruxClassIndex._(classes);
  }

  const CruxClassIndex._(this._classes);

  final Map<String, List<_IndexedClass>> _classes;

  /// How many classes were indexed.
  int get length => _classes.values.fold(0, (n, list) => n + list.length);

  /// Whether a class named [name], as seen from [fromPath], holds typed
  /// input itself or through its `State`. A private name resolves only in
  /// [fromPath]; a public one anywhere.
  bool holdsTypedInput(String name, String fromPath) {
    for (final c in _visible(name, fromPath)) {
      if (c.typedInput) return true;
      final state = c.state;
      if (state != null && _visible(state, c.path).any((s) => s.typedInput)) {
        return true;
      }
    }
    return false;
  }

  Iterable<_IndexedClass> _visible(String name, String fromPath) {
    final all = _classes[name] ?? const <_IndexedClass>[];
    return name.startsWith('_') ? all.where((c) => c.path == fromPath) : all;
  }
}

@immutable
final class _IndexedClass {
  const _IndexedClass(this.path, this.state, {required this.typedInput});

  final String path;
  final bool typedInput;
  final String? state;
}
