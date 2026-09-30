// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard encoding crux-shared's domain-neutrality charter, so the two
// decisions that drew its current boundary cannot silently erode.
//
// THE CHARTER, AND WHY A GUARD
// crux-shared hosts *suite-wide EDA infrastructure* — code more than one
// product actually uses (CLAUDE.md "Scope rules"). The test is consumption, not
// vocabulary. But two specific pieces of single-product domain vocabulary have
// a live history of drifting in:
//
//  - `crux_yosys` legitimately names the HDL languages
//    (Verilog / SystemVerilog / VHDL) because Yosys elaboration is shared
//    tooling two products invoke (NetCrux and LintCrux) — the charter was
//    amended from "domain-neutral" to "suite-wide EDA" precisely to bless it.
//    That makes `crux_yosys` the ONE sanctioned home for HDL-language
//    vocabulary, and nowhere else.
//  - WaveCrux's waveform-canvas tokens (`signal.x.fill`,
//    `cursor.delta`, `marker.line`, …) were pulled back OUT of `crux_theme`'s
//    shared presets, where they had forced every other product to carry a
//    palette it can never use. The token *namespaces* must not creep back.
//
// This guard fails the build if either boundary is crossed: HDL-language
// vocabulary outside `crux_yosys`, or a waveform-canvas token namespace
// anywhere in shared `lib/`.
//
// WHAT IS DELIBERATELY NOT BANNED
//  - Bare `signal` / `marker` / `net` / `rule` / `test` as CXP element kinds.
//    `crux_cxp`'s `ElementKind` is the shared cross-*product* identity protocol
//    — naming an element every product can reference is its whole job, and
//    the per-product kinds are open by design. So the ban targets the
//    waveform-canvas token *namespaces* (`signal.x`, `cursor.delta`, …), not
//    the bare identity words.
//  - Comments. The charter is about what the CODE models and ships (a token
//    value, an enum, an emitted script), not about prose. crux-shared's doc
//    comments legitimately DESCRIBE the boundary — `crux_theme` names the
//    waveform tokens to say they must NOT be baked in — so scanning comments
//    would force allowlisting half the repo, defeating "only crux_yosys". The
//    scanner strips comments and reads code (identifiers + string literals).
//
// The package allowlist has exactly one entry: `crux_yosys`. Anything else
// this guard flags is a real charter violation to fix or escalate — do not add
// a second entry to make it pass. `_fileAllowlist` is the one narrow escape
// hatch, and it is for a file that quotes an external text verbatim, never for
// code we wrote and could have named differently.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Packages allowed to carry otherwise-banned EDA vocabulary in their code,
/// each with the reason that sanctions it. Exactly one entry, by design.
const Map<String, String> _allowlist = <String, String>{
  'crux_yosys':
      'Yosys elaboration is shared EDA tooling two products invoke '
      '(NetCrux, LintCrux), so its YosysSourceLanguage enum and emitted '
      'read scripts legitimately name Verilog / SystemVerilog / VHDL. The '
      'charter is amended to "suite-wide EDA infrastructure" for exactly '
      'this case.',
};

/// Individual files allowed to carry the vocabulary, each with its reason.
///
/// Separate from [_allowlist] and deliberately narrower: an entry here exempts
/// one file, so the rest of its package stays guarded. The package allowlist
/// above is for a package whose *domain* is the sanctioned one; this is for a
/// file whose *content is not ours to edit*.
///
/// The bar is the same — a real charter violation is still a violation. What
/// qualifies here is a file that quotes an external text verbatim, where
/// obeying the charter would mean altering that text rather than fixing our
/// design.
const Map<String, String> _fileAllowlist = <String, String>{
  'packages/crux_eula/lib/src/eula_document.dart':
      'The executed End User License Agreement, generated verbatim from the '
      'text counsel finalised. It names the four products and what each one '
      'is ("WaveCrux (waveform viewer), NetCrux (RTL schematic browser)") '
      'because a licence has to identify what it licenses. The charter is '
      'about what shared code MODELS; this file models nothing and its '
      'wording is not ours to edit to suit a lint. Editing it to pass this '
      'guard would put the agreement the apps present out of step with the '
      'one that binds, which is the single failure crux_eula exists to '
      'prevent.',
};

/// HDL-language vocabulary. Sanctioned only inside `crux_yosys`; a
/// hard-boundary word match, so it flags the `YosysSourceLanguage`-style enum
/// value or a `read_verilog` string, not a substring of an unrelated word.
final _hdlLanguageRe = RegExp(
  r'\b(?:verilog|systemverilog|vhdl)\b',
  caseSensitive: false,
);

/// Single-product canvas / domain nouns that name a specific product's model
/// rather than shared infrastructure.
final _domainNounRe = RegExp(
  r'\b(?:waveform|netlist|schematic|testbench)\b',
  caseSensitive: false,
);

/// Waveform-canvas token namespaces. This is the exact shape that was removed
/// from `crux_theme` — a dotted token path such as `signal.x.fill`,
/// `cursor.delta`, `marker.line`. Bare `signal` / `cursor` / `marker` are NOT
/// matched (they are shared identity / UI vocabulary); the dotted namespace is
/// unambiguously a waveform canvas token.
final _canvasTokenRe = RegExp(
  r'\b(?:signal\.(?:x|z|scalar)|cursor\.(?:primary|delta)|'
  r'marker\.(?:line|flag))',
  caseSensitive: false,
);

/// A finding: the offending token, its repo-relative file and line.
class _Hit {
  const _Hit(this.token, this.path, this.line);
  final String token;
  final String path;
  final int line;

  @override
  String toString() => '$path:$line — "$token"';
}

/// The crux-shared workspace root, found by walking up from the test's working
/// directory until the root `pubspec.yaml` naming the melos workspace is found.
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

/// Every non-generated Dart file under `packages/*/lib`, paired with the
/// package name it belongs to.
List<({String package, File file})> _libFiles(String root) {
  final out = <({String package, File file})>[];
  final packages = Directory(p.join(root, 'packages'));
  for (final entry in packages.listSync()) {
    if (entry is! Directory) continue;
    final package = p.basename(entry.path);
    final lib = Directory(p.join(entry.path, 'lib'));
    if (!lib.existsSync()) continue;
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart')) {
        continue;
      }
      out.add((package: package, file: f));
    }
  }
  out.sort((a, b) => a.file.path.compareTo(b.file.path));
  return out;
}

/// Returns [source] with every comment blanked to spaces (newlines kept, so
/// line numbers are preserved), leaving code — identifiers and string literals
/// — intact. String literals are NOT blanked: a banned token baked into a
/// string value (a theme token key, an emitted script command) is exactly what
/// the charter is about.
String _stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final nl = source.indexOf('\n', i);
      final end = nl == -1 ? source.length : nl;
      out.write(' ' * (end - i));
      i = end;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final close = source.indexOf('*/', i + 2);
      final end = close == -1 ? source.length : close + 2;
      for (var j = i; j < end; j++) {
        out.write(source[j] == '\n' ? '\n' : ' ');
      }
      i = end;
      continue;
    }
    if (c == "'" || c == '"') {
      final before = i;
      i = _skipString(source, i);
      out.write(source.substring(before, i));
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
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
    if (!triple && source[i] == '\n') return i;
    i++;
  }
  return source.length;
}

List<_Hit> _scan(String root, RegExp pattern, {required Set<String> exempt}) {
  final hits = <_Hit>[];
  for (final entry in _libFiles(root)) {
    if (exempt.contains(entry.package)) continue;
    final relative = p.relative(entry.file.path, from: root);
    if (_fileAllowlist.containsKey(p.url.joinAll(p.split(relative)))) continue;
    final code = _stripComments(entry.file.readAsStringSync());
    var line = 1;
    var offset = 0;
    for (final match in pattern.allMatches(code)) {
      while (offset < match.start) {
        if (code[offset] == '\n') line++;
        offset++;
      }
      hits.add(_Hit(match.group(0)!, relative, line));
    }
  }
  return hits;
}

void main() {
  final root = _workspaceRoot();

  test('the workspace layout resolved', () {
    expect(_libFiles(root).length, greaterThan(40));
  });

  test('HDL-language vocabulary appears only in crux_yosys', () {
    final hits = _scan(root, _hdlLanguageRe, exempt: _allowlist.keys.toSet());
    expect(
      hits.map((h) => h.toString()).toList()..sort(),
      isEmpty,
      reason:
          'HDL-language vocabulary (Verilog / SystemVerilog / VHDL) appears in '
          'a shared package other than crux_yosys. crux-shared '
          'hosts HDL elaboration only through crux_yosys; a shared package '
          'naming a specific HDL is modelling one product domain. Move it into '
          'the product, or route it through crux_yosys.\n${hits.join('\n')}',
    );
  });

  test('no single-product canvas/domain nouns in shared code', () {
    final hits = _scan(root, _domainNounRe, exempt: _allowlist.keys.toSet());
    expect(
      hits.map((h) => h.toString()).toList()..sort(),
      isEmpty,
      reason:
          'A shared package names a single-product domain noun (waveform / '
          'netlist / schematic / testbench) in its code. That vocabulary '
          'belongs to a product repo. If the concept is genuinely shared, '
          'naming it is the CXP identity protocol job (crux_cxp) — as an '
          'element kind, not as a product model.\n${hits.join('\n')}',
    );
  });

  test('no waveform-canvas token namespaces creep back into shared code', () {
    // crux_yosys is exempt from the language ban but has no reason to hold a
    // canvas token, so this class scans it too — the allowlist is language-
    // only in intent.
    final hits = _scan(root, _canvasTokenRe, exempt: const <String>{});
    expect(
      hits.map((h) => h.toString()).toList()..sort(),
      isEmpty,
      reason:
          'A waveform-canvas token namespace (signal.x / signal.z / '
          'signal.scalar / cursor.primary / cursor.delta / marker.line / '
          'marker.flag) has reappeared in shared code. It was removed exactly '
          'this from crux_theme so the other three products stop carrying a '
          'palette they cannot use. Contribute it as a product-owned '
          'ThemeTokenCategory instead.\n${hits.join('\n')}',
    );
  });

  test('the allowlist holds exactly the one sanctioned charter entry', () {
    expect(
      _allowlist.keys.toList(),
      <String>['crux_yosys'],
      reason:
          'The charter allowlist must contain exactly crux_yosys and '
          'nothing else. A second entry means a real charter violation was '
          'allowlisted instead of fixed.',
    );
    // The sanctioned package must still exist, or the entry is dead.
    expect(
      Directory(p.join(root, 'packages', 'crux_yosys')).existsSync(),
      isTrue,
    );
  });
}
