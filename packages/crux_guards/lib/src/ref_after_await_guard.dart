// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// One function allowed to use `ref` after an `await` with no mounted check,
/// and why that is safe there.
@immutable
final class CruxRefAfterAwaitExemption {
  /// Creates an exemption.
  const CruxRefAfterAwaitExemption({
    required this.file,
    required this.function,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The function or method name, as findings print it (`_handleOpen`,
  /// `build`, or `<closure>` for an anonymous function).
  final String function;

  /// Why the `ref` it holds cannot be dead by then: for example, a `ref`
  /// owned by a container that outlives the widget.
  final String reason;
}

/// `ref` is never used after an `await` unless something checked `mounted`
/// in between.
///
/// A `ConsumerState`'s `ref`, and a `WidgetRef` handed to a function, die
/// with their widget. Read after an `await`, when the widget may be gone, it
/// throws "Using ref when a widget is about to or has been unmounted", and the
/// rest of the handler never runs: an audit record not written, an
/// annotation never posted, a flag that blocks input for the session. The
/// suite has fixed this class many times; this guard stops it coming back.
///
/// **What is checked.** Every asynchronous function body that is a member of
/// a class extending `ConsumerState`, or that belongs to a function or
/// method with a parameter typed `WidgetRef`, including the closures inside
/// either. In such a body, each use of `ref` (other than `ref.mounted`) after
/// an `await` is a finding unless an identifier `mounted` (`mounted`,
/// `ref.mounted`, `context.mounted`) appears between the closest `await`
/// before it and the use. A nested function body is judged on its own awaits.
///
/// **What is not.** This reads syntax, in source order. An `await` in a loop
/// whose `ref` use comes earlier in the next iteration, a `ref` stored in a
/// local and used later, and a `ref` reached through another object are not
/// seen. A `mounted` check that does not actually guard the use (one read
/// and ignored) satisfies it. A `Ref` held by a provider is not a widget's
/// and is out of scope.
///
/// [exemptions] name a file and function where the use is safe, with the
/// reason; an exemption that matches nothing is a finding.
CruxGuardResult cruxAuditRefAfterAwait({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxRefAfterAwaitExemption> exemptions =
      const <CruxRefAfterAwaitExemption>[],
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
    final scopes = _ScopeFinder();
    unit.accept(scopes);
    for (final (name, body) in scopes.bodies) {
      for (final use in _unguardedUses(body)) {
        seen++;
        final index = pinned.indexWhere(
          (e) => e.file == file.path && e.function == name,
        );
        if (index >= 0) {
          used.add(index);
          continue;
        }
        findings.add(
          CruxGuardFinding(
            path: file.path,
            line: lineOf(file.source, use),
            detail:
                'in $name, `ref` is used after an await with no mounted '
                'check in between. If the widget is gone by then this throws '
                'and the rest of the handler never runs. Read what you need '
                'from ref before the await, or check `mounted` (or '
                '`ref.mounted` / `context.mounted`) after it and return.',
          ),
        );
      }
    }
  }
  for (var i = 0; i < pinned.length; i++) {
    if (used.contains(i)) continue;
    findings.add(
      CruxGuardFinding(
        path: pinned[i].file,
        line: 0,
        detail:
            'exemption for ${pinned[i].function} matches no use of ref after '
            'an await; remove it.',
      ),
    );
  }
  return CruxGuardResult(
    findings: findings,
    filesScanned: files,
    matchesSeen: seen,
  );
}

/// Finds the asynchronous bodies in scope, each with the name a finding
/// prints.
class _ScopeFinder extends RecursiveAstVisitor<void> {
  final List<(String, FunctionBody)> bodies = <(String, FunctionBody)>[];
  var _consumerState = 0;
  var _widgetRefFunction = 0;
  String _name = '<closure>';

  bool get _inScope => _consumerState > 0 || _widgetRefFunction > 0;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass.name.lexeme;
    final isConsumerState = superclass == 'ConsumerState';
    if (isConsumerState) _consumerState++;
    super.visitClassDeclaration(node);
    if (isConsumerState) _consumerState--;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) => _function(
    node.name.lexeme,
    node.parameters,
    node.body,
    () => super.visitMethodDeclaration(node),
  );

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => _function(
    node.name.lexeme,
    node.functionExpression.parameters,
    node.functionExpression.body,
    () => node.functionExpression.parameters?.accept(this),
    bodyVisit: () => node.functionExpression.body.accept(this),
  );

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A closure: its own body, judged on its own awaits, under the name of
    // nothing (it is anonymous).
    if (node.parent is FunctionDeclaration) {
      super.visitFunctionExpression(node);
      return;
    }
    _function(
      '<closure>',
      node.parameters,
      node.body,
      () => super.visitFunctionExpression(node),
    );
  }

  void _function(
    String name,
    FormalParameterList? parameters,
    FunctionBody body,
    void Function() visitChildren, {
    void Function()? bodyVisit,
  }) {
    final takesRef = parameters?.parameters.any(_isWidgetRefParameter) ?? false;
    if (takesRef) _widgetRefFunction++;
    final outer = _name;
    _name = name == '<closure>' ? outer : name;
    if (_inScope && body.isAsynchronous) bodies.add((_name, body));
    visitChildren();
    bodyVisit?.call();
    _name = outer;
    if (takesRef) _widgetRefFunction--;
  }

  static bool _isWidgetRefParameter(FormalParameter parameter) {
    final p = parameter is DefaultFormalParameter
        ? parameter.parameter
        : parameter;
    if (p is SimpleFormalParameter) {
      final type = p.type;
      return type is NamedType && type.name.lexeme == 'WidgetRef';
    }
    return false;
  }
}

/// Offsets of the uses of `ref` in [body] that follow an await with no
/// `mounted` between, not looking into nested function bodies.
///
/// An await inside a block that does not hold the use and that leaves by
/// `return`, `throw`, `break` or `continue` never precedes it at run time
/// (`if (x) { await dialog(); return; }`), so it does not count.
List<int> _unguardedUses(FunctionBody body) {
  final events = _EventCollector(body);
  body.accept(events);
  final uses = <int>[];
  for (final use in events.refUses) {
    int? lastAwait;
    for (final (end, exitingBlock) in events.awaits) {
      if (end > use) continue;
      if (exitingBlock != null &&
          !(exitingBlock.offset <= use && use < exitingBlock.end)) {
        continue;
      }
      if (lastAwait == null || end > lastAwait) lastAwait = end;
    }
    if (lastAwait == null) continue;
    final guarded = events.mountedChecks.any((m) => m > lastAwait! && m < use);
    if (!guarded) uses.add(use);
  }
  return uses;
}

/// The innermost block around [node] that ends by leaving it, or null.
Block? _exitingBlock(AstNode node, FunctionBody root) {
  var n = node.parent;
  for (; n != null && !identical(n, root); n = n.parent) {
    if (n is! Block) continue;
    final last = n.statements.isEmpty ? null : n.statements.last;
    final exits =
        last is ReturnStatement ||
        last is BreakStatement ||
        last is ContinueStatement ||
        (last is ExpressionStatement && last.expression is ThrowExpression);
    return exits ? n : null;
  }
  return null;
}

class _EventCollector extends RecursiveAstVisitor<void> {
  _EventCollector(this.root);

  final FunctionBody root;
  final List<(int, Block?)> awaits = <(int, Block?)>[];
  final List<int> refUses = <int>[];
  final List<int> mountedChecks = <int>[];

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    if (identical(node, root)) super.visitBlockFunctionBody(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (identical(node, root)) super.visitExpressionFunctionBody(node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    super.visitAwaitExpression(node);
    awaits.add((node.end, _exitingBlock(node, root)));
  }

  @override
  void visitForElement(ForElement node) {
    super.visitForElement(node);
    if (node.awaitKeyword != null) {
      awaits.add((node.end, _exitingBlock(node, root)));
    }
  }

  @override
  void visitForStatement(ForStatement node) {
    super.visitForStatement(node);
    if (node.awaitKeyword != null) {
      awaits.add((node.end, _exitingBlock(node, root)));
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'mounted') {
      mountedChecks.add(node.offset);
    } else if (node.name == 'ref' &&
        _isVariable(node) &&
        !_isMountedRead(node)) {
      refUses.add(node.offset);
    }
    super.visitSimpleIdentifier(node);
  }

  /// Whether [node] reads a variable named `ref`, rather than naming an
  /// argument (`ref:`) or a member of something else (`widget.ref`).
  static bool _isVariable(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is Label) return false;
    if (parent is PrefixedIdentifier) return identical(parent.prefix, node);
    if (parent is PropertyAccess) return identical(parent.target, node);
    if (parent is MethodInvocation) return identical(parent.target, node);
    return true;
  }

  static bool _isMountedRead(SimpleIdentifier node) {
    final parent = node.parent;
    if (parent is PrefixedIdentifier && identical(parent.prefix, node)) {
      return parent.identifier.name == 'mounted';
    }
    if (parent is PropertyAccess && identical(parent.target, node)) {
      return parent.propertyName.name == 'mounted';
    }
    return false;
  }
}
