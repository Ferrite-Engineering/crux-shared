// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_db_recovery.dart';
// Imported so the [CruxDeleteAllowlistEntry] and [cruxAuditOpenOptions]
// cross-references below resolve: G5b is an extension of G5 and borrows G4's
// allowlist property, and a reader who cannot click through to either has to
// take both claims on trust.
import 'package:crux_sqlite/src/guards/crux_database_delete_guard.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_guard_sources.dart';
import 'package:crux_sqlite/src/guards/crux_open_options_guard.dart';
import 'package:meta/meta.dart';

/// How many times [cruxOpenReachingEntryPoints] re-runs its derivation before
/// it stops.
///
/// Each round can only add entry points, and adding one is what lets the next
/// round see a caller of it, so the set is monotone and the loop is a fixed
/// point that terminates on its own. The cap is a guard against a
/// pathological source set, not a tuning knob: the real store graphs settle in
/// two rounds (a root, then the store factory that calls it). It is quoted in
/// the failure message because a boundary a guard does not state is a boundary
/// a reader assumes is not there.
const int kCruxOpenReachRounds = 8;

/// One file permitted to wrap an open-reaching call in a catch-all, and the
/// store whose data value makes that survivable.
///
/// **The entry carries the store's own recovery declaration, not a copy of
/// it** — the same property that keeps [CruxDeleteAllowlistEntry] from being a
/// hole, and for the same reason. Write
/// `recovery: SqliteLintRunCacheService.dataValue`, never
/// `recovery: CruxDbRecovery.recreate`. An entry is honoured only when that
/// constant is [CruxDbRecovery.recreate], so a store that turns PRECIOUS
/// withdraws its own permission with nobody having to remember to come back
/// here. A copied literal would keep saying `recreate` long after the store
/// stopped meaning it.
///
/// An entry is a *maximum* permission, not an endorsement. Even for a
/// derivable store the correct shape is typed catches — the suite's one
/// derivable database, `cache.db`, degrades through three typed handlers and
/// needs no entry. The strong outcome for this list is that it is empty.
@immutable
final class CruxOpenCatchAllowlistEntry {
  /// Creates a [CruxOpenCatchAllowlistEntry].
  const CruxOpenCatchAllowlistEntry({
    required this.file,
    required this.storeName,
    required this.recovery,
    required this.reason,
  });

  /// The path (or path suffix) of the file permitted to hold the catch-all.
  /// Matched by suffix so an entry survives the repo being checked out
  /// anywhere.
  final String file;

  /// The store whose data value makes the catch-all survivable.
  final String storeName;

  /// **The store's own `CruxDbRecovery` declaration, referenced.** Honoured
  /// only when it is [CruxDbRecovery.recreate].
  final CruxDbRecovery recovery;

  /// Why every fault this catch can swallow is one the store can survive
  /// silently, in terms a reader can check against the inventory in the
  /// migration guide.
  final String reason;
}

/// Every `Class.method(...)` in [sources] that reaches a database open, plus
/// any [seeds] handed in.
///
/// **Derived, not listed.** A store is covered the day it is written, without
/// anybody remembering to come back and name it here — which is the difference
/// between a guard that keeps working and a guard that quietly stops.
///
/// The derivation starts from two roots that no product owns:
///
///  * `openDatabase(...)` in any receiver form — sqflite's own API.
///  * `<something>.open(...)` where the surrounding statement names a policy,
///    which is `CruxSqliteOpenPolicy.open`, the sanctioned route. The same
///    receiver heuristic `cruxAuditOpenOptions` uses, so the two guards agree
///    on what an open is.
///
/// From there, any `static` method or `factory` constructor whose body
/// contains a root call — or a call to an entry point a previous round
/// found — becomes an entry point itself, named `Class.method`. The rounds
/// repeat until the set stops growing, at most [kCruxOpenReachRounds] times.
/// Two rounds is what a real store takes: the policy call, then the store's
/// `open` factory that wraps it.
///
/// **What it does not see, stated because a guard that quietly checks less
/// than it appears to is worse than one with a boundary:** this is a text
/// scan, not a call graph. An open reached only through an instance method, a
/// function-typed field, a tear-off, a top-level function, or a class that
/// lives in a package outside [sources] is not derived. Pass those to
/// [cruxAuditOpenCatchShapes]'s `extraOpenEntryPoints` if a repo grows one.
Set<String> cruxOpenReachingEntryPoints({
  required Iterable<CruxSourceFile> sources,
  Set<String> seeds = const <String>{},
}) {
  final declarations = <_EntryDeclaration>[];
  for (final file in sources) {
    declarations.addAll(_entryDeclarations(_blankNonCode(file.source)));
  }
  final entries = <String>{...seeds};
  for (var round = 0; round < kCruxOpenReachRounds; round++) {
    var grew = false;
    for (final declaration in declarations) {
      if (entries.contains(declaration.qualifiedName)) continue;
      if (_openReachingCallsIn(declaration.body, entries).isEmpty) continue;
      entries.add(declaration.qualifiedName);
      grew = true;
    }
    if (!grew) break;
  }
  return entries;
}

/// **Guard G5b — catch shapes at an open site.**
///
/// No `catch (e)` and no `on Object catch` may wrap a call that reaches a
/// database open. It is an extension of [cruxAuditOpenOptions] rather than a
/// guard of its own because it is the same question asked one step further
/// out: G5 asks whether an open is *built* safely, G5b asks whether its
/// failure is *read* safely, and both work off the same inventory of what
/// counts as an open.
///
/// ### Why the rule is absolute
///
/// Three different faults arrive at an open call, and at a catch-all they are
/// one exception:
///
///  * **Genuine corruption** — the bytes on disk are not a database. The
///    world's fault. The data is unreadable.
///  * **A migration failure** — our own code threw. Our fault. The
///    transaction rolled back and **every row is still there**.
///  * **Version skew** — the file's `user_version` is higher than this build
///    knows. Nobody's fault, two builds sharing one file. **Nothing was
///    written.**
///
/// A handler written for the first is catastrophic for the other two: it
/// treats a bug of ours, and an ordinary two-build overlap, as damaged
/// hardware. That is the defect this rule exists to remove, and it is not
/// hypothetical — it cost a paying user a year of history. `SQLITE_BUSY` is a
/// fourth thing a catch-all cannot see: a live, healthy, *busy* database.
///
/// The rule does not forbid **degrading**. A store whose contents are
/// reproducible may legitimately answer "no cache this session" to all of
/// them. What it forbids is degrading without being able to say *which*
/// happened, because the version of that which ships is the one where a broken
/// migration turns a feature off for every user with no diagnostic anywhere.
///
/// ### How it decides a call reaches an open
///
/// By [cruxOpenReachingEntryPoints], derived from the same sources rather than
/// hand-listed — see there for the roots, the rounds, and the shapes the
/// derivation does not see. [extraOpenEntryPoints] adds names by hand for the
/// cases it cannot reach.
///
/// ### The allowlist
///
/// [CruxOpenCatchAllowlistEntry], honoured only when the store it references
/// declares [CruxDbRecovery.recreate]. An entry that matches nothing is red:
/// a standing permission nobody is reading is how the next one gets added
/// without an argument.
CruxGuardReport cruxAuditOpenCatchShapes({
  required Iterable<CruxSourceFile> sources,
  required String subject,
  Iterable<CruxOpenCatchAllowlistEntry> allowlist =
      const <CruxOpenCatchAllowlistEntry>[],
  Set<String> extraOpenEntryPoints = const <String>{},
}) {
  final files = sources.toList();
  final entryPoints = cruxOpenReachingEntryPoints(
    sources: files,
    seeds: extraOpenEntryPoints,
  );
  final findings = <CruxGuardFinding>[];
  final observations = <CruxGuardFinding>[];
  final entries = allowlist.toList();
  final used = <int>{};

  for (final entry in entries) {
    if (entry.recovery == CruxDbRecovery.recreate) continue;
    findings.add(
      CruxGuardFinding(
        location: 'allowlist entry for ${entry.file}',
        detail:
            'the ${entry.storeName} declares '
            'CruxDbRecovery.${entry.recovery.name}, which is PRECIOUS. No '
            'entry can put a catch-all in front of an open on data that '
            'cannot be rebuilt — a swallowed migration failure there is a '
            'history nobody knows is gone. Either the store stopped being '
            'derivable (remove this entry and write typed catches) or the '
            'declaration is wrong.',
      ),
    );
  }

  for (final file in files) {
    final code = _blankNonCode(file.source);
    for (final statement in _tryStatements(code)) {
      final calls = _openReachingCallsIn(statement.body, entryPoints);
      if (calls.isEmpty) continue;
      for (final clause in statement.clauses) {
        if (!clause.isCatchAll) continue;
        final index = entries.indexWhere(
          (e) => file.path.endsWith(e.file) || e.file.endsWith(file.path),
        );
        final shape = clause.shape;
        final reached = calls.join(', ');
        if (index < 0) {
          findings.add(
            CruxGuardFinding(
              location: file.locate(clause.offset),
              detail:
                  '`$shape` wraps a call that reaches a database open '
                  '($reached).\n'
                  '        That one handler is where genuine corruption, a '
                  'migration failure of ours, and a version skew between two '
                  'builds all arrive as the same object — and the first is '
                  'the only one of the three the data is actually lost in.',
            ),
          );
          continue;
        }
        used.add(index);
        final entry = entries[index];
        if (entry.recovery != CruxDbRecovery.recreate) continue;
        observations.add(
          CruxGuardFinding(
            location: file.locate(clause.offset),
            detail:
                '`$shape` wraps $reached — allowlisted for the '
                '${entry.storeName}: ${entry.reason}',
          ),
        );
      }
    }
  }

  for (var i = 0; i < entries.length; i++) {
    if (used.contains(i)) continue;
    findings.add(
      CruxGuardFinding(
        location: 'allowlist entry for ${entries[i].file}',
        detail:
            'matches no catch-all at an open. The entry permits something '
            'that is no longer there. Remove it — the list is meant to '
            'shrink, and a standing permission nobody is reading is how the '
            'next catch-all gets added without an argument.',
      ),
    );
  }

  findings.sort((a, b) => a.location.compareTo(b.location));
  observations.sort((a, b) => a.location.compareTo(b.location));

  return CruxGuardReport(
    guard: 'G5b — catch shapes at an open site',
    subject: subject,
    findings: findings,
    observations: observations,
    guideSection: '"Corruption, migration failure and version skew"',
    whatBroke:
        'A catch that cannot distinguish anything is wrapped around a call '
        'that reaches a database open.',
    whyTheRuleExists:
        'Three unrelated faults arrive at an open as one exception: the file '
        'is genuinely corrupt (the data is gone), OUR migration code threw '
        '(the transaction rolled back and every row is still there), or the '
        "file's version is higher than this build knows (nothing was written "
        'at all). A fourth, SQLITE_BUSY, is a live and healthy database that '
        'somebody else has open. A catch-all handles all four the same way, '
        'so whatever it does for the first it also does for the three where '
        'nothing was wrong — which is how a recovery written for damaged '
        "hardware came to delete a year of a paying customer's history, and "
        'how a broken migration can turn a feature off for every user with no '
        'diagnostic anywhere. The rule is negative and absolute because there '
        'is no version of "catch everything" that knows which one it caught.',
    theWayToGreen:
        'Catch the narrowest type that can only mean the thing you are '
        'handling. Around an open through crux_sqlite that is: '
        '`on CruxSqliteException` switched exhaustively over the sealed '
        'family (a fifth member then becomes a compile error rather than a '
        'silent last arm), `on DatabaseException` for a file that will not '
        'open at all — locked, read-only, unavailable — and '
        '`on FileSystemException` for a path that is not there. Anything '
        'outside those propagates, deliberately. Degrading is still allowed: '
        'what is forbidden is degrading without being able to say which fault '
        'caused it, so each typed arm reports at its own volume. Deleting the '
        'catch is usually simpler than it looks, because the open policy has '
        'already handled corruption before the exception reaches you.\n'
        '  HOW THIS GUARD DECIDES A CALL REACHES AN OPEN, AND WHAT IT DOES '
        'NOT SEE: it starts from `openDatabase(...)` and from '
        '`<policy>.open(...)`, then derives — over the sources it was handed '
        'and nothing else — every `static` method and `factory` constructor '
        'whose body reaches one of those, matched at call sites as '
        '`Class.method(...)`, repeating up to $kCruxOpenReachRounds rounds '
        'until the set stops growing. So a store factory is covered the day '
        'it is written, without being listed. It is a TEXT SCAN, NOT A CALL '
        'GRAPH: an open reached only through an instance method, a '
        'function-typed field, a tear-off, a top-level function, or a class '
        'in a package outside the scanned sources is not derived, and a '
        'catch-all around one of those is not flagged. Passing it in '
        'extraOpenEntryPoints is how that gap is closed deliberately rather '
        'than discovered.',
  );
}

// ---------------------------------------------------------------------------
// Finding the calls that reach an open
// ---------------------------------------------------------------------------

/// sqflite's own open, in any receiver form: bare, `databaseFactory.` or a
/// resolved factory variable.
final RegExp _openDatabaseCall = RegExp(r'\bopenDatabase\s*\(');

/// `<anything>.open(` — a candidate for the policy route, confirmed only when
/// the surrounding statement names a policy.
final RegExp _dotOpenCall = RegExp(r'\.\s*open\s*\(');

final RegExp _namesAPolicy = RegExp('policy', caseSensitive: false);

/// The open-reaching calls in [code], described for a failure message.
///
/// [code] must already be blanked by [_blankNonCode]: a `.open(` inside a
/// doc comment is not a call, and the fixtures that prove this guard are full
/// of prose about open calls.
List<String> _openReachingCallsIn(String code, Set<String> entryPoints) {
  final found = <String>{};
  if (_openDatabaseCall.hasMatch(code)) found.add('openDatabase(...)');
  for (final match in _dotOpenCall.allMatches(code)) {
    final statement = _statementAround(code, match.start);
    if (!_namesAPolicy.hasMatch(statement)) continue;
    found.add('CruxSqliteOpenPolicy.open(...)');
  }
  for (final entry in entryPoints) {
    final dot = entry.indexOf('.');
    if (dot <= 0) continue;
    final owner = RegExp.escape(entry.substring(0, dot));
    final member = RegExp.escape(entry.substring(dot + 1));
    if (RegExp('\\b$owner\\s*\\.\\s*$member\\s*\\(').hasMatch(code)) {
      found.add('$entry(...)');
    }
  }
  final out = found.toList()..sort();
  return out;
}

/// The statement text around [index] — back to the nearest `;`, `{` or `}`,
/// bounded, so `final db = await _policyFor(x).open(p);` is read whole while a
/// `policy` mentioned four statements earlier is not borrowed.
String _statementAround(String code, int index) {
  var start = index;
  final floor = index - 240 < 0 ? 0 : index - 240;
  while (start > floor) {
    final c = code[start - 1];
    if (c == ';' || c == '{' || c == '}') break;
    start--;
  }
  return code.substring(start, index);
}

// ---------------------------------------------------------------------------
// Deriving the entry points
// ---------------------------------------------------------------------------

/// A `static` method or `factory` constructor, with the class it belongs to
/// and its body.
final class _EntryDeclaration {
  const _EntryDeclaration(this.qualifiedName, this.body);

  /// `SqlTrendStore.open`.
  final String qualifiedName;

  /// The blanked source of the body, `{ … }` or the `=>` expression.
  final String body;
}

final RegExp _classDeclaration = RegExp(r'\bclass\s+(\w+)');

/// `static <Type> <name>(` — the type may carry one level of generics.
final RegExp _staticMember = RegExp(
  r'\bstatic\s+(?:const\s+|final\s+|late\s+)*'
  r'[\w$]+(?:<[^<>]*(?:<[^<>]*>[^<>]*)?>)?\??\s+'
  r'([\w$]+)\s*\(',
);

/// `factory <Class>.<name>(`.
final RegExp _factoryConstructor = RegExp(
  r'\bfactory\s+(\w+)\s*\.\s*(\w+)\s*\(',
);

Iterable<_EntryDeclaration> _entryDeclarations(String code) sync* {
  final classes = _classDeclaration.allMatches(code).toList();

  String? enclosingClass(int offset) {
    String? name;
    for (final match in classes) {
      if (match.start > offset) break;
      name = match.group(1);
    }
    return name;
  }

  for (final match in _staticMember.allMatches(code)) {
    final owner = enclosingClass(match.start);
    if (owner == null) continue;
    final body = _memberBody(code, match.end - 1);
    if (body == null) continue;
    yield _EntryDeclaration('$owner.${match.group(1)}', body);
  }
  for (final match in _factoryConstructor.allMatches(code)) {
    final body = _memberBody(code, match.end - 1);
    if (body == null) continue;
    yield _EntryDeclaration('${match.group(1)}.${match.group(2)}', body);
  }
}

/// The body that follows the parameter list opening at [parenIndex]: a
/// balanced `{ … }`, or an `=>` expression up to its `;`. `null` for an
/// abstract or external declaration with no body at all.
String? _memberBody(String code, int parenIndex) {
  final args = cruxBalancedParens(code, parenIndex);
  if (args == null) return null;
  var i = parenIndex + args.length;
  while (i < code.length) {
    final c = code[i];
    if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
      i++;
      continue;
    }
    if (code.startsWith('async*', i)) {
      i += 6;
      continue;
    }
    if (code.startsWith('async', i)) {
      i += 5;
      continue;
    }
    if (code.startsWith('sync*', i)) {
      i += 5;
      continue;
    }
    break;
  }
  if (i >= code.length) return null;
  if (code.startsWith('=>', i)) {
    final end = code.indexOf(';', i);
    return end < 0 ? code.substring(i) : code.substring(i, end);
  }
  if (code[i] != '{') return null;
  final close = _matchingBrace(code, i);
  if (close < 0) return null;
  return code.substring(i + 1, close);
}

// ---------------------------------------------------------------------------
// Walking try / on / catch
// ---------------------------------------------------------------------------

final class _CatchClause {
  const _CatchClause({
    required this.offset,
    required this.shape,
    required this.isCatchAll,
  });

  /// Offset of the `on` or `catch` keyword, for the finding's location.
  final int offset;

  /// How it reads in the source: `catch (e)`, `on Object catch`, `on Object`.
  final String shape;

  /// Whether it admits everything.
  final bool isCatchAll;
}

final class _TryStatement {
  const _TryStatement({required this.body, required this.clauses});

  /// The blanked source between the try block's braces.
  final String body;

  /// Its `on` / `catch` clauses, in source order.
  final List<_CatchClause> clauses;
}

final RegExp _tryKeyword = RegExp(r'\btry\s*\{');
final RegExp _onClause = RegExp(r'on\s+([\w.]+(?:<[^<>]*>)?)\s*');
final RegExp _catchClause = RegExp(r'catch\s*\([^()]*\)\s*');

/// The types that catch everything. `on dynamic` is legal Dart and reads as a
/// deliberate narrowing to a reader skimming for `Object`.
const Set<String> _catchAllTypes = <String>{'Object', 'dynamic'};

Iterable<_TryStatement> _tryStatements(String code) sync* {
  for (final match in _tryKeyword.allMatches(code)) {
    final brace = code.indexOf('{', match.start);
    if (brace < 0) continue;
    final close = _matchingBrace(code, brace);
    if (close < 0) continue;
    yield _TryStatement(
      body: code.substring(brace + 1, close),
      clauses: _clausesAfter(code, close + 1).toList(),
    );
  }
}

Iterable<_CatchClause> _clausesAfter(String code, int start) sync* {
  var i = start;
  while (true) {
    while (i < code.length && _isSpace(code[i])) {
      i++;
    }
    if (i >= code.length) return;
    if (code.startsWith('finally', i)) return;

    final keyword = i;
    String? type;
    final on = _onClause.matchAsPrefix(code, i);
    if (on != null) {
      type = on.group(1);
      i = on.end;
    }
    final caught = _catchClause.matchAsPrefix(code, i);
    if (caught != null) {
      i = caught.end;
    } else if (type == null) {
      return;
    }
    if (i >= code.length || code[i] != '{') return;
    final close = _matchingBrace(code, i);
    if (close < 0) return;

    final shape = type == null
        ? 'catch (…)'
        : caught == null
        ? 'on $type'
        : 'on $type catch';
    yield _CatchClause(
      offset: keyword,
      shape: shape,
      isCatchAll: type == null || _catchAllTypes.contains(type),
    );
    i = close + 1;
  }
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\r' || c == '\t';

/// The index of the `}` matching the `{` at [open], or `-1`.
///
/// Safe on raw source only after [_blankNonCode]: a `{` in a string literal or
/// a comment would otherwise unbalance the walk.
int _matchingBrace(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Blanking comments and string literals
// ---------------------------------------------------------------------------

/// [source] with every comment and every string literal's contents replaced by
/// spaces, **preserving every offset and every newline**.
///
/// Offsets are preserved so a finding still points at the real line. The
/// blanking itself is what makes brace-matching and the `static`/`class`
/// regexes trustworthy: without it a `{` inside a string, a `try {` inside a
/// doc comment, or the phrase "on Object" in the paragraph explaining why one
/// must not be used would each be read as code — and this guard's whole
/// subject matter is written about in the comments beside it.
String _blankNonCode(String source) {
  final out = List<String>.filled(source.length, '');
  for (var i = 0; i < source.length; i++) {
    out[i] = source[i];
  }
  void blank(int from, int to) {
    for (var i = from; i < to && i < source.length; i++) {
      if (source[i] != '\n' && source[i] != '\r') out[i] = ' ';
    }
  }

  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      var end = source.indexOf('\n', i);
      if (end < 0) end = source.length;
      blank(i, end);
      i = end;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      // Dart block comments nest.
      var depth = 0;
      var j = i;
      while (j < source.length) {
        if (source.startsWith('/*', j)) {
          depth++;
          j += 2;
          continue;
        }
        if (source.startsWith('*/', j)) {
          depth--;
          j += 2;
          if (depth == 0) break;
          continue;
        }
        j++;
      }
      blank(i, j);
      i = j;
      continue;
    }
    if (c == "'" || c == '"') {
      final isRaw = i > 0 && source[i - 1] == 'r';
      final isTriple = source.startsWith(c * 3, i);
      final terminator = isTriple ? c * 3 : c;
      var j = i + terminator.length;
      while (j < source.length) {
        if (!isRaw && source[j] == r'\') {
          j += 2;
          continue;
        }
        if (!isTriple && source[j] == '\n') break;
        if (source.startsWith(terminator, j)) {
          j += terminator.length;
          break;
        }
        j++;
      }
      // Keep the quotes, blank the contents — an empty pair of quotes is
      // still recognisably a literal to anything reading the result.
      blank(i + terminator.length, j - terminator.length);
      i = j;
      continue;
    }
    i++;
  }
  return out.join();
}
