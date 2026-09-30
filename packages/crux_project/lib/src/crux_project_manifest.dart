// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A parsed `<design>.crux-project` manifest.
///
/// Every path exposed here is **resolved against the manifest's own
/// directory**, never the process working directory — see [resolve]. The raw
/// relative strings are kept in [rawArtifacts] and [rawSources] for round-trip
/// and diagnostics.
///
/// Absence is not failure anywhere in this type. A manifest naming a dump that
/// has not been generated yet is a normal, useful manifest; the missing file
/// surfaces when something tries to open it, not at parse time.
///
/// ## Artifact kinds are opaque strings
///
/// An artifact kind is the manifest key verbatim — this package never
/// enumerates them. That is deliberate, and it is the same choice
/// `crux_cxp`'s `WorkspaceArtifact.kind` makes: naming the kinds here would
/// put one product's domain vocabulary into shared code, which the
/// domain-neutrality charter forbids (see `charter_vocabulary_test.dart`).
/// Each product owns the constant for the kind it consumes; the manifest
/// format's key set is normative in the suite design manifest specification,
/// not in Dart.
///
/// A consequence worth stating plainly: a key this build has never heard of is
/// not an error and not discarded. It lands in [rawArtifacts] like any other,
/// so a manifest written for a later suite version opens here unchanged and a
/// product can still enumerate what it does not consume.
@immutable
class CruxProjectManifest {
  /// Creates a manifest. Prefer `CruxProjectParser.parse`.
  const CruxProjectManifest({
    required this.version,
    required this.directory,
    this.name,
    this.top,
    this.rawSources = const <String>[],
    this.rawArtifacts = const <String, String>{},
    this.warnings = const <String>[],
  });

  /// The schema version declared by the file.
  final int version;

  /// Absolute, canonical path of the directory containing the manifest.
  ///
  /// This is the design's identity: the CXP `design_id` is derived from it, so
  /// a manifest-opened design and a directly-opened one share a design id and
  /// cross-probe between them joins with no extra wiring.
  final String directory;

  /// Human label. Falls back to the directory's basename when the file omits
  /// it, so this is never null after parsing.
  final String? name;

  /// Declared top module, when the sources have more than one candidate.
  final String? top;

  /// Source paths exactly as written in the file.
  final List<String> rawSources;

  /// Artifact paths exactly as written in the file, keyed by the manifest key
  /// verbatim.
  ///
  /// Every key the file carried is here, including ones this build does not
  /// consume — see the class doc on opaque kinds.
  final Map<String, String> rawArtifacts;

  /// Non-fatal problems found while parsing — a future schema version, a
  /// malformed entry that was skipped.
  final List<String> warnings;

  /// The label to show a user: [name] when set, else the directory basename.
  String get displayName => name ?? p.basename(directory);

  /// Resolves [relativeOrAbsolute] against [directory].
  ///
  /// Absolute paths pass through verbatim — accepted, though a manifest
  /// carrying one is not portable between machines. `~` is deliberately **not**
  /// expanded: a path is a path.
  String resolve(String relativeOrAbsolute) => p.isAbsolute(relativeOrAbsolute)
      ? p.normalize(relativeOrAbsolute)
      : p.normalize(p.join(directory, relativeOrAbsolute));

  /// Source paths resolved against [directory], in declaration order.
  List<String> get sources => [for (final s in rawSources) resolve(s)];

  /// The resolved path for the artifact key [kind], or null when the manifest
  /// does not name it.
  String? artifact(String kind) {
    final raw = rawArtifacts[kind];
    return raw == null ? null : resolve(raw);
  }

  /// Whether this manifest names anything at all beyond its version.
  ///
  /// A version-only manifest is valid (a design that has not produced anything
  /// yet still deserves one) but there is nothing for a product to open, so
  /// callers use this to choose a clearer message.
  bool get isEmpty => rawSources.isEmpty && rawArtifacts.isEmpty;

  @override
  String toString() =>
      'CruxProjectManifest($displayName, v$version, '
      '${rawSources.length} sources, ${rawArtifacts.length} artifacts)';
}

/// Thrown when a file cannot be read as a `<design>.crux-project` manifest.
///
/// Only two things raise it: unreadable/unparseable YAML, and a missing or
/// non-integer `version`. Everything else in the format degrades to a warning,
/// because the strictness exists for exactly one purpose — so a YAML file that
/// happens to be lying around cannot be mistaken for a manifest.
class CruxProjectFormatException implements Exception {
  /// Creates the exception.
  const CruxProjectFormatException(this.message, {this.path});

  /// What went wrong, phrased for a user.
  final String message;

  /// The offending file, when known.
  final String? path;

  @override
  String toString() => path == null
      ? 'CruxProjectFormatException: $message'
      : 'CruxProjectFormatException: $message ($path)';
}

/// Thrown when a directory holds more than one manifest, so the design it
/// describes is ambiguous.
///
/// A design directory holds exactly one manifest. Two named manifests, or a
/// named one beside the legacy bare `.crux-project`, are refused rather than
/// ranked: whichever one lost would describe the design differently, and a
/// user would be opening a design from a file they may not know is stale.
/// [message] names every candidate so the user can remove or merge the extras.
class CruxProjectAmbiguousException implements Exception {
  /// Creates the exception.
  const CruxProjectAmbiguousException({
    required this.directory,
    required this.candidates,
  });

  /// The directory that was searched.
  final String directory;

  /// Every manifest found, as full paths, sorted.
  final List<String> candidates;

  /// What went wrong, phrased for a user.
  String get message =>
      '$directory holds ${candidates.length} design manifests '
      '(${candidates.map(p.basename).join(', ')}); a design directory holds '
      'exactly one. Remove or merge the extras.';

  @override
  String toString() => 'CruxProjectAmbiguousException: $message';
}
