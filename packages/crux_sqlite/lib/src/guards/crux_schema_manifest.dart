// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_schema_snapshot.dart';
import 'package:meta/meta.dart';

/// The checked-in, append-only record of what each shipped schema version
/// looked like: one line per version, `v<N>  <sha256 hex>`.
///
/// A plain text file rather than a Dart constant, and one file per store, so
/// that the reviewable event is exactly the one that matters: **a legitimate
/// new version adds one line and changes none.** A diff that modifies an
/// existing line is a shipped migration having been edited, and it is visible
/// as such in a pull request before any test runs.
///
/// The file lives next to the thin per-repo guard test that consumes it —
/// `test/static/sqlite_schema_manifests/<store>.fingerprints`.
@immutable
final class CruxSchemaManifest {
  /// Creates a [CruxSchemaManifest].
  const CruxSchemaManifest({
    required this.storeName,
    required this.fingerprints,
    required this.source,
  });

  /// Parses [text], read from [source] (named in failure messages).
  ///
  /// Blank lines and `#` comments are ignored. Every other line must be
  /// `v<N>` and a 64-character lower-case hex digest, whitespace-separated.
  factory CruxSchemaManifest.parse(
    String text, {
    required String storeName,
    required String source,
  }) {
    final entries = <int, String>{};
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = _lineFormat.firstMatch(line);
      if (match == null) {
        throw FormatException(
          'unreadable schema manifest line in $source at line ${i + 1}: '
          '"$line". Expected `v<N>  <64 hex chars>`, e.g. '
          '`v1  ${'0' * 64}`.',
        );
      }
      final version = int.parse(match.group(1)!);
      if (entries.containsKey(version)) {
        throw FormatException(
          '$source declares v$version twice (line ${i + 1}). A schema version '
          'has exactly one shipped shape.',
        );
      }
      entries[version] = match.group(2)!;
    }
    return CruxSchemaManifest(
      storeName: storeName,
      fingerprints: Map<int, String>.unmodifiable(entries),
      source: source,
    );
  }

  /// Reads and parses the manifest at [path].
  ///
  /// A missing file is an [Exception] rather than an empty manifest: an absent
  /// manifest that silently passed would make guard G1 vacuous in exactly the
  /// repo that deleted it.
  factory CruxSchemaManifest.readFile(
    String path, {
    required String storeName,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        'no schema fingerprint manifest at $path for the $storeName. Guard G1 '
        'cannot tell an edited migration from an untouched one without it. '
        'Generate it with cruxRenderSchemaManifest() and commit it.',
      );
    }
    return CruxSchemaManifest.parse(
      file.readAsStringSync(),
      storeName: storeName,
      source: path,
    );
  }

  static final RegExp _lineFormat = RegExp(r'^v(\d+)\s+([0-9a-f]{64})$');

  /// The store this manifest belongs to, as the runner names it.
  final String storeName;

  /// Version → SHA-256 of that version's normalised schema.
  final Map<int, String> fingerprints;

  /// Where it was read from, for failure messages.
  final String source;

  /// The highest version recorded, or 0 for an empty manifest.
  int get latestVersion => fingerprints.keys.fold(0, (a, b) => a > b ? a : b);
}

/// Renders [snapshots] as manifest text.
///
/// Used to create a manifest for a store that has none yet, and — carefully —
/// to read off the single line a genuinely new version needs. It deliberately
/// does *not* exist as a `--write` mode on a guard: a guard that can rewrite
/// its own expectations is a guard with an off switch, and "just regenerate
/// the manifest" is precisely the move that turns an edited shipped migration
/// into a green build.
String cruxRenderSchemaManifest(
  List<CruxSchemaSnapshot> snapshots, {
  required String storeName,
}) {
  final buffer = StringBuffer()
    ..writeln('# Frozen schema fingerprints — $storeName')
    ..writeln('#')
    ..writeln('# APPEND ONLY. One line per shipped schema version:')
    ..writeln('#   v<N>  <sha256 of the normalised sqlite_master dump at vN>')
    ..writeln('#')
    ..writeln('# Adding schema version N+1 adds ONE line here and changes')
    ..writeln('# none. If a diff to this file MODIFIES an existing line, a')
    ..writeln('# migration that has already shipped was edited — which means')
    ..writeln('# fresh installs and upgraded installs now disagree about the')
    ..writeln('# schema, silently, forever. Revert that edit and express the')
    ..writeln('# change as a new migration instead.')
    ..writeln('#')
    ..writeln('# Guard G1 in crux_sqlite_guards.dart checks this file.')
    ..writeln('# The rule: $kCruxMigrationGuideRef, rule 1.')
    ..writeln('#');
  for (final snapshot in snapshots) {
    buffer.writeln('v${snapshot.version}  ${snapshot.fingerprint}');
  }
  return buffer.toString();
}
