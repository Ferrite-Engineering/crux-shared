// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One source file handed to [cruxAuditEulaSeededBoots]: its path, for the
/// finding, and its text.
@immutable
final class CruxEulaGuardSource {
  /// Creates a source.
  const CruxEulaGuardSource({required this.path, required this.source});

  /// The path a finding names, normally relative to the repository root.
  final String path;

  /// The file's text.
  final String source;
}

/// A boot call with no EULA acceptance seeded before it.
@immutable
final class CruxEulaSeedFinding {
  /// Creates a finding.
  const CruxEulaSeedFinding({
    required this.path,
    required this.line,
    required this.call,
  });

  /// The file holding the call.
  final String path;

  /// The call's 1-based line.
  final int line;

  /// The boot function called.
  final String call;

  @override
  String toString() =>
      '$path:$line: `$call(` boots the app with no EULA acceptance seeded '
      'before it. CruxEulaGate covers the app with a modal barrier until the '
      'agreement is accepted, so every tap in this test misses. Seed '
      'acceptance first (a seed helper, or kCruxEulaAcceptedVersionKey set to '
      'kCruxEulaVersion), or pass `acceptEula: false` if the agreement is '
      "this test's subject.";
}

/// Finds every integration-test boot that does not seed EULA acceptance first.
///
/// `CruxEulaGate` shows the agreement until it is accepted, behind a modal
/// barrier that swallows every gesture. An integration test that boots the
/// app without seeding acceptance has every tap miss, and because
/// integration tests run weekly the failure surfaces up to a week late,
/// behind whatever else broke that week.
///
/// A call to one of [bootCalls] (`bootstrap` by default; a product adds any
/// boot helper of its own that does **not** seed) is seeded when, earlier in
/// the file, one of [seedCalls] is called or `kCruxEulaAcceptedVersionKey` is
/// named, either:
///
///  * in the same block as the boot call or a block enclosing it, so a seed
///    in a sibling test does not count; or
///  * inside a `setUp` or `setUpAll` callback, which runs before every test
///    the file holds.
///
/// A boot call whose arguments say `acceptEula: false` is the agreement's own
/// test and is never flagged.
///
/// Comments and string literals are blanked first, so a mention in prose is
/// neither a boot nor a seed. This is a text scan: a boot reached through a
/// helper not named in [bootCalls] is not seen, which is why each product
/// names its own.
List<CruxEulaSeedFinding> cruxAuditEulaSeededBoots({
  required Iterable<CruxEulaGuardSource> sources,
  Set<String> bootCalls = const <String>{'bootstrap'},
  Set<String> seedCalls = const <String>{'seedEulaAcceptance'},
}) {
  final findings = <CruxEulaSeedFinding>[];
  final bootPattern = _callPattern(bootCalls);
  final seedPattern = RegExp(
    [
      if (seedCalls.isNotEmpty) _callPattern(seedCalls).pattern,
      r'\bkCruxEulaAcceptedVersionKey\b',
    ].join('|'),
  );
  for (final file in sources) {
    final code = _blankNonCode(file.source);
    final seeds = [for (final m in seedPattern.allMatches(code)) m.start];
    for (final boot in bootPattern.allMatches(code)) {
      // A declaration of the boot function itself is not a call to it.
      if (_isDeclaration(code, boot.start)) continue;
      final open = code.indexOf('(', boot.start);
      final close = _matching(code, open, '(', ')');
      final args = close < 0 ? '' : code.substring(open, close);
      if (RegExp(r'\bacceptEula\s*:\s*false\b').hasMatch(args)) continue;
      final seeded = seeds.any(
        (s) =>
            s < boot.start &&
            (_inSameFunction(code, s, boot.start) || _inSetUp(code, s)),
      );
      if (seeded) continue;
      findings.add(
        CruxEulaSeedFinding(
          path: file.path,
          line: '\n'.allMatches(code.substring(0, boot.start)).length + 1,
          call: boot.group(1)!,
        ),
      );
    }
  }
  return findings;
}

RegExp _callPattern(Set<String> names) => RegExp(
  '(?<![\\w\$])(${names.map(RegExp.escape).join('|')})\\s*\\(',
);

/// Whether the function body holding [seed] also holds [boot]: the seed runs
/// earlier in the same call, at any depth (inside an `if` that guards it,
/// too), or in a function the boot's own closure is nested in. A seed in a
/// sibling test's closure does not.
bool _inSameFunction(String code, int seed, int boot) {
  final body = _enclosingFunctionBody(code, seed);
  if (body < 0) return true;
  final close = _matching(code, body, '{', '}');
  return close < 0 || boot < close;
}

const Set<String> _controlKeywords = {
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'on',
};

/// The offset of the `{` opening the innermost function body around [at],
/// or -1 at the top level. A block opened by `if`, `for`, `while`, `switch`,
/// `catch`, `else`, `try`, `do` or `finally` is not a function body.
int _enclosingFunctionBody(String code, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = code[i];
    if (c == '}') {
      depth++;
      continue;
    }
    if (c != '{') continue;
    if (depth > 0) {
      depth--;
      continue;
    }
    if (_opensFunctionBody(code, i)) return i;
  }
  return -1;
}

bool _opensFunctionBody(String code, int brace) {
  var i = brace - 1;
  void skipSpace() {
    while (i >= 0 && ' \t\r\n'.contains(code[i])) {
      i--;
    }
  }

  skipSpace();
  for (final modifier in ['async*', 'sync*', 'async']) {
    if (i - modifier.length + 1 >= 0 &&
        code.substring(i - modifier.length + 1, i + 1) == modifier) {
      i -= modifier.length;
      skipSpace();
      break;
    }
  }
  if (i < 0 || code[i] != ')') return false;
  var depth = 0;
  for (; i >= 0; i--) {
    if (code[i] == ')') depth++;
    if (code[i] == '(') {
      depth--;
      if (depth == 0) break;
    }
  }
  i--;
  skipSpace();
  final end = i;
  while (i >= 0 && RegExp(r'[\w$]').hasMatch(code[i])) {
    i--;
  }
  return !_controlKeywords.contains(code.substring(i + 1, end + 1));
}

final RegExp _setUpOpener = RegExp(
  r'\bsetUp(?:All)?\s*\(\s*\(\s*\)\s*(?:async\s*)?\{$',
);

/// Whether [at] lies inside a `setUp` / `setUpAll` callback body.
bool _inSetUp(String code, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = code[i];
    if (c == '}') {
      depth++;
    } else if (c == '{') {
      if (depth == 0) {
        final head = code.substring(i - 80 < 0 ? 0 : i - 80, i + 1);
        if (_setUpOpener.hasMatch(head)) return true;
      } else {
        depth--;
      }
    }
  }
  return false;
}

/// Whether the name at [at] is declared rather than called: preceded by a
/// return type (`Future<void> bootstrap(`), not by an operator, `await` or
/// punctuation.
bool _isDeclaration(String code, int at) {
  var i = at - 1;
  while (i >= 0 && (code[i] == ' ' || code[i] == '\t')) {
    i--;
  }
  if (i < 0) return false;
  final c = code[i];
  if (c == '>' || c == '?') return true;
  if (!RegExp(r'[\w$]').hasMatch(c)) return false;
  var j = i;
  while (j >= 0 && RegExp(r'[\w$]').hasMatch(code[j])) {
    j--;
  }
  final word = code.substring(j + 1, i + 1);
  return !const {'await', 'return', 'yield', 'else', 'unawaited'}.contains(
    word,
  );
}

int _matching(String code, int open, String opener, String closer) {
  if (open < 0) return -1;
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    if (code[i] == opener) depth++;
    if (code[i] == closer) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// [source] with comments and string-literal contents replaced by spaces,
/// keeping every offset and newline.
String _blankNonCode(String source) {
  final out = source.split('');
  void blank(int from, int to) {
    for (var i = from; i < to && i < source.length; i++) {
      if (source[i] != '\n') out[i] = ' ';
    }
  }

  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      var end = source.indexOf('\n', i);
      if (end < 0) end = source.length;
      blank(i, end);
      i = end;
      continue;
    }
    if (source.startsWith('/*', i)) {
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
    final c = source[i];
    if (c == "'" || c == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final terminator = source.startsWith(c * 3, i) ? c * 3 : c;
      var j = i + terminator.length;
      while (j < source.length) {
        if (!raw && source[j] == r'\') {
          j += 2;
          continue;
        }
        if (terminator.length == 1 && source[j] == '\n') break;
        if (source.startsWith(terminator, j)) {
          j += terminator.length;
          break;
        }
        j++;
      }
      blank(i + terminator.length, j - terminator.length);
      i = j;
      continue;
    }
    i++;
  }
  return out.join();
}
