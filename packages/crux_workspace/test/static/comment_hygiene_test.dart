// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard for the Crux suite's clinical-comment convention, applied
// across every package in the crux-shared workspace. crux-shared goes public
// under Apache 2.0 at the open-core flip, so its comments must read for a
// stranger who has only this repository.
//
// A comment must describe the code as it stands. Four classes of prose fail
// that test and are rejected here:
//
//  1. Backlog / track identifiers used as anchors. A work-item id — a
//     two-letter product or round prefix and a row number, or a ruling id
//     behind an `R-` prefix — names an entry in a tracker the reader cannot
//     open, so a comment anchored to one says nothing to them. Citations of a
//     document committed to this repository (an ADR under `docs/adr/`, a
//     package README) are NOT in this class — the reference stays
//     resolvable.
//  2. Dates used as process notes. A stamp narrating when work happened
//     carries no information about the code. Dates that are DATA — a beta
//     expiry the code enforces, a calendar-validation example, a licence
//     header — are unaffected; the class matches only a date in an
//     authorship / change-history context.
//  3. Session / process voice. Prose scoped to the sitting that wrote it
//     ("this round", "for now", person-addressed TODOs) expires immediately.
//     Note "session" is domain vocabulary here (a workspace / app session is a
//     first-class concept), so it is not matched on its own.
//  4. Reviewer voice. A comment addressed to someone reading the change,
//     rather than to someone reading the code, is misfiled — that content
//     belongs in the commit message.
//
// SCOPE. Classes 2–4 scan every `packages/*/lib`. Class 1 scans every
// `packages/*/lib` AND every `packages/*/test`: a test comment anchored to a
// work-item id is as unreadable to a public reader as a production one, and
// test names and reasons are where regression history most wants to cite one.
// Test and group *names* are string literals, which this scanner skips;
// `no_private_references_test.dart` covers those, and every other tracked
// file, for the same ids.
//
// Only comment text is examined. String literals are skipped by the scanner,
// so identifier-shaped domain data cannot trigger a finding, and the patterns
// written below do not match themselves.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Round identifiers: a two-letter product or round prefix plus a row number.
/// Bare match — no such token has a legitimate meaning in this repository's
/// code or tests.
final _roundIdRe = RegExp(r'\b(?:CS|NC|WC|LC|SC)\d{1,2}\b');

/// Ruling identifiers (an `R-` prefix on a round id) and section-mark anchors
/// into a backlog (a section mark, `item` or `track` before a letter-and-number
/// id), matched behind a reference marker so bare domain vocabulary is
/// untouched.
final _trackIdRe = RegExp(
  r'\bR-CS\d{1,2}\b|'
  r'''(?:§|\bitems?[ -]|\btracks?[ -]|\bbacklog[ -])'''
  r'[GNWLSX]\d{1,2}\b',
);

/// Prose forms of the same anchor, which name a backlog without an id.
final _backlogProseRe = RegExp(
  r'\bbacklog (?:item|anchor|row)\b|\bper the batch\b|'
  r'\btracked in PENDING\b|\bexecution prompt\b',
  caseSensitive: false,
);

/// Process-note dates: a calendar date in an authorship / change-history
/// context. crux-shared carries legitimate DATA dates (the beta-expiry the
/// code enforces, `2026-02-30`-style validation examples), so — unlike the
/// product guards, whose `lib/` had none — the class does not match every
/// date. It matches a date next to a history verb, a bare leading date stamp,
/// or a `date:`/`date —` log prefix.
final _dateRe = RegExp(
  // A history verb followed (within a clause) by a date.
  r'\b(?:added|fixed|changed|renamed|moved|removed|updated|refactored|'
  'introduced|reverted|reviewed|landed|implemented|created|wrote|written|'
  r'done|completed|committed|as of|last updated)\b[^\n]{0,40}'
  r'\b(?:19|20)\d{2}-\d{2}-\d{2}\b|'
  // A date as a log-line stamp: at the comment-line start and standing alone
  // or introducing a log message (`// 2026-07-19: …`), not a date embedded in
  // descriptive prose (`… through 2026-08-31 and becomes …`, which is data).
  r'^\s*(?://+|\*)\s*(?:19|20)\d{2}-\d{2}-\d{2}\s*(?:[:—-]|$)',
  caseSensitive: false,
  multiLine: true,
);

/// Session / process voice. "this session" is deliberately absent: a workspace
/// / app session is domain vocabulary here.
final _sessionVoiceRe = RegExp(
  r'\bthis (?:round|batch|sweep)\b|\bfor now\b|'
  r'\bas discussed\b|\bwe decided\b|\bnote to self\b|'
  r'\bat the time of writing\b|\bas of (?:today|this writing)\b|'
  r'\bTODO\((?:martin|mfink|me|self)\)',
  caseSensitive: false,
);

/// Reviewer voice. First-person-plural change narration is included; bare
/// "we" is not, because it reads naturally in design rationale.
final _reviewerVoiceRe = RegExp(
  r'\bas you can see\b|\bnote that we\b|\bto the reviewer\b|'
  r'\breviewer note\b|\bin this (?:commit|PR|pull request|patch|diff|'
  r'changeset)\b|\b(?:before|after) this change\b|'
  r'\bwe (?:added|removed|changed|renamed|moved|introduced|reverted)\b|'
  r"\bI (?:added|removed|kept|decided)\b|\blet's\b|\bdon't forget\b|"
  r'\bper the review\b',
  caseSensitive: false,
);

/// Files exempt from every class, keyed by path suffix. Kept empty
/// deliberately: an entry here is a permanent hole in the guard, so a
/// violation is fixed rather than listed.
const Map<String, String> _allowlist = <String, String>{};

/// A comment occurrence: the 1-based line it starts on and its raw text.
class _Comment {
  const _Comment(this.line, this.text);

  final int line;
  final String text;
}

/// Extracts every comment from [source], skipping string literals so that
/// quoted data is never mistaken for prose.
List<_Comment> _extractComments(String source) {
  final comments = <_Comment>[];
  var line = 1;
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final nl = source.indexOf('\n', i);
      final end = nl == -1 ? source.length : nl;
      comments.add(_Comment(line, source.substring(i, end)));
      i = end;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final startLine = line;
      final close = source.indexOf('*/', i + 2);
      final end = close == -1 ? source.length : close + 2;
      final text = source.substring(i, end);
      comments.add(_Comment(startLine, text));
      line += '\n'.allMatches(text).length;
      i = end;
      continue;
    }
    if (c == "'" || c == '"') {
      final before = i;
      i = _skipString(source, i);
      line += '\n'.allMatches(source.substring(before, i)).length;
      continue;
    }
    i++;
  }
  return comments;
}

/// Advances past the string literal starting at [start] (its opening quote),
/// honouring raw prefixes, triple quotes, and backslash escapes.
int _skipString(String source, int start) {
  final quote = source[start];
  final isRaw = start > 0 && source[start - 1] == 'r';
  final triple = source.startsWith(quote * 3, start);
  final delimiter = triple ? quote * 3 : quote;
  var i = start + delimiter.length;
  while (i < source.length) {
    if (!isRaw && source[i] == r'\') {
      i += 2;
      continue;
    }
    if (source.startsWith(delimiter, i)) return i + delimiter.length;
    // An unterminated single-quoted literal cannot cross a line; bail out so
    // a malformed file degrades into over-scanning rather than swallowing the
    // rest of the source.
    if (!triple && source[i] == '\n') return i;
    i++;
  }
  return source.length;
}

/// Every package `lib` directory under the workspace root.
List<Directory> _libRoots() => _packageRoots('lib');

/// Every package `test` directory under the workspace root.
List<Directory> _testRoots() => _packageRoots('test');

List<Directory> _packageRoots(String child) {
  final packages = Directory(p.join(_workspaceRoot(), 'packages'));
  final roots =
      <Directory>[
          for (final entry in packages.listSync())
            if (entry is Directory) Directory(p.join(entry.path, child)),
        ].where((d) => d.existsSync()).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return roots;
}

/// The crux-shared workspace root, found by walking up from the test's working
/// directory (the `crux_workspace` package) until the root `pubspec.yaml`
/// naming the melos workspace is found.
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

List<File> _dartFilesUnder(Iterable<Directory> roots) {
  final files = <File>[];
  for (final dir in roots) {
    if (!dir.existsSync()) continue;
    files.addAll(
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // Generated output is not hand-written prose.
          .where((f) => !f.path.endsWith('.g.dart'))
          .where((f) => !f.path.endsWith('.freezed.dart')),
    );
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

bool _isAllowlisted(String relativePath) =>
    _allowlist.keys.any(relativePath.endsWith);

/// Runs [pattern] over every comment in [roots] and returns `path:line —
/// matched text` for each hit.
List<String> _scan(
  Iterable<Directory> roots,
  RegExp pattern, {
  bool Function(String commentText)? exempt,
}) {
  final root = _workspaceRoot();
  final offenders = <String>[];
  for (final file in _dartFilesUnder(roots)) {
    final relative = p.relative(file.path, from: root);
    if (_isAllowlisted(relative)) continue;
    for (final comment in _extractComments(file.readAsStringSync())) {
      if (exempt != null && exempt(comment.text)) continue;
      final match = pattern.firstMatch(comment.text);
      if (match == null) continue;
      offenders.add('$relative:${comment.line} — "${match.group(0)!.trim()}"');
    }
  }
  return offenders;
}

void main() {
  final libRoots = _libRoots();
  final anchorRoots = [...libRoots, ..._testRoots()];

  test('the workspace layout resolved', () {
    expect(
      libRoots.length,
      greaterThan(10),
      reason:
          'expected every package lib/ to be discovered; the workspace '
          'root or layout changed',
    );
  });

  test('no backlog or track identifiers used as comment anchors', () {
    final offenders = [
      ..._scan(anchorRoots, _roundIdRe),
      ..._scan(anchorRoots, _trackIdRe),
      ..._scan(anchorRoots, _backlogProseRe),
    ]..sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'A comment anchors on a backlog or track identifier. A public '
          'reader cannot resolve it. State what the code does and why; cite a '
          'document committed to this repository if an external reference is '
          'genuinely needed.\n'
          '${offenders.join('\n')}',
    );
  });

  test('no dates used as process notes in comments', () {
    final offenders = _scan(libRoots, _dateRe);
    expect(
      offenders,
      isEmpty,
      reason:
          'A comment carries a date narrating when work happened. When the '
          'work was done is recorded by git; the comment should record what '
          'the code does. (A date the code treats as data — a beta expiry, a '
          'validation example — is fine and is not matched.)\n'
          '${offenders.join('\n')}',
    );
  });

  test('no session or process voice in comments', () {
    final offenders = _scan(libRoots, _sessionVoiceRe);
    expect(
      offenders,
      isEmpty,
      reason:
          'A comment is scoped to the sitting that wrote it. Such prose '
          'cannot be evaluated by a later reader — describe the state of the '
          'code, not the state of the work.\n${offenders.join('\n')}',
    );
  });

  test('no reviewer voice in comments', () {
    final offenders = _scan(libRoots, _reviewerVoiceRe);
    expect(
      offenders,
      isEmpty,
      reason:
          'A comment addresses a reader of the change rather than a reader of '
          'the code. Change narration belongs in the commit message.\n'
          '${offenders.join('\n')}',
    );
  });
}
