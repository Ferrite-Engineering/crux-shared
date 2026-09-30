// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// What a store is permitted to do to its own file when the bytes on disk
/// turn out not to be a readable SQLite database.
///
/// **This is the data-value policy, expressed as a type rather than as a
/// convention**, because the convention is what failed. The rule used to live
/// in a docstring: it was stale in one file and factually wrong in another,
/// and the wrong one destroyed a Pro user's entire violation history. A
/// reviewer
/// reading an open call now sees the store's answer to "can this file be
/// rebuilt from anything else on disk?" at the call site, in the argument
/// list, where a stale comment cannot contradict it.
///
/// It applies to **genuine corruption only**. A migration failure and a
/// version skew never reach a recovery path at all, whatever value is chosen
/// here — see the vocabulary in `crux_sqlite_exceptions.dart`.
enum CruxDbRecovery {
  /// **PRECIOUS.** The contents cannot be reconstructed from anything else on
  /// disk, and a diagnostics seam exists to tell the user what happened.
  ///
  /// The damaged file is renamed to `<db>.corrupt-<ISO 8601 basic UTC>`, its
  /// `-wal` / `-shm` / `-journal` sidecars move with it, a fresh database
  /// opens in its place, and the recovery listener is told. **Nothing is ever
  /// deleted.** The app cannot distinguish "this file is garbage" from "this
  /// file is fine and I have a bug", so the worst permitted action is the
  /// reversible one: the user keeps the bytes and support can ask for them.
  ///
  /// Requires a recovery listener. A silent quarantine is its own defect — a
  /// chart that is empty because the file was moved aside looks exactly like a
  /// chart that is empty because nothing has run yet.
  renameAside,

  /// **PRECIOUS, with nowhere to say so.** Refuse to open; touch nothing.
  ///
  /// For a store whose contents are unreconstructible and whose product has no
  /// seam to surface a notice through. A silent quarantine there is worse than
  /// a refusal, because a refusal destroys nothing and a user who is told
  /// "this file could not be opened" still has every byte. The typed
  /// `CruxDatabaseCorruptionException` propagates to the caller with
  /// `quarantinedPath: null`.
  ///
  /// This is the honest holding position, not a permanent one: a store moves
  /// to [renameAside] the moment its product grows somewhere to put the
  /// notice, and that is a one-line change.
  refuse,

  /// **DERIVABLE.** A fresh run regenerates the contents, so wipe-and-recreate
  /// is a legitimate recovery.
  ///
  /// The file is deleted and a fresh database is created in its place.
  /// Legitimate for exactly one kind of store: a cache. Choosing this for a
  /// file whose contents are not reproducible is the F1 defect, restated as an
  /// argument instead of as a docstring — which is the point, because an
  /// argument is reviewable and greppable and a docstring is neither.
  ///
  /// Also requires a recovery listener. A cache that silently rebuilds itself
  /// on every launch is a bug nobody ever sees.
  recreate;

  /// Whether this store's contents cannot be reconstructed from anything else
  /// on disk.
  ///
  /// **This is what switches the pre-upgrade backup on**, and it is derived
  /// here rather than declared a second time on purpose: a store opts into
  /// being backed up by *being precious*, not by remembering to ask. A backup
  /// you have to remember is a backup somebody will forget, and the store that
  /// forgets is the one whose data nobody can get back.
  ///
  /// True for [renameAside] and [refuse] — both mean "unreconstructible", and
  /// they differ only in whether the product has somewhere to put a notice.
  /// False for [recreate] alone: a fresh run regenerates a cache, so
  /// snapshotting one before a migration spends a user's disk on bytes we
  /// could rebuild for free.
  bool get isPrecious => this != CruxDbRecovery.recreate;
}
