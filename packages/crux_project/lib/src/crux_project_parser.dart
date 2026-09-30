// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_project/src/crux_project_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The manifest file extension, without the leading dot.
///
/// A manifest is named `<design>.crux-project` — any non-empty stem, this
/// extension — so `uart_tx.crux-project`. This is the value a file picker's
/// extension filter and a macOS document type take. Matching is ASCII
/// case-insensitive; see [CruxProjectParser.isManifestPath].
const String kCruxProjectExtension = 'crux-project';

/// The legacy manifest file name: a bare dotfile with no stem.
@Deprecated(
  'Manifests are named <design>.crux-project. Recognise one with '
  'CruxProjectParser.isManifestPath and filter file pickers with '
  'kCruxProjectExtension. Removed in crux_project 0.2.0, together with '
  'reading the legacy name.',
)
const String kCruxProjectFileName = _legacyFileName;

/// The schema version this build authors and fully understands.
const int kCruxProjectSchemaVersion = 1;

const String _legacyFileName = '.$kCruxProjectExtension';

/// Reads `<design>.crux-project` manifests.
///
/// The parser is **tolerant by design and strict in exactly one place**. A
/// missing or non-integer `version` is fatal, because that check is the only
/// thing standing between "this is a manifest" and "this is some YAML file
/// that happened to be selected". Everything else — a future schema version, a
/// malformed entry, the legacy file name — becomes a warning and the rest of
/// the file is kept, because a manifest is a pointer file and a partially
/// understood one is still useful. Artifact kinds are opaque strings, so there
/// is no such thing as an unrecognized one; see [CruxProjectManifest].
///
/// ## The file name
///
/// A manifest is `<design>.crux-project`: a user-named file carrying the
/// suite's extension, visible in every file picker and in Finder. The legacy
/// bare `.crux-project` is still read, with a deprecation warning, because
/// native pickers hide dotfiles and a user cannot select what they cannot see
/// — it is recognised by [isManifestPath], flagged by [isLegacyManifestPath],
/// and dropped in a later release.
///
/// A design directory holds exactly one manifest. [findIn] and [locate]
/// refuse to guess between several — the legacy file beside a named one
/// included — and throw [CruxProjectAmbiguousException] naming them.
class CruxProjectParser {
  /// Creates a parser.
  const CruxProjectParser();

  /// Parses [yamlText] as the manifest at [manifestPath].
  ///
  /// [manifestPath] is used for the manifest's directory (the design identity),
  /// for error messages, and to recognise the legacy file name; the file is
  /// not read.
  CruxProjectManifest parse(String yamlText, {required String manifestPath}) {
    final Object? doc;
    try {
      doc = loadYaml(yamlText);
    } on YamlException catch (e) {
      throw CruxProjectFormatException(
        'not valid YAML: ${e.message}',
        path: manifestPath,
      );
    }

    if (doc is! Map) {
      throw CruxProjectFormatException(
        'expected a mapping at the top level',
        path: manifestPath,
      );
    }

    final rawVersion = doc['version'];
    if (rawVersion is! int) {
      throw CruxProjectFormatException(
        rawVersion == null
            ? 'missing the required "version" key'
            : '"version" must be an integer, got ${rawVersion.runtimeType}',
        path: manifestPath,
      );
    }

    final warnings = <String>[];
    if (isLegacyManifestPath(manifestPath)) {
      warnings.add(_legacyFileNameWarning(manifestPath));
    }
    if (rawVersion > kCruxProjectSchemaVersion) {
      warnings.add(
        'manifest declares version $rawVersion; this build understands '
        '$kCruxProjectSchemaVersion. Reading what it can — fields introduced '
        'later are ignored.',
      );
    }
    if (rawVersion < 1) {
      throw CruxProjectFormatException(
        '"version" must be 1 or greater, got $rawVersion',
        path: manifestPath,
      );
    }

    final directory = _canonicalDirectoryOf(manifestPath);

    final name = _optionalString(doc['name'], 'name', warnings);

    String? top;
    final sources = <String>[];
    final design = doc['design'];
    if (design is Map) {
      top = _optionalString(design['top'], 'design.top', warnings);
      final rawSources = design['sources'];
      if (rawSources is List) {
        for (var i = 0; i < rawSources.length; i++) {
          final entry = rawSources[i];
          if (entry is String && entry.trim().isNotEmpty) {
            sources.add(entry.trim());
          } else {
            warnings.add('design.sources[$i] is not a path — skipped');
          }
        }
      } else if (rawSources != null) {
        warnings.add('design.sources must be a list — ignored');
      }
    } else if (design != null) {
      warnings.add('design must be a mapping — ignored');
    }

    final artifacts = <String, String>{};
    final rawArtifacts = doc['artifacts'];
    if (rawArtifacts is Map) {
      for (final entry in rawArtifacts.entries) {
        final key = entry.key;
        if (key is! String) {
          warnings.add('artifacts key ${entry.key} is not a string — skipped');
          continue;
        }
        final value = entry.value;
        if (value is String && value.trim().isNotEmpty) {
          // Forward tolerance: kinds are opaque, so a key a later suite version
          // introduces is kept verbatim rather than rejected or dropped.
          artifacts[key] = value.trim();
        } else {
          warnings.add('artifacts.$key is not a path — skipped');
        }
      }
    } else if (rawArtifacts != null) {
      warnings.add('artifacts must be a mapping — ignored');
    }

    return CruxProjectManifest(
      version: rawVersion,
      directory: directory,
      name: name,
      top: top,
      rawSources: List.unmodifiable(sources),
      rawArtifacts: Map.unmodifiable(artifacts),
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Reads and parses the manifest file at [manifestPath].
  ///
  /// Throws [CruxProjectFormatException] when the file cannot be read or is not
  /// a manifest.
  CruxProjectManifest parseFile(String manifestPath) {
    final file = File(manifestPath);
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (e) {
      throw CruxProjectFormatException(
        'cannot read the file: ${e.message}',
        path: manifestPath,
      );
    }
    return parse(text, manifestPath: manifestPath);
  }

  /// True when [path] names a manifest **by filename**: `<stem>.crux-project`
  /// with a non-empty stem, or the legacy bare `.crux-project`.
  ///
  /// The extension is compared ASCII case-insensitively, as file pickers and
  /// Finder compare it. `notes.crux-project.txt` is not a manifest; its
  /// extension is `txt`.
  ///
  /// Deliberately does not read the file: this is the cheap predicate a
  /// file-open dispatcher uses to decide which branch to take, and the parse
  /// that follows is what decides whether the contents are valid.
  static bool isManifestPath(String path) =>
      p.basename(path).toLowerCase().endsWith(_legacyFileName);

  /// True when [path] names a manifest by the legacy bare `.crux-project`
  /// file name.
  ///
  /// Such a manifest still opens. [parse] records a deprecation warning as its
  /// first warning — naming the file to rename it to — so a product that
  /// already shows warnings needs nothing more; a product that localizes its
  /// messages tests this instead and shows its own text.
  static bool isLegacyManifestPath(String path) =>
      p.basename(path).toLowerCase() == _legacyFileName;

  /// The deprecation diagnostic for a manifest at the legacy [manifestPath]:
  /// what is wrong and what to rename the file to.
  static String _legacyFileNameWarning(String manifestPath) {
    final stem = p.basename(_canonicalDirectoryOf(manifestPath));
    final suggested =
        '${stem.isEmpty ? 'design' : stem}.$kCruxProjectExtension';
    return 'the manifest file name "$_legacyFileName" is deprecated: file '
        'pickers hide it. Rename it to "$suggested"; a later release stops '
        'reading the bare name.';
  }

  /// The single manifest inside [directory], or null when there is none or
  /// the directory cannot be listed.
  ///
  /// Only regular files (or links to them) directly inside [directory] count;
  /// the search does not recurse. Throws [CruxProjectAmbiguousException] when
  /// more than one matches [isManifestPath] — the legacy `.crux-project` beside
  /// a named manifest counts as two — because choosing one silently would open
  /// a design from a file the user may not know is stale.
  static String? findIn(String directory) {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(directory).listSync(followLinks: false);
    } on FileSystemException {
      return null;
    }
    final found = <String>[
      for (final entry in entries)
        if (isManifestPath(entry.path) &&
            FileSystemEntity.isFileSync(entry.path))
          entry.path,
    ]..sort();
    if (found.length > 1) {
      throw CruxProjectAmbiguousException(
        directory: directory,
        candidates: List<String>.unmodifiable(found),
      );
    }
    return found.isEmpty ? null : found.single;
  }

  /// The manifest [path] designates, or null when it designates none.
  ///
  /// A directory resolves through [findIn], including its refusal of several
  /// manifests. Any other path is returned unchanged when [isManifestPath]
  /// accepts its name; whether it exists and parses is [parseFile]'s question.
  ///
  /// Both routes lead to the same design: the design identity is the
  /// manifest's directory, so opening `uart_tx/` and opening
  /// `uart_tx/uart_tx.crux-project` yield the same CXP `design_id`.
  static String? locate(String path) {
    if (FileSystemEntity.isDirectorySync(path)) return findIn(path);
    return isManifestPath(path) ? path : null;
  }

  static String? _optionalString(
    Object? value,
    String label,
    List<String> warnings,
  ) {
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    warnings.add('$label must be a non-empty string — ignored');
    return null;
  }

  /// The canonical directory containing [manifestPath].
  ///
  /// Canonicalized against the filesystem when it exists so that two paths
  /// reaching the same folder by different routes (a symlink, a `..`) produce
  /// the same design identity — the same rule `cxpDesignIdForPath` applies,
  /// and it has to match or the two would key the same design differently.
  static String _canonicalDirectoryOf(String manifestPath) {
    final dir = p.dirname(p.normalize(p.absolute(manifestPath)));
    try {
      if (Directory(dir).existsSync()) {
        return Directory(dir).resolveSymbolicLinksSync();
      }
    } on FileSystemException {
      // Fall through to the lexical answer — a manifest for a design that does
      // not exist on this machine still parses.
    }
    return p.canonicalize(dir);
  }
}
