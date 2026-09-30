// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/src/cxp_manifest_directory.dart';
import 'package:crux_cxp/src/cxp_path_containment.dart';
import 'package:crux_io/crux_io.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Resolves the suite-shared CXP **workspace** directory for this user.
///
/// Sibling of the peers directory ([sharedCxpManifestDirectory]): where
/// `peers/` holds live-presence manifests, `workspace/` holds the
/// design→artifact link store that lets a receiver open the right file when
/// it has none matching open. Layout:
/// `<user-app-data>/crux/cxp/workspace/<design_id>.json`.
///
/// [environment] and [operatingSystem] are injectable for tests and forwarded
/// verbatim to [sharedCxpManifestDirectory], so the two directories always
/// resolve under the same per-user root.
String sharedCxpWorkspaceDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) => p.join(
  p.dirname(
    sharedCxpManifestDirectory(
      environment: environment,
      operatingSystem: operatingSystem,
    ),
  ),
  'workspace',
);

/// One produced file belonging to a shared design, as recorded in the
/// workspace manifest.
///
/// [kind] and `design_id` are opaque strings supplied by the producer — the
/// library never computes them. The descriptive [topModule] / [basename]
/// fields are optional resolver hints: [CxpWorkspaceStore.resolveArtifact]
/// prefers an exact `design_id`+`kind` match and falls back to matching these.
@immutable
class WorkspaceArtifact {
  /// Creates a workspace artifact record.
  const WorkspaceArtifact({
    required this.kind,
    required this.path,
    required this.producer,
    required this.ts,
    this.topModule,
    this.basename,
  });

  /// Decodes a [WorkspaceArtifact] from its JSON form.
  factory WorkspaceArtifact.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    final path = json['path'];
    final producer = json['producer'];
    if (kind is! String) {
      throw const FormatException('WorkspaceArtifact: missing "kind"');
    }
    if (path is! String) {
      throw const FormatException('WorkspaceArtifact: missing "path"');
    }
    if (producer is! String) {
      throw const FormatException('WorkspaceArtifact: missing "producer"');
    }
    final ts = json['ts'];
    final topModule = json['top_module'];
    final basename = json['basename'];
    return WorkspaceArtifact(
      kind: kind,
      path: path,
      producer: producer,
      ts: ts is int ? ts : 0,
      topModule: topModule is String ? topModule : null,
      basename: basename is String ? basename : null,
    );
  }

  /// Opaque artifact kind — e.g. `waveform`, `netlist`, `source`.
  final String kind;

  /// Absolute path to the produced file.
  final String path;

  /// Short name of the producing product — e.g. `simcrux`, `netcrux`.
  final String producer;

  /// Milliseconds-since-epoch the entry was last upserted. Refreshed on every
  /// upsert; drives TTL-based stale pruning.
  final int ts;

  /// Optional top-module name, a descriptive resolver hint.
  final String? topModule;

  /// Optional file leaf name. When absent, resolvers fall back to the leaf of
  /// [path].
  final String? basename;

  /// The effective leaf used for descriptive matching: [basename] if set,
  /// else the leaf of [path].
  String get effectiveBasename => basename ?? p.basename(path);

  /// JSON form suitable for writing to disk.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'path': path,
    'producer': producer,
    'ts': ts,
    'top_module': ?topModule,
    'basename': ?basename,
  };

  /// Copy with a refreshed [ts] (and optionally refreshed descriptive fields).
  WorkspaceArtifact _refreshed({
    required int ts,
    required String producer,
    String? topModule,
    String? basename,
  }) => WorkspaceArtifact(
    kind: kind,
    path: path,
    producer: producer,
    ts: ts,
    topModule: topModule ?? this.topModule,
    basename: basename ?? this.basename,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceArtifact &&
          other.kind == kind &&
          other.path == path &&
          other.producer == producer &&
          other.ts == ts &&
          other.topModule == topModule &&
          other.basename == basename);

  @override
  int get hashCode =>
      Object.hash(kind, path, producer, ts, topModule, basename);

  @override
  String toString() =>
      'WorkspaceArtifact($kind $path by $producer'
      '${topModule == null ? '' : ', top=$topModule'})';
}

/// File-based store linking a shared **design** to the concrete artifacts
/// produced for it, so a peer that receives a cross-probe it cannot satisfy
/// locally can open the right file (CXP §9.10,
/// <https://edacrux.app/cxp#sec-9-10>).
///
/// One JSON document per design lives at `<workspaceDirectory>/<design_id>.json`
/// (shape: `{"design_id": "...", "artifacts": [ ... ]}`). Producers
/// [upsertArtifact] on open/produce; consumers [resolveArtifact] when an
/// incoming highlight/selection misses. Writes use the same crash-safe atomic
/// rename the peer manifests use.
///
/// Stale pruning mirrors peer discovery's: an artifact whose file
/// [WorkspaceArtifact.path] no longer exists, or whose [WorkspaceArtifact.ts]
/// is older than [ttl], is dropped on the next read and the pruned document is
/// rewritten (or deleted when it empties). `design_id` is opaque and
/// producer-supplied throughout.
///
/// ### Concurrent writers
///
/// [upsertArtifact] and [pruneDesign] each read a design's document, change
/// it and write it back. Within one isolate they are queued per document,
/// across every store instance, so each one reads what the one before it
/// wrote: any number of concurrent upserts for one design all survive.
///
/// Across processes nothing is queued. The atomic rename guarantees that a
/// reader sees a whole document — the old one or the new one, never a torn
/// one — and that a crash leaves one of the two. It does not make a
/// read-change-write atomic: when two processes upsert the same design at
/// the same moment, each writes the document it read plus its own entry, and
/// the rename that lands second drops the first one's entry. The window is
/// the few milliseconds between one process's read and its rename; the lost
/// entry comes back with that producer's next upsert of it.
class CxpWorkspaceStore {
  /// Creates a store rooted at [workspaceDirectory] (defaults to
  /// [sharedCxpWorkspaceDirectory]). [ttl] bounds how long an entry survives
  /// without a refreshing upsert.
  ///
  /// [containment], when given, is applied to what [readArtifacts] and
  /// [resolveArtifact] return — the spec's rule that a resolved artifact
  /// gets the same scrutiny as a `file_path` on the wire (§9.10, §11). Pass
  /// the same instance the product's `LocalCxpServer` holds. It never
  /// filters what is *persisted*: a producer records the paths it produced,
  /// and which of them a given consumer may open is that consumer's rule.
  CxpWorkspaceStore({
    String? workspaceDirectory,
    this.ttl = _defaultTtl,
    this.containment,
  }) : workspaceDirectory = workspaceDirectory ?? sharedCxpWorkspaceDirectory();

  static const Duration _defaultTtl = Duration(days: 30);

  /// Directory holding `<design_id>.json` documents.
  final String workspaceDirectory;

  /// An entry older than this (by [WorkspaceArtifact.ts]) is stale-pruned on
  /// read. File-existence pruning applies regardless of [ttl].
  final Duration ttl;

  /// The rule an artifact's path must pass to be returned by
  /// [readArtifacts] and [resolveArtifact]. Null applies none.
  final CxpPathContainment? containment;

  /// Idempotently records (or refreshes) the artifact of [kind] at [path] for
  /// [designId].
  ///
  /// The entry is keyed by (`path`, `kind`): a repeat call with the same pair
  /// updates the existing record's [WorkspaceArtifact.ts] (and any changed
  /// descriptive fields) rather than appending a duplicate. Returns the full
  /// current artifact list for the design after the upsert.
  ///
  /// A [designId] that does not stay inside [workspaceDirectory] (see
  /// [isValidDesignId]) records nothing and returns the empty list. Every id
  /// the suite mints comes from `cxpDesignIdForPath`, which cannot produce
  /// one; the guard is for ids that arrived over the wire.
  ///
  /// Concurrent calls for one design, from any store in this isolate, run
  /// one after another; see the class documentation for writers in other
  /// processes.
  Future<List<WorkspaceArtifact>> upsertArtifact({
    required String designId,
    required String kind,
    required String path,
    required String producer,
    String? topModule,
    String? basename,
    int? ts,
  }) async {
    final file = _fileFor(designId);
    if (file == null) return const <WorkspaceArtifact>[];
    final now = ts ?? DateTime.now().millisecondsSinceEpoch;
    return _queuedFor(file, () async {
      // Prune stale entries as we write, so ordinary producer activity
      // bounds the document without relying on a read-time rewrite, as
      // discovery does.
      final current = _prune(_readRaw(designId));
      final next = <WorkspaceArtifact>[];
      var replaced = false;
      for (final a in current) {
        if (a.path == path && a.kind == kind) {
          next.add(
            a._refreshed(
              ts: now,
              producer: producer,
              topModule: topModule,
              basename: basename,
            ),
          );
          replaced = true;
        } else {
          next.add(a);
        }
      }
      if (!replaced) {
        next.add(
          WorkspaceArtifact(
            kind: kind,
            path: path,
            producer: producer,
            ts: now,
            topModule: topModule,
            basename: basename,
          ),
        );
      }
      await _write(designId, next);
      return List<WorkspaceArtifact>.unmodifiable(next);
    });
  }

  /// Returns the (stale-pruned) artifacts recorded for [designId] that pass
  /// [containment], when one is set.
  ///
  /// Pruning is applied to the returned view only — this method performs no
  /// disk I/O, so it is safe to call synchronously from a resolver on a hot
  /// path. Persisting the pruned document is the job of [upsertArtifact] (on
  /// the next produce) and the explicit [pruneDesign]. An unknown design
  /// yields an empty list.
  List<WorkspaceArtifact> readArtifacts(String designId) =>
      List.unmodifiable(_admitted(_prune(_readRaw(designId))));

  /// The artifacts of [artifacts] whose path [containment] allows — all of
  /// them when no rule is set.
  List<WorkspaceArtifact> _admitted(List<WorkspaceArtifact> artifacts) {
    final rule = containment;
    if (rule == null) return artifacts;
    return <WorkspaceArtifact>[
      for (final a in artifacts)
        if (rule.allows(a.path)) a,
    ];
  }

  /// Persists the stale-pruned artifact set for [designId], deleting the
  /// design document entirely when nothing survives. Returns the surviving
  /// artifacts. A no-op (beyond the read) when nothing was stale.
  ///
  /// Queued with [upsertArtifact] for the same design, so a prune cannot
  /// write back a document read before an upsert landed.
  Future<List<WorkspaceArtifact>> pruneDesign(String designId) async {
    final file = _fileFor(designId);
    if (file == null) return const <WorkspaceArtifact>[];
    return _queuedFor(file, () async {
      final raw = _readRaw(designId);
      final pruned = _prune(raw);
      if (pruned.length != raw.length) await _write(designId, pruned);
      return List<WorkspaceArtifact>.unmodifiable(pruned);
    });
  }

  /// Resolves the artifact of [kind] for [designId], preferring an exact
  /// `design_id`+`kind` match and falling back to the descriptive
  /// [topModule] / [basename] hints.
  ///
  /// Resolution among the design's non-stale artifacts of [kind]:
  /// 1. a [topModule] match, when [topModule] is given;
  /// 2. else a [basename]/leaf match, when [basename] is given;
  /// 3. else the single artifact of that kind, if unambiguous;
  /// 4. else the most recently upserted one.
  ///
  /// Returns null when the design has no artifact of [kind].
  WorkspaceArtifact? resolveArtifact(
    String designId,
    String kind, {
    String? topModule,
    String? basename,
  }) {
    final ofKind = readArtifacts(
      designId,
    ).where((a) => a.kind == kind).toList(growable: false);
    if (ofKind.isEmpty) return null;
    if (ofKind.length == 1) return ofKind.first;

    if (topModule != null) {
      for (final a in ofKind) {
        if (a.topModule == topModule) return a;
      }
    }
    if (basename != null) {
      final leaf = p.basename(basename);
      for (final a in ofKind) {
        if (a.effectiveBasename == leaf || a.effectiveBasename == basename) {
          return a;
        }
      }
    }
    // Unambiguous fallback: newest ts.
    ofKind.sort((a, b) => b.ts.compareTo(a.ts));
    return ofKind.first;
  }

  List<WorkspaceArtifact> _prune(List<WorkspaceArtifact> artifacts) {
    final cutoff = DateTime.now().millisecondsSinceEpoch - ttl.inMilliseconds;
    return <WorkspaceArtifact>[
      for (final a in artifacts)
        if (a.ts >= cutoff && File(a.path).existsSync()) a,
    ];
  }

  /// Whether [designId] names a record file inside [workspaceDirectory].
  ///
  /// A `design_id` is opaque on the wire (CXP §9.10.1) and arrives from a
  /// peer on every `request_open_artifact`, so the one thing this store
  /// does with it — turn it into a file name — has to be safe for any
  /// string. `p.join(workspaceDirectory, '$designId.json')` is not: a
  /// `..` segment walks out of the directory, and an absolute `designId`
  /// makes `p.join` discard the directory altogether (measured:
  /// `/tmp/evil` became `/tmp/evil.json`). An id that does not stay inside
  /// the directory is treated as a design with no records, which is the
  /// only truthful answer — no record can exist for it.
  ///
  /// This is a containment check, not a parse: an id with a separator in it
  /// (`designs/cdc_capture`) still keys a file one level down, as it always
  /// has.
  bool isValidDesignId(String designId) {
    if (designId.isEmpty || designId.contains('\x00')) return false;
    final file = p.normalize(p.join(workspaceDirectory, '$designId.json'));
    return p.isWithin(workspaceDirectory, file);
  }

  /// The record file for [designId], or null when the id does not stay
  /// inside [workspaceDirectory] — see [isValidDesignId].
  File? _fileFor(String designId) => isValidDesignId(designId)
      ? File(p.join(workspaceDirectory, '$designId.json'))
      : null;

  List<WorkspaceArtifact> _readRaw(String designId) {
    final file = _fileFor(designId);
    if (file == null || !file.existsSync()) return const <WorkspaceArtifact>[];
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const <WorkspaceArtifact>[];
      final rawArtifacts = decoded['artifacts'];
      if (rawArtifacts is! List) return const <WorkspaceArtifact>[];
      final result = <WorkspaceArtifact>[];
      for (final entry in rawArtifacts) {
        if (entry is Map<String, Object?>) {
          result.add(WorkspaceArtifact.fromJson(entry));
        } else if (entry is Map) {
          result.add(WorkspaceArtifact.fromJson(entry.cast<String, Object?>()));
        }
      }
      return result;
    } on FormatException {
      return const <WorkspaceArtifact>[];
    } on FileSystemException {
      return const <WorkspaceArtifact>[];
    }
  }

  Future<void> _write(
    String designId,
    List<WorkspaceArtifact> artifacts,
  ) async {
    final file = _fileFor(designId);
    // An id that cannot name a file inside the workspace has nothing to
    // write to; [upsertArtifact] and [pruneDesign] return the (empty) list
    // they computed, and nothing lands outside the directory.
    if (file == null) return;
    if (artifacts.isEmpty) {
      // An empty design document is noise; remove it rather than persist [].
      try {
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        // Best effort.
      }
      return;
    }
    await writeJsonAtomic(file, <String, Object?>{
      'design_id': designId,
      'artifacts': artifacts.map((a) => a.toJson()).toList(growable: false),
    });
  }
}

/// The last read-change-write queued for each design document in this
/// isolate, keyed by the document's absolute path.
///
/// Held per isolate rather than per store because every product builds its
/// store in a provider that is rebuilt when the containment rule changes: a
/// queue per instance would let the new store's upsert read the document
/// while the old store's write of it was still in flight.
final Map<String, Future<void>> _documentQueues = <String, Future<void>>{};

/// Runs [body] once every read-change-write queued before it for [file] has
/// finished, successfully or not.
///
/// Without this, concurrent upserts for one design each read the document
/// before any of them had written it, and the last rename kept only its own
/// entry: a producer that publishes several artifacts at once — a waveform
/// per finished test — lost all but one.
Future<T> _queuedFor<T>(File file, Future<T> Function() body) {
  final key = p.normalize(p.absolute(file.path));
  final previous = _documentQueues[key] ?? Future<void>.value();
  final result = previous.then((_) => body());
  // The queue waits on each body but never inherits its failure; the caller
  // still gets it through [result].
  final settled = result.then<void>((_) {}, onError: (Object _) {});
  _documentQueues[key] = settled;
  unawaited(
    settled.whenComplete(() {
      // The last in the queue leaves it empty; one queued since keeps it.
      if (identical(_documentQueues[key], settled)) {
        _documentQueues.remove(key)?.ignore();
      }
    }),
  );
  return result;
}
