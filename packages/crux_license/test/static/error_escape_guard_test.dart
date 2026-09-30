// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// An `Error` is not an `Exception`, and `on Exception` does not catch one.
//
// WHAT THIS BANS
// A `try` on the licence, policy or CXP path whose handlers are ALL typed
// (`on Exception`, `on FormatException`, `on IOException`,
// `on FileSystemException`, …) and whose protected body performs an operation
// that throws an `Error` rather than an `Exception`. Such a try looks defended
// and is not: the Error walks straight through it.
//
// WHY THOSE THREE PATHS
// They are the three that parse bytes somebody else wrote. A licence
// credential is pasted by a user, a policy file is written by an IT
// department, and a CXP frame arrives over a socket from another process.
// Every one of them is reached from a UI callback or a read loop where an
// escaping Error is an unhandled async error rather than a message.
//
// THE DEFECT THAT MOTIVATED IT
// `parseLicenseCredential` documents itself as total — "the UI needs a
// sentence back, not a crash" — and threw `RangeError` on a 49-character
// paste, because both licence-file markers end in five dashes and
// `indexOf(END)` matched inside the BEGIN marker. Three call sites relied on
// the totality and none re-checked it; `RangeError` is an `Error`, so it
// escaped every `on Exception` between the parser and the activation screen.
//
// WHAT THIS GUARD DOES NOT COVER, AND WHAT DOES
// It would NOT have caught that bug: `_parseLicenseFile` has no `try` at all.
// A function documented as never throwing is proved by fuzzing, not by
// scanning handlers — that job belongs to
// `test/license_credential_fuzz_test.dart`, which enumerates every prefix of
// a valid credential and generates marker-heavy soup. The two guards are
// complementary: this one watches the handlers, that one watches the promise.
//
// WHY NOT A BLANKET BAN ON `on Exception`
// Because it would be blunt enough to be ignored. At the time of writing the
// three packages hold 21 typed-only try blocks, and 20 of them protect a body
// that can only raise an Exception — `jsonDecode`, `base64.decode`,
// `File.delete`. Demanding a written allowance for each would produce twenty
// entries saying "jsonDecode only throws FormatException", which is noise that
// nobody re-reads and that hides the one entry that matters. Pairing the
// handler shape with the body's *content* flags exactly the combination that
// is wrong, and leaves the allowlist small enough to stay honest.
//
// ANALYSIS MODEL
// The scan resolves every library under the source roots with
// `package:analyzer` and works on the AST with static types, so `.last` on a
// List is distinguished from `.last` on something else. For each
// `TryStatement`:
//
//  1. HANDLERS. A clause with no `on` type (a bare `catch (e)`) or with
//     `on Object` catches everything, so the try is safe and is skipped. A try
//     with no catch clauses at all (`try`/`finally`) is skipped too — it does
//     not pretend to handle anything.
//  2. BODY. Otherwise the `try` block is walked for the operations below.
//     Nested try statements that are themselves safe have their bodies skipped
//     (their operations cannot escape), while their catch and finally blocks
//     are still walked.
//  3. CLOSURES are not descended into. A function expression written inside a
//     try usually runs somewhere else entirely, so its contents are not
//     protected by this try and counting them would produce false positives.
//
// THE OPERATIONS, AND WHY EACH IS ON THE LIST
//  * `as` — `TypeError`. Excluded when the target is `Object?`/`dynamic`,
//    which cannot fail.
//  * `!` — `TypeError` on null.
//  * `.first` / `.last` / `.single` on an Iterable — `StateError`.
//  * `substring`, `elementAt` — `RangeError`.
//  * `firstWhere` / `lastWhere` / `singleWhere` / `reduce` — `StateError`.
//  * Indexing a List or String — `RangeError`.
//  * `DateTime.fromMillisecondsSinceEpoch` / `fromMicrosecondsSinceEpoch` —
//    `RangeError` (measured) outside +/-8640000000000000, which is exactly
//    what a corrupt or hostile timestamp field supplies.
//
// AND WHAT IS DELIBERATELY NOT ON IT
//  * `Map` indexing returns null for an absent key; it does not throw.
//  * `int.parse`, `double.parse`, `DateTime.parse`, `Uri.parse` throw
//    `FormatException`, which IS an Exception — a typed handler catches them.
//  * `.cast<K, Object?>()` returns a lazy view whose value cast is to
//    `Object?` and therefore always succeeds; its key cast to `String` could
//    fail in principle, but only on a map `jsonDecode` cannot produce. Each
//    such site in crux_cxp was read by hand and is guarded by an `is Map`
//    test that throws `FormatException` first.
//
// WHAT THE SAME ENGINE FOUND ELSEWHERE, ONCE
// During the 2026-09 audit this visitor was lifted into a throwaway script and
// run over every `lib/` in the suite — crux-shared's 41 packages and all four
// products, open core and Pro overlay: 3075 files, 1076 `try` statements, 27
// raw findings. Twenty-six were false positives of the same three shapes, and
// they are why the roots below stop where they do rather than covering the
// suite:
//
//   * the operation is dominated by the test that makes it safe —
//     `if (entries.length == 1) … entries.single`,
//     `if (decoded['message'] is String) … as String`,
//     `dot > separator ? packPath.substring(0, dot) : packPath`;
//   * `firstWhere`/`lastWhere` with an `orElse`, which cannot raise at all
//     (five of LintCrux's engine probes are this one line);
//   * a `!` on a field assigned from a non-nullable future two lines above,
//     with no `await` in between to let anything null it.
//
// The one true positive was `CxpDiscovery._scan`, since fixed (the handler
// is `on Object` and the decoder is total over FormatException), which is
// why the allowlist below is empty. A guard that reported the other
// twenty-six every run would be turned off within a month, so widening the
// roots is not free: it costs an allowlist entry per false positive, and an
// allowlist nobody believes is worse than no guard.
//
// LIMITATION, STATED PLAINLY
// The scan is intraprocedural. A typed-only try around a CALL whose callee
// throws an Error is not flagged — `decodeCxpMessage` in `cxp_client.dart`
// and `cxp_server.dart` is the live example. Those decoder trees were audited
// by hand for this campaign and every `!`/`as` in them is dominated by an
// `is!` test that raises `FormatException`, so they are clean today. Going
// interprocedural would need a whole-program throw summary; the honest
// statement is that this guard watches the shape it can see.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Sites allowed to keep a typed-only handler over an Error-capable body, each
/// with the reason it is allowed.
///
/// Keyed by `<package>/<path under lib>:<symbol>` rather than by line number,
/// so an unrelated edit above the site does not silently retire the allowance
/// or, worse, move it onto a different try.
///
/// An allowance without a reason is indistinguishable from an oversight six
/// months later. The map shape is borrowed from netcrux's
/// `action_reachability_guard_test`, for exactly that reason.
///
/// Empty since the one site it held — `crux_cxp/src/cxp_discovery.dart:_scan`,
/// whose `on FormatException` let a `RangeError` from
/// `CxpPeerManifest.fromJson` freeze discovery — was fixed by widening the
/// handler to `on Object`. The map stays so the next allowance has a home and
/// a reason next to it.
const Map<String, String> _allowed = <String, String>{};

/// Packages scanned, as directories relative to this package root.
///
/// The guard lives in `crux_license` because that is where the defect that
/// motivated it was found, and it reaches its two siblings rather than being
/// written out three times. crux_signing is included and contributes nothing:
/// it has no `try` at all, which is the correct amount for a verifier.
const List<String> _roots = <String>[
  'lib',
  '../crux_policy/lib',
  '../crux_cxp/lib',
  '../crux_signing/lib',
];

void main() {
  late final _Scan scan;

  setUpAll(() async {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason: 'run this test from the crux_license package root',
    );
    scan = await _Scan.run(_roots);
  });

  test('resolution covered the tree', () {
    // A guard that silently resolved nothing is a guard that passes forever.
    expect(
      scan.unresolved,
      isEmpty,
      reason:
          'these libraries did not resolve, so any try they hold is invisible '
          'to the scan — run `melos bootstrap`:\n${scan.unresolved.join('\n')}',
    );
    expect(
      scan.filesScanned,
      greaterThan(40),
      reason: 'far fewer files than the four packages hold; the roots moved',
    );
    expect(
      scan.tryStatements,
      greaterThan(30),
      reason: 'almost no try statements found; the visitor is not running',
    );
  });

  test('no Error escapes a typed-only handler, or it says why', () {
    final offenders = <String>[];
    for (final finding in scan.findings) {
      if (_allowed.containsKey(finding.key)) continue;
      offenders.add(finding.describe());
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A typed handler does not catch an Error. Either narrow the body so '
          'it cannot raise one, or catch `on Object` and say in a comment why '
          'swallowing a programming error is right here — the precedent is '
          "LintCrux's filter-preset dialog, which hung forever on an "
          '`UnsupportedError` the `on ArgumentError` beside it could not see.'
          '\n\n${offenders.join('\n\n')}',
    );
  });

  test('every allowance is still needed', () {
    // An allowance that outlived its problem is worse than no allowance: it
    // reads as a standing exemption for a site that is now fine, and the next
    // person to break that site gets waved through.
    final found = <String>{for (final f in scan.findings) f.key};
    final stale = _allowed.keys.where((k) => !found.contains(k)).toList();
    expect(
      stale,
      isEmpty,
      reason:
          'these sites no longer raise a finding — delete their entries from '
          '_allowed:\n${stale.join('\n')}',
    );
  });

  test('the guard is not vacuous', () async {
    // If the detector stopped recognising Error-capable operations, every
    // check above would pass trivially and the allowlist would go stale in a
    // way the previous test reports as a SUCCESS story. The scanned packages
    // are clean today, so their findings cannot prove the detector works;
    // a fixture written to be caught can. One typed-only try whose body
    // holds three of the listed operations, and one that catches everything
    // and must not be reported.
    final fixtureDir = await Directory.systemTemp.createTemp(
      'error_escape_fixture_',
    );
    addTearDown(() => fixtureDir.delete(recursive: true));
    final lib = Directory(p.join(fixtureDir.path, 'lib'))..createSync();
    File(p.join(lib.path, 'fixture.dart')).writeAsStringSync('''
int? typedOnly(List<int> xs, Object o, int ms) {
  try {
    final head = xs.first;
    final cast = o as int;
    final when = DateTime.fromMillisecondsSinceEpoch(ms);
    return head + cast + when.millisecond;
  } on FormatException {
    return null;
  }
}

int? catchesEverything(List<int> xs) {
  try {
    return xs.first;
  } on Object {
    return null;
  }
}
''');
    final probe = await _Scan.run(<String>[lib.path]);
    expect(probe.unresolved, isEmpty, reason: 'the fixture must resolve');
    expect(
      probe.findings.map((f) => f.key),
      ['${p.basename(fixtureDir.path)}/fixture.dart:typedOnly'],
      reason: 'exactly the typed-only try is a finding',
    );
    expect(
      probe.findings.single.reasons.join('\n'),
      allOf(
        contains('StateError from `.first`'),
        contains('TypeError from an `as` cast'),
        contains('fromMillisecondsSinceEpoch'),
      ),
      reason: 'each listed operation class is still recognised',
    );
  });
}

/// One typed-only `try` whose body can raise an `Error`.
class _Finding {
  _Finding({
    required this.key,
    required this.path,
    required this.line,
    required this.handlers,
    required this.reasons,
  });

  /// Stable identity: `<package>/<path under lib>:<enclosing symbol>`.
  final String key;
  final String path;
  final int line;
  final List<String> handlers;

  /// The Error-capable operations found, as `<line>: <what>`.
  final List<String> reasons;

  String describe() =>
      '$path:$line ($key)\n'
      '  handlers: ${handlers.join(', ')}\n'
      '  body can raise an Error via:\n'
      '${reasons.map((r) => '    $r').join('\n')}';
}

class _Scan {
  _Scan._();

  final List<_Finding> findings = <_Finding>[];
  final List<String> unresolved = <String>[];
  int filesScanned = 0;
  int tryStatements = 0;

  static Future<_Scan> run(List<String> roots) async {
    final files = <String>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) {
          files.add(p.normalize(e.absolute.path));
        }
      }
    }
    final scan = _Scan._();
    if (files.isEmpty) return scan;
    final collection = AnalysisContextCollection(
      includedPaths: files,
      sdkPath: _dartSdkPath(),
    );
    for (final file in files) {
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        unresolvedAdd(scan, file);
        continue;
      }
      scan.filesScanned++;
      result.unit.accept(_TryVisitor(scan, result));
    }
    return scan;
  }

  static void unresolvedAdd(_Scan scan, String file) =>
      scan.unresolved.add(p.relative(file));
}

/// The Dart SDK the analyzer resolves `dart:` libraries against. Under
/// `flutter test` the running executable is the Flutter tester, whose
/// directory is not an SDK, so the bundled `dart-sdk` is located explicitly.
String? _dartSdkPath() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null) p.join(flutterRoot, 'bin', 'cache', 'dart-sdk'),
    p.dirname(p.dirname(Platform.resolvedExecutable)),
  ];
  for (final candidate in candidates) {
    if (File(p.join(candidate, 'lib', 'core', 'core.dart')).existsSync()) {
      return candidate;
    }
  }
  return null;
}

class _TryVisitor extends RecursiveAstVisitor<void> {
  _TryVisitor(this.scan, this.unit);

  final _Scan scan;
  final ResolvedUnitResult unit;

  @override
  void visitTryStatement(TryStatement node) {
    scan.tryStatements++;
    if (!_catchesEverything(node)) {
      final body = _BodyVisitor(unit);
      node.body.accept(body);
      if (body.reasons.isNotEmpty) {
        scan.findings.add(
          _Finding(
            key: _keyFor(node),
            path: p.relative(unit.path),
            line: unit.lineInfo.getLocation(node.offset).lineNumber,
            handlers: <String>[
              for (final c in node.catchClauses)
                'on ${c.exceptionType?.toSource() ?? '<untyped>'}',
            ],
            reasons: body.reasons,
          ),
        );
      }
    }
    super.visitTryStatement(node);
  }

  /// `<package>/<path under lib>:<enclosing declaration>`.
  String _keyFor(TryStatement node) {
    final path = p.split(p.normalize(unit.path));
    final libAt = path.lastIndexOf('lib');
    final scoped = libAt > 0
        ? '${path[libAt - 1]}/${p.posix.joinAll(path.sublist(libAt + 1))}'
        : p.relative(unit.path);
    return '$scoped:${_enclosingName(node)}';
  }

  static String _enclosingName(AstNode node) {
    for (AstNode? n = node; n != null; n = n.parent) {
      if (n is MethodDeclaration) return n.name.lexeme;
      if (n is FunctionDeclaration) return n.name.lexeme;
      if (n is ConstructorDeclaration) {
        // The class name is `typeName`, not `returnType`, and it is nullable:
        // the `C.new()` spelling has no type name at all. Fall back to the
        // enclosing declaration so the key never degrades to `null`.
        final owner = n.typeName?.name ?? _enclosingTypeName(n) ?? '<type>';
        final named = n.name?.lexeme;
        return named == null ? owner : '$owner.$named';
      }
    }
    return '<top level>';
  }

  /// The name of the class, enum or mixin a node sits inside.
  ///
  /// Only ever consulted for the `C.new()` constructor spelling, which leaves
  /// [ConstructorDeclaration.typeName] null. Nothing in these four packages
  /// uses it today; the branch exists so the key cannot become `<type>` for a
  /// site the allowlist has to address by name.
  static String? _enclosingTypeName(AstNode node) {
    for (AstNode? n = node; n != null; n = n.parent) {
      if (n is ClassDeclaration) return n.namePart.typeName.lexeme;
      if (n is EnumDeclaration) return n.namePart.typeName.lexeme;
      if (n is MixinDeclaration) return n.name.lexeme;
    }
    return null;
  }

  /// True when some clause catches an `Error` as well as an `Exception`: a
  /// bare `catch (e)`, or `on Object` / `on dynamic`.
  static bool _catchesEverything(TryStatement node) {
    if (node.catchClauses.isEmpty) return true;
    for (final clause in node.catchClauses) {
      final type = clause.exceptionType;
      if (type == null) return true;
      final resolved = type.type;
      if (resolved == null) continue;
      if (resolved is DynamicType) return true;
      if (resolved.isDartCoreObject) return true;
      // `on Error` is a deliberate, lint-suppressed choice in this codebase
      // (see workspace_service.dart) and closes the hole just as well.
      if (resolved.element?.name == 'Error') return true;
    }
    return false;
  }
}

/// Walks a protected block looking for operations that raise an `Error`.
class _BodyVisitor extends RecursiveAstVisitor<void> {
  _BodyVisitor(this.unit);

  final ResolvedUnitResult unit;
  final List<String> reasons = <String>[];

  static const Set<String> _riskyMethods = <String>{
    'substring',
    'elementAt',
    'firstWhere',
    'lastWhere',
    'singleWhere',
    'reduce',
  };
  static const Set<String> _riskyGetters = <String>{'first', 'last', 'single'};
  static const Set<String> _riskyConstructors = <String>{
    'fromMillisecondsSinceEpoch',
    'fromMicrosecondsSinceEpoch',
  };

  void _note(AstNode node, String what) {
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    reasons.add('$line: $what — `${_snippet(node)}`');
  }

  String _snippet(AstNode node) {
    final text = node.toSource().replaceAll(RegExp(r'\s+'), ' ');
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  /// A closure written here almost never runs here, so its contents are not
  /// protected by the enclosing try. Not descending is what keeps the guard
  /// from flagging every `map((e) => e as Foo)` in a body.
  @override
  void visitFunctionExpression(FunctionExpression node) {}

  /// A nested try that catches everything contains its own operations; only
  /// its handlers and finally can still raise into the outer try.
  @override
  void visitTryStatement(TryStatement node) {
    if (!_TryVisitor._catchesEverything(node)) node.body.accept(this);
    for (final clause in node.catchClauses) {
      clause.body.accept(this);
    }
    node.finallyBlock?.accept(this);
  }

  @override
  void visitAsExpression(AsExpression node) {
    final target = node.type.type;
    final harmless =
        target is DynamicType ||
        (target != null &&
            target.isDartCoreObject &&
            target.nullabilitySuffix.name == 'question');
    if (!harmless) _note(node, 'TypeError from an `as` cast');
    super.visitAsExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.type == TokenType.BANG) {
      _note(node, 'TypeError from a `!` null assertion');
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_riskyMethods.contains(node.methodName.name)) {
      _note(node, 'RangeError/StateError from `${node.methodName.name}`');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _checkGetter(node, node.propertyName.name, node.realTarget.staticType);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _checkGetter(node, node.identifier.name, node.prefix.staticType);
    super.visitPrefixedIdentifier(node);
  }

  void _checkGetter(AstNode node, String name, DartType? targetType) {
    if (!_riskyGetters.contains(name)) return;
    if (targetType == null) return;
    // Only an Iterable's first/last/single throw; a field called `last` on a
    // domain object does not.
    final isIterable =
        targetType.isDartCoreList ||
        targetType.isDartCoreSet ||
        targetType.isDartCoreIterable;
    if (isIterable) {
      _note(node, 'StateError from `.$name` on an empty iterable');
    }
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    final target = node.realTarget.staticType;
    if (target != null && (target.isDartCoreList || target.isDartCoreString)) {
      _note(node, 'RangeError from indexing a List/String');
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.name?.name;
    if (name != null && _riskyConstructors.contains(name)) {
      _note(node, 'ArgumentError from `$name` on an out-of-range value');
    }
    super.visitInstanceCreationExpression(node);
  }
}
