// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: nothing tracked in crux-shared points a reader at a repository
// or a planning document they cannot open.
//
// crux-shared is public under Apache 2.0. Its readers have this repository,
// the four open-core products, the published pages on the product sites, and
// nothing else. A comment that says "see" a path in a closed repository, a
// doc that justifies a rule by a section of an unpublished plan, or a test
// named after a row in an internal tracker is a dead end for every one of
// them — and a quiet disclosure of how the closed half is laid out.
//
// So the rule is: state the reason in place, or cite something the reader can
// open — a file in this repository, an ADR under `docs/adr/`, or a public page
// such as the CXP specification or the policy file reference.
//
// WHAT IS SCANNED
// Every file git tracks or would track (`git ls-files --cached --others
// --exclude-standard`): source, tests, READMEs, changelogs, pubspecs, ADRs,
// workflows and tools, comments and string literals alike. A test name is
// text a public reader sees in CI output, so it is held to the same bar.
// Skipped: files that are not UTF-8 text, and the files generated from
// third-party inputs
// (`pubspec.lock` resolutions and the `NOTICES` licence texts).
//
// WHAT IS REJECTED
// Four classes, each a pattern list below:
//  1. Closed repositories, by path or by name — the repository that holds the
//     suite's plans, the four Pro overlay repositories, and the update,
//     commerce, website and analytics repositories. The Pro overlay as a
//     *concept* is public and fine to describe ("the Pro overlay overrides
//     this provider"); its repository name and paths are not.
//  2. Unpublished planning documents — suite, product, launch and business
//     planning, the UI consistency rules and their rulings, campaign and
//     track paths, prompt sets, and the closed specifications and guides that
//     have a public replacement.
//  3. Roadmap phases, which number a plan the reader does not have.
//  4. Tracker identifiers — workstream, round, ruling, finding and prompt ids.
//
// THE ALLOWLIST
// An entry names one exact file and one exact matched text, with the reason
// that occurrence is legitimate (a shipped executable that happens to share a
// repository's name, say). It is empty, and an entry that stops matching
// fails the run, so the list cannot rot into a set of standing holes.
//
// The patterns are written so they do not match their own source text: each
// literal is broken by a regex construct, which is why several read oddly.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// One class of reference this guard rejects.
class _Rule {
  const _Rule(this.name, this.pattern, this.planted);

  /// What the rule catches, as a failure message names it.
  final String name;

  /// The pattern. A line containing a match is an offender.
  final RegExp pattern;

  /// Text the pattern must match — proof the pattern has not rotted into one
  /// that matches nothing. Assembled from pieces so this file stays clean.
  final List<String> planted;
}

final List<_Rule> _rules = <_Rule>[
  _Rule(
    'a path into the closed repository that holds the plans',
    RegExp(r'(?<![\w./@~-])edacr(?:ux)/'),
    ['see `${'edacr'}ux/docs/specs/x.md`', '${'edacr'}ux/tool/y.py'],
  ),
  _Rule(
    'that closed repository by name',
    RegExp(
      r'`edacr(?:ux)`|\bedacr(?:ux) (?:repo|repository)\b|'
      r'\bplanning (?:repo|repository)\b|\bprivate plan(?:ning|s?\b)',
      caseSensitive: false,
    ),
    ['in the sibling `${'edacr'}ux` repo', 'the private ${'plann'}ing docs'],
  ),
  _Rule(
    'a Pro overlay repository by name or path',
    RegExp(
      r'\b(?:wave|net|lint|sim)crux-pr(?:o)\b(?!-)|\*-pr(?:o)\b|'
      r'<product>-pr(?:o)\b|\$\{?product\}?-pr(?:o)\b|\bcrux-shared-pr(?:o)\b',
    ),
    [
      '`lint${'crux-pro'}/lib/x.dart`',
      'each `*${'-pro'}` overlay',
      '../<product>${'-pro'}/<product>',
    ],
  ),
  // The beta repos close at the open-core flip (L4): they are the beta
  // cohort's public record, and archived-then-private is a 404 to anyone
  // who follows a link into one.
  _Rule(
    'a beta-period repository by name',
    RegExp(
      r'\b(?:wave|net|lint|sim)crux-bet(?:a)\b',
      caseSensitive: false,
    ),
    ['see wave${'crux-beta'} issue #9', '`lint${'crux-beta'}`'],
  ),
  _Rule(
    'another closed repository by name',
    RegExp(
      r'\b(?:crux-upd(?:ates)|wavecrux-upd(?:ates)|crux-comm(?:erce)|'
      'ferrite-web(?:site)|(?:wave|net|lint|sim|eda)crux-web(?:site)|'
      r'vcd_pars(?:er))\b|\bpulse(?:crux)\b|\banne(?:al)\b',
      caseSensitive: false,
    ),
    ['`crux-${'updates'}/telemetry`', 'belongs to `crux-${'commerce'}`'],
  ),
  _Rule(
    'an unpublished planning document',
    RegExp(
      r'\b(?:suite|project|strategic|business|ecosystem|increment|launch)'
      r'[- ]pla(?:ns?)\b|commercial[- ]lau(?:nch)|RISCV_ECOSYS(?:TEM)|'
      r'consistency char(?:ter)|\bchar(?:ter)\s*§|\bchar(?:ter) rulings?\b|'
      r'\bpla(?:n)\s*§|sqlite-migration-gui(?:de)|export-control-posi(?:tion)|'
      'crux-policy-sp(?:ec)|crux-project-sp(?:ec)|'
      r'accessibility-verifi(?:cation)|\bdecisi(?:ons)\.md\b|'
      r'WORLD_CLASS_QUAL(?:ITY)|\bcampaig(?:ns?)/|\btrac(?:ks)/|'
      r'\bquality[- ]rou(?:nd)\b|audit-remedi(?:ation)|'
      r'\bexecution[- ]promp(?:ts?)\b|\bcross-probe incr(?:ement)\b|'
      r'\b20\d\d-\d\d-[a-z][\w-]*-(?:acceleration|remediation|round|crash|'
      r'sweep|hardening|restructure)\b',
      caseSensitive: false,
    ),
    [
      'the suite ${'plan'} §6.1',
      '`commercial-${'launch'}-plan.md`',
      'the UI consistency ${'charter'} §2',
      '2026-08-phase7-${'acceleration'} K1',
      'the CXP Cross-Probe ${'Increment'}',
    ],
  ),
  _Rule(
    'a roadmap phase',
    RegExp(r'\bPha(?:se)[ -]\d+(?:\.\d+)*\b'),
    ['added with ${'Phase'} 6', 'in ${'Phase'} 4.13.2'],
  ),
  _Rule(
    'a tracker identifier',
    RegExp(
      r'\bW(?:S)-[A-Z]\b|\bW(?:S)\d+\b|\bC(?:S)\d{1,2}(?:\.\d+)?\b|'
      r'\bR-[A-Z]{1,3}\d{1,2}\b|\b(?:NC|WC|LC|SC)\d{1,2}\b|'
      r'\b[ADF]-\d{2}\b|\bProm(?:pt) \d+\b|\bIss(?:ue)-\d+\b|'
      r'\b(?:bug|finding|defect|item|prompt)s? [A-Z]{1,2}\d{1,2}[a-z]?\b|'
      r'\((?:[ACDKMN]|MD)\d{1,2}\)|'
      r"\b(?:[ABCDGKLMN]|MD)\d{1,2}(?:'s)? (?:left|decided|decision|measured|"
      r'identified)\b',
    ),
    [
      'shared-workspace link (${'WS'}-E)',
      'group(${"'"}${'CS'}5.8 — ...',
      'ruling R-${'CS'}4',
      'audit ${'F'}-17',
      'NetCrux bug ${'N'}1',
      "which ${'C'}1 left open",
    ],
  ),
];

/// Occurrences that are legitimate, as `<repo-relative path>` → matched text
/// → reason. Empty by design; see the header.
const Map<String, Map<String, String>> _allowlist =
    <String, Map<String, String>>{};

/// Files never scanned, with the reason.
const Map<String, String> _skipped = <String, String>{
  'pubspec.lock': 'resolver output, not prose',
  'tool/api_snapshot/pubspec.lock': 'resolver output, not prose',
  'NOTICES': 'third-party licence texts, generated from pubspec.lock',
};

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

/// Every file git tracks or would track, repo-relative, with `/` separators.
List<String> _trackedFiles(String root) {
  final result = Process.runSync(
    'git',
    ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    workingDirectory: root,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    fail('git ls-files failed in $root: ${result.stderr}');
  }
  return (result.stdout as String)
      .split(String.fromCharCode(0))
      .where((f) => f.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

/// [relative]'s text, or null when it is gone or is not UTF-8 text.
String? _textOf(String root, String relative) {
  final file = File(p.join(root, relative));
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// One rejected occurrence.
class _Hit {
  const _Hit(this.path, this.line, this.rule, this.text);

  final String path;
  final int line;
  final String rule;
  final String text;

  @override
  String toString() => '$path:$line — $rule: "$text"';
}

List<_Hit> _scan(String root, List<String> files) {
  final hits = <_Hit>[];
  for (final relative in files) {
    if (_skipped.containsKey(relative)) continue;
    final text = _textOf(root, relative);
    if (text == null) continue;
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      for (final rule in _rules) {
        for (final match in rule.pattern.allMatches(lines[i])) {
          hits.add(_Hit(relative, i + 1, rule.name, match.group(0)!));
        }
      }
    }
  }
  return hits;
}

bool _allowed(_Hit hit) => _allowlist[hit.path]?.containsKey(hit.text) ?? false;

void main() {
  final root = _workspaceRoot();
  final files = _trackedFiles(root);
  final hits = _scan(root, files);

  test('the tracked file list resolved', () {
    expect(
      files.length,
      greaterThan(300),
      reason: 'git ls-files returned too little; the root or checkout changed',
    );
    expect(files, contains('CLAUDE.md'));
  });

  test('every rule still matches what it exists to reject', () {
    for (final rule in _rules) {
      for (final sample in rule.planted) {
        expect(
          rule.pattern.hasMatch(sample),
          isTrue,
          reason: 'the "${rule.name}" pattern no longer matches "$sample"',
        );
      }
    }
  });

  test('public references stay allowed', () {
    const publicText = <String>[
      'https://edacrux.app/cxp#sec-9-1-1',
      'https://docs.netcrux.app/getting-started',
      'the Pro overlay overrides licenseTierProvider',
      '/etc/edacrux/.crux-policy.json',
      "'wavecrux-pro-monthly': stripe lookup key",
      'guard G1 — frozen schema fingerprints',
      'https://github.com/Ferrite-Engineering/crux-shared',
      'simulated annealing',
      'CXP §9.10.1',
    ];
    for (final text in publicText) {
      for (final rule in _rules) {
        expect(
          rule.pattern.hasMatch(text),
          isFalse,
          reason: '"${rule.name}" wrongly rejects public text "$text"',
        );
      }
    }
  });

  test('no tracked file points at a closed repository or plan', () {
    final offenders = hits.where((h) => !_allowed(h)).map((h) => '$h').toList();
    expect(
      offenders,
      isEmpty,
      reason:
          'A tracked file points a public reader at something they cannot '
          'open. State the reason in place, or cite a file in this repository '
          'or a public page (https://edacrux.app/cxp#sec-<n>-<n>, '
          'https://edacrux.app/policy-reference, …). Do not allowlist it '
          'unless the text is genuinely public — a shipped executable name, '
          'for instance.\n${offenders.join('\n')}',
    );
  });

  test('every allowlist entry still matches something', () {
    final stale = <String>[
      for (final entry in _allowlist.entries)
        for (final text in entry.value.keys)
          if (!hits.any((h) => h.path == entry.key && h.text == text))
            '${entry.key}: "$text"',
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'An allowlist entry no longer matches anything. Remove it.\n'
          '${stale.join('\n')}',
    );
  });
}
