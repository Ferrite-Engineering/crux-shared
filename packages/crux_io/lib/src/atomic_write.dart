// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Monotonic discriminator appended to every temp filename so two writers
/// racing over the same destination never share a scratch file.
int _tempCounter = 0;

/// Suffix given to the scratch file an atomic write renames from.
const String _tempSuffix = '.tmp';

/// The pretty-printer every Crux on-disk JSON document is written with.
///
/// Two-space indent, matching what the four persistence layers independently
/// converged on before they were unified here. Keeping it in one place means a
/// document written by one package and read by another never differs in
/// whitespace — which matters because several of these files are
/// user-inspectable and end up in diffs.
const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

/// Whether an atomic write waits for the bytes to reach stable storage before
/// publishing them with the rename.
///
/// ### Why this is an explicit parameter
///
/// `tmp.writeAsString(...)` followed by `tmp.rename(dest)` is only *nominally*
/// atomic. Without an `fsync`, the filesystem is free to order the rename's
/// metadata update ahead of the data blocks, so a crash in the window between
/// the two leaves the destination name pointing at a zero-length or
/// partially-written file. That is strictly worse than not having written at
/// all: the previous good document is already gone. `flush: true` closes the
/// window.
///
/// Before this helper existed the suite had five independent atomic writers
/// and only two of them flushed — not as a decision, but because nobody had
/// compared them. The choice is now made per call site, on the record:
///
/// - **[durable] is the default.** Every caller that persists something the
///   user cannot trivially reconstruct — the workspace document, a theme pack,
///   the project registry — takes it. The cost is one `fsync` on a file of a
///   few kilobytes, off the UI isolate, and the workspace's autosave is behind
///   a one-second debounce, so the worst case is one small `fsync` per second
///   while the user is actively rearranging tabs. That is not a budget worth
///   trading correctness for.
/// - **[ephemeral] is for state that is republished on a timer and whose loss
///   self-heals.** The CXP peer manifest is the only such caller today: it is
///   discovery state rewritten every 30-second heartbeat, it is never a source
///   of truth, and a manifest lost to a crash is regenerated within one
///   interval by a process that had to restart anyway. Paying for durability
///   here would buy nothing.
///
/// If a new call site wants [ephemeral], the bar is the CXP bar: the data must
/// be *reproducible without the user*, on a bounded schedule. "It would be a
/// bit faster" is not the bar.
enum WriteDurability {
  /// `fsync` the scratch file before the rename. The default.
  durable,

  /// Skip the `fsync`. Only for state a running process republishes on a
  /// bounded timer — see the enum-level rationale.
  ephemeral;

  /// Whether this level asks `dart:io` to flush.
  bool get flush => this == WriteDurability.durable;
}

/// Crash-safely replaces the contents of [file] with [contents].
///
/// The bytes go to a uniquely-named sibling scratch file, are optionally
/// flushed to stable storage (see [WriteDurability]), and are then `rename`d
/// over [file]. `rename` within a directory is atomic on every filesystem the
/// Crux products target, so a concurrent reader observes either the whole old
/// document or the whole new one — never a torn one.
///
/// The parent directory is created if it does not exist.
///
/// The scratch filename embeds a timestamp and a process-monotonic counter.
/// A fixed `<dest>.tmp` is not safe: two overlapping writes to the same
/// destination — an autosave racing a quit-time flush, or two service
/// instances pointed at the same directory — would each write *the same*
/// scratch path and the second rename would find the file already consumed,
/// silently losing one save or publishing a half-written document.
///
/// On failure the scratch file is removed on a best-effort basis (so a failed
/// write leaves no debris for a later directory scan to trip over) and the
/// original exception is rethrown. Callers that want best-effort save
/// semantics catch it themselves; the helper never swallows.
///
/// [onBeforeRename] is a test-only seam fired after the scratch file is
/// written but before the rename, so a test can throw at the single most
/// dangerous instant and assert the destination is untouched. Production
/// callers never pass it.
Future<void> writeStringAtomic(
  File file,
  String contents, {
  WriteDurability durability = WriteDurability.durable,
  @visibleForTesting FutureOr<void> Function()? onBeforeRename,
}) async {
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.${_nextTempDiscriminator()}$_tempSuffix');
  try {
    await temp.writeAsString(contents, flush: durability.flush);
    if (onBeforeRename != null) await onBeforeRename();
    await temp.rename(file.path);
  } on Object {
    await _deleteQuietly(temp);
    rethrow;
  }
}

/// Crash-safely replaces [file] with the pretty-printed JSON encoding of
/// [data], which must be JSON-encodable.
///
/// Thin wrapper over [writeStringAtomic] — see it for the atomicity and
/// durability contract.
///
/// Declared `async` on purpose: encoding happens before any I/O, so a
/// non-encodable [data] would otherwise throw *synchronously* out of a
/// `Future`-returning function and bypass the caller's `catchError` /
/// `await`-site handler.
Future<void> writeJsonAtomic(
  File file,
  Object? data, {
  WriteDurability durability = WriteDurability.durable,
  @visibleForTesting FutureOr<void> Function()? onBeforeRename,
}) async => writeStringAtomic(
  file,
  _jsonEncoder.convert(data),
  durability: durability,
  onBeforeRename: onBeforeRename,
);

String _nextTempDiscriminator() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_tempCounter++}';

Future<void> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) await file.delete();
  } on FileSystemException {
    // Best-effort: an orphaned scratch file is inert, and reporting a cleanup
    // failure would mask the write failure the caller actually needs to see.
  }
}
