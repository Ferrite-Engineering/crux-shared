// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// One Dart source the text-scanning guards (G3, G4, G5) look at.
///
/// Carries its text rather than only its path so a guard can be driven from a
/// string literal as easily as from disk. That is not a convenience: it is
/// what makes a guard's own correctness testable. A scanner that can only read
/// the repo can only ever be asserted to find nothing, and "finds nothing"
/// looks the same whether the tree is clean or the regex rotted. Every guard
/// in this package is proved against hand-written violating sources built with
/// [CruxSourceFile.inline] before it is trusted against a real `lib/`.
@immutable
final class CruxSourceFile {
  /// Creates a [CruxSourceFile] from text already in hand.
  const CruxSourceFile({required this.path, required this.source});

  /// Reads [file], reporting it as [relativeTo]-relative if given.
  factory CruxSourceFile.read(File file, {String? relativeTo}) {
    return CruxSourceFile(
      path: relativeTo == null
          ? file.path
          : p.relative(file.path, from: relativeTo),
      source: file.readAsStringSync(),
    );
  }

  /// A synthetic source, for proving a scanner flags what it claims to.
  factory CruxSourceFile.inline(String name, String source) =>
      CruxSourceFile(path: name, source: source);

  /// How this file is named in a failure message. Repo-relative wherever
  /// possible — an absolute path from a CI runner is not something a reader
  /// can paste anywhere useful.
  final String path;

  /// The file's full text.
  final String source;

  /// The 1-based line number containing [offset].
  int lineAt(int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;

  /// `path:line` for [offset] — the form an editor and a terminal both
  /// understand.
  String locate(int offset) => '$path:${lineAt(offset)}';

  @override
  String toString() => path;
}

/// Every `.dart` file under [root], excluding generated and build output.
///
/// Paths are reported relative to [relativeTo], defaulting to [root]'s parent
/// so a report reads `lib/services/...` rather than an absolute path.
List<CruxSourceFile> cruxDartSourcesIn(
  Directory root, {
  String? relativeTo,
  Iterable<String> excludeSegments = const <String>[
    '.dart_tool',
    'build',
    'generated',
  ],
}) {
  if (!root.existsSync()) return const <CruxSourceFile>[];
  final base = relativeTo ?? p.dirname(root.path);
  final excluded = excludeSegments.toSet();
  final out = <CruxSourceFile>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart')) continue;
    final segments = p.split(p.relative(entity.path, from: base));
    if (segments.any(excluded.contains)) continue;
    out.add(CruxSourceFile.read(entity, relativeTo: base));
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// The source text of the balanced `(` … `)` argument list that starts at the
/// `(` at or after [open], or `null` if the parentheses do not balance.
///
/// String literals and line comments are skipped so a `)` inside `'…)'` does
/// not close the list early. Deliberately not a Dart parser: these guards run
/// in every product's test suite on every push, and a full analyzer pass over
/// a Pro `lib/` is a different order of cost. The scanners are text scanners
/// that are *proved* against fixtures rather than trusted for their
/// sophistication.
String? cruxBalancedParens(String source, int open) {
  final start = source.indexOf('(', open);
  if (start < 0) return null;
  var depth = 0;
  var i = start;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"') {
      i = _skipStringLiteral(source, i);
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final nl = source.indexOf('\n', i);
      i = nl < 0 ? source.length : nl;
      continue;
    }
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
    i++;
  }
  return null;
}

/// Returns the index just past the string literal starting at [start].
int _skipStringLiteral(String source, int start) {
  final quote = source[start];
  final isTriple =
      source.startsWith(quote * 3, start) && start + 3 <= source.length;
  final terminator = isTriple ? quote * 3 : quote;
  var i = start + terminator.length;
  while (i < source.length) {
    if (source[i] == r'\') {
      i += 2;
      continue;
    }
    if (source.startsWith(terminator, i)) return i + terminator.length;
    i++;
  }
  return source.length;
}
