// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard for the mechanically checkable claims in crux-shared's root
// reference documents. An audit once found both root docs materially wrong
// about the single most basic fact in the repo — the package inventory (one
// said 7 packages, one said 6, there were 15). Prose has no compiler, so that
// decay is only ever found by a human sweep; this guard replaces the sweep.
//
// Three claim classes are checked:
//
//  1. Path existence. A repo-relative path written in a reference document
//     must resolve to a file or directory on disk.
//  2. Package-table inventory. The package table in each root document must
//     name exactly the set of `packages/*` directories — no more, no fewer.
//     This is the class that would have caught that inventory rot, and it
//     enforces step 7 of the "Adding a new package" checklist (add a table row
//     to CLAUDE.md and README.md) mechanically.
//  3. Per-package documents. Every `packages/*` directory carries a README.md
//     and a CHANGELOG.md. The root README says every package has its own
//     README, and step 6 of the checklist asks for both; without a check, six
//     packages had shipped without one or the other.
//
// A derived package-count class was considered and rejected: the root docs
// deliberately say "the authoritative list is `ls packages/`" rather than a
// figure, and "N packages" in prose almost always means "N packages had some
// property", not "the total is N" — so a count guard is all false positive and
// no signal. The inventory class checks the actual set, which is stronger.
//
// The path extractor is scoped rather than allowlisted. It reads only
// backticked tokens and Markdown link targets, ignores fenced code blocks,
// ignores tokens carrying glob or placeholder punctuation, strips trailing
// shell arguments, and requires a repo-root directory prefix so that
// per-package paths (`lib/`, `test/`) and cross-repo references resolve as
// prose rather than as broken local paths.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Documents whose claims are binding, relative to the workspace root.
const _referenceDocs = ['CLAUDE.md', 'README.md', 'docs/adr/README.md'];

/// The documents every package directory must carry.
const _perPackageDocs = ['README.md', 'CHANGELOG.md'];

/// Top-level directories that mark a token as a repo-root-relative path. A
/// token without one of these prefixes is prose, a package-internal path
/// (`lib/`, `test/` appear illustratively in the "Adding a new package"
/// steps), or a path in another repository, and is not this guard's business.
const _pathPrefixes = [
  'packages/',
  'docs/',
  'tool/',
  'api/',
  '.github/',
];

/// Characters that mark a token as a pattern, a placeholder, or prose rather
/// than a literal path.
const _patternChars = ['*', '<', '>', '{', '}', '?', '…', '|', ',', '(', ')'];

final _linkRe = RegExp(r'\[((?:[^\]\\]|\\.)*)\]\(([^)\s]+)\)');
final _tickRe = RegExp(r'`([^`\n]+)`');
final _uriRe = RegExp('^[a-z][a-z0-9+.-]*:');

/// A claim and the document location that makes it.
class _Claim {
  const _Claim(this.doc, this.line, this.text);

  final String doc;
  final int line;
  final String text;

  @override
  String toString() => '$doc:$line — $text';
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

/// Returns [source]'s lines with fenced-code content blanked, preserving line
/// numbering so findings point at the right row.
List<String> _linesOutsideFences(String source) {
  final lines = <String>[];
  var inFence = false;
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      lines.add('');
      continue;
    }
    lines.add(inFence ? '' : line);
  }
  return lines;
}

/// Extracts path-shaped tokens from one document line.
///
/// A Markdown link carries the path in its target when the target is
/// repo-relative, and in its label when the target is an external URL (the
/// label names the local file, the URL names its published copy). Both forms
/// are handled so neither hides a stale path.
List<String> _pathTokens(String line) {
  final tokens = <String>[];
  var remainder = line;
  for (final match in _linkRe.allMatches(line)) {
    final label = match.group(1)!;
    final target = match.group(2)!;
    if (_uriRe.hasMatch(target)) {
      tokens.addAll(_tickRe.allMatches(label).map((m) => m.group(1)!));
    } else {
      tokens.add(target);
    }
    remainder = remainder.replaceFirst(match.group(0)!, ' ');
  }
  tokens.addAll(_tickRe.allMatches(remainder).map((m) => m.group(1)!));
  return tokens;
}

/// Normalizes a token to a candidate path, or returns null if it is not one.
String? _asRepoPath(String token) {
  // Strip a trailing shell argument (`tool/api-snapshot.sh --check`), a
  // `path::test name` suffix, and a `#anchor`.
  var candidate = token.trim().split(RegExp(r'\s')).first;
  candidate = candidate.split('::').first.split('#').first;
  while (candidate.isNotEmpty &&
      '.,;:'.contains(candidate[candidate.length - 1])) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  if (!candidate.contains('/')) return null;
  if (!_pathPrefixes.any(candidate.startsWith)) return null;
  if (_patternChars.any(candidate.contains)) return null;
  return candidate;
}

/// Every path-shaped token in the reference documents, with its location.
List<_Claim> _documentedPaths(String root) {
  final claims = <_Claim>[];
  for (final doc in _referenceDocs) {
    final file = File(p.join(root, doc));
    if (!file.existsSync()) continue;
    final lines = _linesOutsideFences(file.readAsStringSync());
    for (var i = 0; i < lines.length; i++) {
      for (final token in _pathTokens(lines[i])) {
        final path = _asRepoPath(token);
        if (path != null) claims.add(_Claim(doc, i + 1, path));
      }
    }
  }
  return claims;
}

// --- Package-table inventory -------------------------------------------

final _packageNameRe = RegExp(r'crux_\w+');

/// The set of `crux_*` package names a document's package table names. Read
/// from the FIRST cell of each Markdown table row only (CLAUDE.md writes
/// `` | `crux_io` | … ``, README writes `` | [`crux_io`](packages/crux_io) |
/// … ``), so prose mentions of a non-package — e.g. the future `crux_session`
/// extraction — are not miscounted as inventory.
Set<String> _documentedPackages(String root, String doc) {
  final file = File(p.join(root, doc));
  if (!file.existsSync()) return <String>{};
  final names = <String>{};
  for (final line in file.readAsLinesSync()) {
    if (!line.startsWith('|')) continue;
    final cells = line.split('|');
    if (cells.length < 2) continue;
    final match = _packageNameRe.firstMatch(cells[1]);
    if (match != null) names.add(match.group(0)!);
  }
  return names;
}

/// The set of package directories actually present under `packages/`.
Set<String> _actualPackages(String root) => Directory(p.join(root, 'packages'))
    .listSync()
    .whereType<Directory>()
    .map((d) => p.basename(d.path))
    .where((n) => n.startsWith('crux_'))
    .toSet();

void main() {
  final root = _workspaceRoot();

  test('the workspace root resolved and holds the reference docs', () {
    expect(File(p.join(root, 'CLAUDE.md')).existsSync(), isTrue);
    expect(File(p.join(root, 'README.md')).existsSync(), isTrue);
    expect(_actualPackages(root).length, greaterThan(10));
  });

  test('every documented repo path exists', () {
    final missing =
        _documentedPaths(root)
            .where((c) => !File(p.join(root, c.text)).existsSync())
            .where((c) => !Directory(p.join(root, c.text)).existsSync())
            .map((c) => c.toString())
            .toSet()
            .toList()
          ..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'A reference document names a path that is not in the tree. Either '
          'the file moved and the document was not updated, or the document '
          'describes something that was never built. Correct the document; do '
          'not exempt the path.\n${missing.join('\n')}',
    );
  });

  test("each root document's package table matches the tree exactly", () {
    final actual = _actualPackages(root);
    final problems = <String>[];
    for (final doc in ['CLAUDE.md', 'README.md']) {
      final documented = _documentedPackages(root, doc);
      final missing = actual.difference(documented).toList()..sort();
      final phantom = documented.difference(actual).toList()..sort();
      for (final m in missing) {
        problems.add('$doc: package `$m` exists but is not in the table');
      }
      for (final ph in phantom) {
        problems.add('$doc: table names `$ph`, which is not a package');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'A root document package inventory disagrees with `ls packages/`. '
          'This is exactly how the inventory rots. Add the missing row (see '
          '"Adding a new package" step 7) or remove the phantom one.\n'
          '${problems.join('\n')}',
    );
  });

  test('every package carries a README.md and a CHANGELOG.md', () {
    final missing = <String>[
      for (final package in _actualPackages(root).toList()..sort())
        for (final doc in _perPackageDocs)
          if (!File(p.join(root, 'packages', package, doc)).existsSync())
            'packages/$package/$doc',
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'A package is missing its own README or CHANGELOG. The root README '
          'promises every package has a README with its full surface, and '
          '"Adding a new package" step 6 asks for both. Write the document; do '
          'not exempt the package.\n${missing.join('\n')}',
    );
  });
}
