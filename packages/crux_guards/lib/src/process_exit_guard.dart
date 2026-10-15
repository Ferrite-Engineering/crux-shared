// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crux_guards/src/dialog_sites.dart' show enclosingMemberName;
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// One reviewed use of `dart:io`'s `exit`, and why it may skip `cruxExit`.
@immutable
final class CruxProcessExitExemption {
  /// Creates an exemption.
  const CruxProcessExitExemption({
    required this.file,
    required this.member,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The enclosing named declaration, as findings print it: a function,
  /// method, constructor, field or top-level variable name, or `<unit>` for
  /// a use outside any of them. A closure is named by the declaration that
  /// holds it.
  final String member;

  /// Why ending the process there must not, or need not, mark the session's
  /// exit clean: for example, a pure-Dart entry point that never starts the
  /// unclean-shutdown detector.
  final String reason;
}

/// No product ends its own process with `dart:io`'s `exit`.
///
/// `exit` ends the process without running any more Dart, so whatever an
/// orderly quit has to do first never happens. The case that made this a
/// guard: `crux_telemetry`'s unclean-shutdown detector keeps a session marker
/// on disk for the life of the session and removes it on a clean exit. Every
/// Quit menu item and quit shortcut in the suite called `exit(0)`, so every
/// such quit left the marker behind and the next launch counted it as a
/// crash. `cruxExit` (in `crux_telemetry`) removes the marker and then exits;
/// it is the one way to end the process.
///
/// **What is a use.** A call `exit(...)`, a tear-off `exit` (as in
/// `exitProcess = exit`), and either one through a prefix (`io.exit`), when
/// the file imports `dart:io` in a way that makes `exit` visible: without a
/// combinator, with `show exit`, or with a `hide` list that leaves it. A
/// parameter, local, member or top-level declaration named `exit` in scope
/// shadows it, and a member access on some other object (`process.exit`) is
/// not a use. Comments and strings never match.
///
/// [exemptions] name a file and enclosing member where a direct `exit` is
/// right, with the reason; an exemption that matches nothing is a finding.
CruxGuardResult cruxAuditProcessExit({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxProcessExitExemption> exemptions =
      const <CruxProcessExitExemption>[],
}) {
  final pinned = exemptions.toList();
  final used = <int>{};
  final findings = <CruxGuardFinding>[];
  var files = 0;
  var seen = 0;
  for (final file in sources) {
    files++;
    final unit = parseString(
      content: file.source,
      throwIfDiagnostics: false,
    ).unit;
    final visibility = _ExitVisibility.of(unit);
    if (!visibility.any) continue;
    final finder = _ExitUseFinder(visibility);
    unit.accept(finder);
    for (final (offset, member) in finder.uses) {
      seen++;
      final index = pinned.indexWhere(
        (e) => e.file == file.path && e.member == member,
      );
      if (index >= 0) {
        used.add(index);
        continue;
      }
      findings.add(
        CruxGuardFinding(
          path: file.path,
          line: lineOf(file.source, offset),
          detail:
              'in $member, `dart:io` `exit` ends the process without running '
              'any Dart, so the unclean-shutdown marker is left behind and '
              'the next launch counts this quit as a crash. Call `cruxExit` '
              'from crux_telemetry instead (or pass it where `exit` was '
              'passed).',
        ),
      );
    }
  }
  for (var i = 0; i < pinned.length; i++) {
    if (used.contains(i)) continue;
    findings.add(
      CruxGuardFinding(
        path: pinned[i].file,
        line: 0,
        detail:
            'exemption for ${pinned[i].member} matches no direct use of '
            '`exit`; remove it.',
      ),
    );
  }
  return CruxGuardResult(
    findings: findings,
    filesScanned: files,
    matchesSeen: seen,
  );
}

/// How a file can name `dart:io`'s `exit`.
final class _ExitVisibility {
  _ExitVisibility({required this.unprefixed, required this.prefixes});

  factory _ExitVisibility.of(CompilationUnit unit) {
    var unprefixed = false;
    final prefixes = <String>{};
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      if (directive.uri.stringValue != 'dart:io') continue;
      if (!_combinatorsAllowExit(directive.combinators)) continue;
      final prefix = directive.prefix?.name;
      if (prefix == null) {
        unprefixed = true;
      } else {
        prefixes.add(prefix);
      }
    }
    return _ExitVisibility(unprefixed: unprefixed, prefixes: prefixes);
  }

  final bool unprefixed;
  final Set<String> prefixes;

  bool get any => unprefixed || prefixes.isNotEmpty;

  static bool _combinatorsAllowExit(List<Combinator> combinators) {
    for (final combinator in combinators) {
      if (combinator is ShowCombinator &&
          !combinator.shownNames.any((n) => n.name == 'exit')) {
        return false;
      }
      if (combinator is HideCombinator &&
          combinator.hiddenNames.any((n) => n.name == 'exit')) {
        return false;
      }
    }
    return true;
  }
}

class _ExitUseFinder extends RecursiveAstVisitor<void> {
  _ExitUseFinder(this.visibility);

  final _ExitVisibility visibility;

  /// Offset and enclosing member of each use.
  final List<(int, String)> uses = <(int, String)>[];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'exit' && _isDartIoExit(node)) {
      uses.add((node.offset, enclosingMemberName(node)));
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Directives hold `show exit`, which is not a use.
    for (final declaration in node.declarations) {
      declaration.accept(this);
    }
  }

  @override
  void visitComment(Comment node) {
    // `[exit]` in a doc comment is a reference, not a use.
  }

  bool _isDartIoExit(SimpleIdentifier node) {
    if (node.inDeclarationContext()) return false;
    final parent = node.parent;
    if (parent is Label) return false;
    if (parent is MethodInvocation && identical(parent.methodName, node)) {
      // `s..exit(0)` has no target of its own: it is a member of `s`.
      if (parent.isCascaded) return false;
      final target = parent.target;
      if (target != null) {
        return target is SimpleIdentifier &&
            visibility.prefixes.contains(target.name);
      }
      return visibility.unprefixed && !_shadowed(node);
    }
    if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
      return visibility.prefixes.contains(parent.prefix.name);
    }
    if (parent is PropertyAccess && identical(parent.propertyName, node)) {
      return false;
    }
    return visibility.unprefixed && !_shadowed(node);
  }

  /// Whether a declaration named `exit` encloses [node]'s scope.
  static bool _shadowed(AstNode node) {
    for (var scope = node.parent; scope != null; scope = scope.parent) {
      final declares = switch (scope) {
        FunctionExpression(:final parameters?) => _declaresIn(parameters),
        MethodDeclaration(:final parameters?) => _declaresIn(parameters),
        ConstructorDeclaration(:final parameters) => _declaresIn(parameters),
        Block(:final statements) => statements.any(_statementDeclaresExit),
        ForStatement(:final forLoopParts) => _forPartsDeclare(forLoopParts),
        CatchClause(:final exceptionParameter, :final stackTraceParameter) =>
          exceptionParameter?.name.lexeme == 'exit' ||
              stackTraceParameter?.name.lexeme == 'exit',
        ClassBody(:final members) => members.any(_memberDeclaresExit),
        EnumBody(:final members) => members.any(_memberDeclaresExit),
        CompilationUnit(:final declarations) => declarations.any(
          _topLevelDeclaresExit,
        ),
        _ => false,
      };
      if (declares) return true;
    }
    return false;
  }

  static bool _declaresIn(FormalParameterList parameters) =>
      parameters.parameters.any((p) => p.name?.lexeme == 'exit');

  static bool _statementDeclaresExit(Statement statement) =>
      switch (statement) {
        VariableDeclarationStatement(:final variables) =>
          variables.variables.any((v) => v.name.lexeme == 'exit'),
        FunctionDeclarationStatement(:final functionDeclaration) =>
          functionDeclaration.name.lexeme == 'exit',
        _ => false,
      };

  static bool _forPartsDeclare(ForLoopParts parts) => switch (parts) {
    ForPartsWithDeclarations(:final variables) => variables.variables.any(
      (v) => v.name.lexeme == 'exit',
    ),
    ForEachPartsWithDeclaration(:final loopVariable) =>
      loopVariable.name.lexeme == 'exit',
    _ => false,
  };

  static bool _memberDeclaresExit(ClassMember member) => switch (member) {
    MethodDeclaration(:final name) => name.lexeme == 'exit',
    FieldDeclaration(:final fields) => fields.variables.any(
      (v) => v.name.lexeme == 'exit',
    ),
    _ => false,
  };

  static bool _topLevelDeclaresExit(CompilationUnitMember member) =>
      switch (member) {
        FunctionDeclaration(:final name) => name.lexeme == 'exit',
        TopLevelVariableDeclaration(:final variables) =>
          variables.variables.any((v) => v.name.lexeme == 'exit'),
        _ => false,
      };
}
