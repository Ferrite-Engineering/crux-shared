// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_workspace/src/workspace.dart';
import 'package:crux_workspace/src/workspace_codec.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// A corruption-recovery record produced by [WorkspaceService.load] when it
/// quarantines an unreadable auto-managed `workspace.json`. The host product
/// reads it (via [WorkspaceService.takeRecovery]) to surface a localized
/// "your workspace could not be restored" notice on launch.
class WorkspaceRecovery {
  /// Creates a recovery record.
  const WorkspaceRecovery({
    required this.quarantinePath,
    required this.reason,
  });

  /// Absolute path the corrupt document was moved to
  /// (`workspace.json.corrupt-<timestamp>`), or — if the move itself failed —
  /// the original path.
  final String quarantinePath;

  /// Diagnostic explaining why the document was unreadable (bad JSON,
  /// non-object root, unsupported schema version, invariant violation).
  final String reason;
}

/// Thrown by [WorkspaceService.loadFromPath] when a named workspace document
/// cannot be read.
///
/// A named document is loaded at the user's explicit request, so a failure
/// must surface to the caller rather than silently yield an empty workspace —
/// substituting `Workspace.empty()` would let the host replace (and then
/// auto-save over) a perfectly good live session. Callers catch this to keep
/// the current workspace and present the failure.
///
/// Unlike the auto-managed document [WorkspaceService.load] owns, a named
/// document lives in a location the user chose, so it is never moved aside on
/// failure — the caller keeps its live session untouched and reports the error.
class WorkspaceLoadException implements Exception {
  /// Creates a load-failure record for the document at [path].
  const WorkspaceLoadException({required this.path, required this.reason});

  /// Absolute path of the document that failed to load.
  final String path;

  /// Diagnostic explaining why the document was unreadable (missing file,
  /// bad JSON, non-object root, unsupported schema version, invariant
  /// violation, I/O error).
  final String reason;

  @override
  String toString() => 'WorkspaceLoadException($path): $reason';
}

/// Owns the on-disk workspace document at
/// `{storageDirectory}/workspace.json`.
///
/// Writes are **atomic** — `workspace.json.tmp` is written first, then
/// renamed over `workspace.json`. A crash mid-write therefore leaves the
/// previous good document intact rather than a half-written file.
///
/// Failure handling:
/// * Missing file → returns `Workspace.empty()`.
/// * Corrupt JSON / non-object root / schema violation / invariant violation
///   → the document is **quarantined** (moved to
///   `workspace.json.corrupt-<timestamp>`) so it cannot brick the next launch
///   nor be silently overwritten, a [WorkspaceRecovery] is recorded for the
///   host to surface, and `Workspace.empty()` is returned. The quarantine
///   preserves the original bytes for manual recovery.
/// * A transient read error (an [Exception] that is *not* a decode failure)
///   returns `Workspace.empty()` but does **not** quarantine — the file may
///   be perfectly good and merely momentarily unreadable.
/// * I/O errors on save are swallowed but logged — a failed save is
///   non-fatal in the same sense as a debounced auto-save dropping a frame.
///
/// Pass `directoryFactory` to override the storage directory in tests; pass
/// `logger` to capture diagnostic output instead of writing to stderr.
/// Pass `fileName` to override the auto-managed document file name (default
/// `workspace.json`); the temp sibling derives by appending `.tmp`.
class WorkspaceService<P> {
  /// Creates a workspace service for payload type `P` using `codec` for
  /// per-tab payload serialization.
  WorkspaceService({
    required WorkspaceCodec<P> codec,
    Future<Directory> Function()? directoryFactory,
    void Function(String message)? logger,
    String fileName = 'workspace.json',
  }) : this._(
         codec,
         directoryFactory,
         logger,
         fileName,
         '$fileName.tmp',
       );

  WorkspaceService._(
    this.codec,
    this._directoryFactory,
    this._logger,
    this._fileName,
    this._tempFileName,
  );

  /// Codec used to serialize and deserialize each tab's payload.
  final WorkspaceCodec<P> codec;

  final Future<Directory> Function()? _directoryFactory;
  final void Function(String message)? _logger;
  final String _fileName;

  /// Legacy fixed temp name (`<fileName>.tmp`). No longer written — [save]
  /// uses a unique name per write — but still swept by [clear] so a temp file
  /// left behind by an older build does not linger.
  final String _tempFileName;

  /// Suffix every temp sibling ends with; [clear] uses it to sweep them.
  static const String _tempSuffix = '.tmp';

  /// Tail of the serialized save chain — see [save].
  Future<void> _saveChain = Future<void>.value();

  WorkspaceRecovery? _lastRecovery;

  /// Public file name for the auto-managed workspace document.
  String get fileName => _fileName;

  /// Returns and clears the most recent corruption-recovery record, if the
  /// last [load] quarantined an unreadable document. Consume-once: a second
  /// call returns `null`. The host product calls this after the first
  /// workspace read to decide whether to show a recovery notice.
  WorkspaceRecovery? takeRecovery() {
    final recovery = _lastRecovery;
    _lastRecovery = null;
    return recovery;
  }

  /// Loads the workspace from the storage directory.
  ///
  /// Returns `Workspace.empty()` for any failure mode — missing file, I/O
  /// error, invalid JSON, or schema violation — so callers never need to
  /// handle an error state. Corrupt files are logged but **not** deleted.
  Future<Workspace<P>> load() async {
    final file = await _workspaceFile();
    if (file == null || !file.existsSync()) return Workspace<P>.empty();
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        _quarantine(file, '$_fileName root is not a JSON object');
        return Workspace<P>.empty();
      }
      return Workspace<P>.fromJson(decoded, codec);
    } on WorkspaceSchemaVersionException catch (e) {
      _quarantine(file, 'unsupported schema version: $e');
      return Workspace<P>.empty();
    } on WorkspaceInvariantException catch (e) {
      _quarantine(file, 'workspace invariant violation: $e');
      return Workspace<P>.empty();
    } on FormatException catch (e) {
      _quarantine(file, '$_fileName is not valid JSON: $e');
      return Workspace<P>.empty();
    } on Exception catch (e) {
      // A transient read error (not a decode failure): do NOT quarantine —
      // the document may be intact and merely momentarily unreadable.
      _log('WorkspaceService: load failed: $e');
      return Workspace<P>.empty();
      // Deliberate: a decode Error must be quarantined, not propagated, or it
      // bricks every subsequent launch. See the comment inside the branch.
      // ignore: avoid_catching_errors
    } on Error catch (e) {
      // Decoding attacker-or-corruption-shaped bytes can raise an *Error*,
      // not an Exception — a `TypeError` from a bad cast (`"version": "2"`
      // where an int is expected), an ArgumentError or StateError out of a
      // product's payload codec. `Error` does not match `on Exception`, so
      // without this branch such a document escapes quarantine and throws on
      // every single launch: the exact permanent-brick failure quarantine
      // exists to prevent. Treat any Error out of decoding as "this document
      // is unreadable" — the bytes are preserved by the quarantine move, so
      // nothing is destroyed if the real cause turns out to be a codec bug.
      _quarantine(file, '$_fileName could not be decoded: $e');
      return Workspace<P>.empty();
    }
  }

  /// Moves a corrupt [file] aside to `<path>.corrupt-<timestamp>` and records
  /// a [WorkspaceRecovery] for the host to surface. Best-effort: if the move
  /// fails the recovery is still recorded so the user is told what happened.
  void _quarantine(File file, String reason) {
    _log('WorkspaceService: $reason — quarantining ${file.path}');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final quarantinePath = '${file.path}.corrupt-$stamp';
    try {
      file.renameSync(quarantinePath);
      _lastRecovery = WorkspaceRecovery(
        quarantinePath: quarantinePath,
        reason: reason,
      );
    } on FileSystemException catch (e) {
      _log('WorkspaceService: quarantine move failed: $e');
      _lastRecovery = WorkspaceRecovery(
        quarantinePath: file.path,
        reason: reason,
      );
    }
  }

  /// Atomically writes [workspace] to the storage directory.
  ///
  /// The serialized JSON is written to a temp sibling file first, then
  /// renamed over the destination. A crash before the rename leaves the
  /// previous document unmodified.
  ///
  /// Silently swallows I/O errors after logging — a failed save is
  /// non-fatal.
  Future<void> save(Workspace<P> workspace) {
    // Serialize writes. Two overlapping saves would each write a temp sibling
    // and rename it over the destination; with a shared temp path the second
    // writer can consume the first's file, so one save is silently lost (the
    // resulting ENOENT is swallowed below) or a partially-written document is
    // published. Chaining makes concurrent callers — a debounced auto-save
    // and a quit-time flush, say — strictly ordered instead of racing.
    final next = _saveChain
        .then((_) => _saveNow(workspace))
        .catchError((Object _) {});
    _saveChain = next;
    return next;
  }

  Future<void> _saveNow(Workspace<P> workspace) async {
    final dir = await _resolveDirectory();
    if (dir == null) return;
    try {
      // `crux_io` owns parent-dir creation, the unique scratch name (belt and
      // braces alongside the chain above, since a second process over the same
      // directory is outside this instance's serialization), the fsync before
      // the rename, and cleanup of the scratch file on failure.
      //
      // The workspace document is the user's open-tab layout: durable, not
      // ephemeral. The one-second autosave debounce means the fsync cost is at
      // most one small file per second while tabs are being rearranged.
      await writeJsonAtomic(
        File('${dir.path}/$_fileName'),
        workspace.toJson(codec),
      );
    } on Exception catch (e) {
      _log('WorkspaceService: save failed: $e');
    }
  }

  /// Atomically writes [workspace] to an arbitrary [path].
  ///
  /// Used by the "Save Workspace As…" flow to export a named workspace
  /// document outside the auto-managed app support directory. Writes via a
  /// scratch sibling and then a `rename`, matching [save]'s atomic-write
  /// contract.
  ///
  /// Rethrows I/O errors so the caller can present a save-failure dialog;
  /// callers that want best-effort semantics can wrap the call.
  Future<void> saveToPath(String path, Workspace<P> workspace) =>
      writeJsonAtomic(File(path), workspace.toJson(codec));

  /// Loads a named workspace document from [path].
  ///
  /// Unlike [load] — which substitutes `Workspace.empty()` because an
  /// unreadable auto-managed document must never brick launch — a named
  /// document is loaded at the user's explicit request, so failure is
  /// surfaced as a [WorkspaceLoadException] instead of an empty workspace.
  /// Substituting empty here would let the caller replace a good live
  /// session (and then auto-save empty over the managed file).
  ///
  /// The document lives where the user put it, so failure never moves it
  /// aside: every branch throws and leaves the file untouched. This mirrors
  /// [load]'s catch taxonomy (schema, invariant, format, transient I/O, and a
  /// decode `Error` from a bad cast) — the only difference is the outcome
  /// (throw vs. degrade-to-empty), never a rename.
  Future<Workspace<P>> loadFromPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw WorkspaceLoadException(path: path, reason: 'file does not exist');
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw WorkspaceLoadException(
          path: path,
          reason: 'root is not a JSON object',
        );
      }
      return Workspace<P>.fromJson(decoded, codec);
    } on WorkspaceLoadException {
      rethrow;
    } on WorkspaceSchemaVersionException catch (e) {
      throw WorkspaceLoadException(
        path: path,
        reason: 'unsupported schema version: $e',
      );
    } on WorkspaceInvariantException catch (e) {
      throw WorkspaceLoadException(
        path: path,
        reason: 'workspace invariant violation: $e',
      );
    } on FormatException catch (e) {
      throw WorkspaceLoadException(path: path, reason: 'not valid JSON: $e');
    } on Exception catch (e) {
      throw WorkspaceLoadException(path: path, reason: 'read failed: $e');
      // Same rationale as [load]'s Error branch: a bad cast while decoding an
      // untrusted document is an Error, and letting it escape would turn
      // "the user picked a malformed file" into a crash.
      // ignore: avoid_catching_errors
    } on Error catch (e) {
      throw WorkspaceLoadException(
        path: path,
        reason: 'could not be decoded: $e',
      );
    }
  }

  /// Deletes the workspace document and any stale temp sibling — both the
  /// legacy fixed `<fileName>.tmp` and the unique-per-write siblings [save]
  /// produces, which a crash between write and rename can leave behind.
  Future<void> clear() async {
    final dir = await _resolveDirectory();
    if (dir == null) return;
    final dest = File('${dir.path}/$_fileName');
    final temp = File('${dir.path}/$_tempFileName');
    final strays = <File>[];
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('$_fileName.') && name.endsWith(_tempSuffix)) {
          strays.add(entity);
        }
      }
    } on Exception catch (e) {
      _log('WorkspaceService: temp sweep failed: $e');
    }
    for (final f in [dest, temp, ...strays]) {
      try {
        if (f.existsSync()) await f.delete();
      } on Exception catch (e) {
        _log('WorkspaceService: clear failed for ${f.path}: $e');
      }
    }
  }

  /// Returns the absolute path of the per-tab session sidecar file for
  /// [tabId]. The path is deterministic — `{storageDirectory}/sessions/
  /// {tabId}.json` — so save and restore can find each tab's session
  /// without storing the path in the workspace document.
  ///
  /// Returns null when the storage directory cannot be resolved (web,
  /// platform-channel-less unit tests). Callers must handle null by
  /// degrading to "no sidecar".
  ///
  /// Pass [extension] to override the sidecar extension (default `.json`);
  /// products typically supply their own extension (e.g. `.wavecrux`).
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.json',
  }) async {
    final dir = await _resolveDirectory();
    if (dir == null) return null;
    final sessionsDir = Directory('${dir.path}/sessions');
    if (!sessionsDir.existsSync()) {
      try {
        sessionsDir.createSync(recursive: true);
      } on Exception catch (e) {
        _log('WorkspaceService: failed to create sessions dir: $e');
        return null;
      }
    }
    return '${sessionsDir.path}/$tabId$extension';
  }

  /// Deletes **every** per-tab session sidecar by removing the entire
  /// `{storageDirectory}/sessions/` directory.
  ///
  /// Companion to [clear]: where [clear] removes the auto-managed
  /// `workspace.json`, this removes the per-tab sidecars that the workspace
  /// document points at. Together they reset on-disk persistence to a truly
  /// empty state. Used by hermetic test boots so a fresh launch can never
  /// hydrate a stale tab *or* re-attach a stale tab's persisted session
  /// (decoders, signal groups). Without this, [clear] alone only *orphans*
  /// the sidecars — they linger on disk and re-surface if any future code
  /// path (or a tab-id collision) reaches them, which is exactly the
  /// "N× transaction rows" over-decode integration-test flake.
  ///
  /// Best-effort: a missing directory or an I/O failure is swallowed after
  /// logging, matching [clear]'s non-fatal contract. No-op when the storage
  /// directory cannot be resolved (web, platform-channel-less unit tests).
  Future<void> clearAllSidecars() async {
    final dir = await _resolveDirectory();
    if (dir == null) return;
    final sessionsDir = Directory('${dir.path}/sessions');
    try {
      if (sessionsDir.existsSync()) {
        await sessionsDir.delete(recursive: true);
      }
    } on Exception catch (e) {
      _log('WorkspaceService: clearAllSidecars failed: $e');
    }
  }

  /// Deletes the per-tab session sidecar for [tabId]. Best-effort —
  /// missing-file / I/O failures are swallowed (the caller is closing a tab
  /// and does not care if the sidecar was already gone).
  Future<void> deleteSidecar(
    String tabId, {
    String extension = '.json',
  }) async {
    final path = await sidecarPathFor(tabId, extension: extension);
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      await file.delete();
    } on Exception catch (e) {
      _log('WorkspaceService: sidecar delete failed ($tabId): $e');
    }
  }

  Future<File?> _workspaceFile() async {
    final dir = await _resolveDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$_fileName');
  }

  Future<Directory?> _resolveDirectory() async {
    final factory = _directoryFactory;
    // Flutter Web has no application-support directory: path_provider's
    // method channel throws `MissingPluginException` there. Short-circuit to
    // null so on-disk persistence degrades to a documented no-op (every
    // caller already handles a null directory) instead of relying on the
    // catch below — which previously turned into an unhandled error when the
    // diagnostic fallback itself threw (see _log). A test-injected factory is
    // still honored so a web widget test can supply a fake directory.
    if (factory == null && kIsWeb) return null;
    try {
      return factory != null
          ? await factory()
          : await getApplicationSupportDirectory();
    } on Exception catch (e) {
      _log('WorkspaceService: directory resolution failed: $e');
      return null;
    }
  }

  void _log(String message) {
    final l = _logger;
    if (l != null) {
      l(message);
      return;
    }
    // Best-effort diagnostic. `stderr` is unavailable on some platforms —
    // Flutter Web's dart:io stub throws `UnsupportedError`
    // (`StdIOUtils._getStdioOutputStream`) the moment `stderr` is accessed.
    // A logging failure must never escape: every caller relies on _log being
    // side-effect-only so the surrounding `on Exception` recovery stays
    // intact. Swallow whatever stderr throws.
    try {
      stderr.writeln(message);
    } on Object {
      // No usable stderr (web) — drop the diagnostic rather than escalate.
    }
  }
}
