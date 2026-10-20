// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where one Recent list is kept.
///
/// The suite unifies how a Recent list behaves, not where each product keeps
/// it: a product that stores its list under its own preference key uses
/// [CruxPrefsRecentStore]; one that keeps it inside a larger settings model
/// implements this over that model, so a saved list from an older release
/// is read as it is.
abstract interface class CruxRecentStore {
  /// The stored entries, most recent first. Never throws: an unreadable
  /// store reads as empty.
  Future<List<String>> load();

  /// Replaces the stored entries.
  Future<void> save(List<String> entries);
}

/// A [CruxRecentStore] holding the list as a string list under one
/// `SharedPreferences` key.
class CruxPrefsRecentStore implements CruxRecentStore {
  /// Creates a store under [prefsKey]. Tests pass [prefsOverride].
  const CruxPrefsRecentStore(this.prefsKey, {this.prefsOverride});

  /// The preference key, unchanged from the product's own so a saved list
  /// survives adoption.
  final String prefsKey;

  /// A preferences instance to use instead of the platform one, for tests.
  final SharedPreferences? prefsOverride;

  Future<SharedPreferences> _prefs() async =>
      prefsOverride ?? await SharedPreferences.getInstance();

  @override
  Future<List<String>> load() async {
    try {
      final prefs = await _prefs();
      return List<String>.unmodifiable(
        prefs.getStringList(prefsKey) ?? const <String>[],
      );
    } on Object {
      // No preferences backend, or a value of another type under the key:
      // an empty list is the only safe reading, and must not fail a launch.
      return const <String>[];
    }
  }

  @override
  Future<void> save(List<String> entries) async {
    final prefs = await _prefs();
    await prefs.setStringList(prefsKey, entries);
  }
}

/// Answers whether the file or directory behind a Recent entry is still on
/// disk.
typedef CruxRecentEntryExists = bool Function(String path);

/// The default [CruxRecentEntryExists]: a file or a directory at [path].
///
/// Synchronous on purpose: the list holds a handful of paths, and a row that
/// renders first and greys a frame later reads as a flicker. A check that
/// throws (a permission error on a parent) counts as present, so the row
/// stays as it was and opening it reports the real error. A browser has no
/// file system to ask, so on the web every entry is present.
bool cruxRecentEntryExists(String path) {
  if (kIsWeb) return true;
  try {
    return File(path).existsSync() || Directory(path).existsSync();
  } on Object {
    return true;
  }
}

/// One Recent list: its store, its entries and the check that greys a
/// missing entry.
///
/// A product declares one per list it shows (WaveCrux keeps two, files and
/// workspaces) as a top-level final, the same way it declares a provider:
///
/// ```dart
/// final recentFiles = CruxRecentList(
///   name: 'recentFiles',
///   store: (_) => const CruxPrefsRecentStore('recent_files'),
/// );
/// ```
///
/// Every list behaves the same way: [CruxRecentListNotifier.markOpened]
/// moves an entry to the front and caps the list at [capacity], a row can be
/// removed, the whole list can be cleared, and an open that fails drops the
/// entry. The stored list is read once, in the background; anything opened,
/// removed or cleared before it arrives is merged into it rather than
/// overwritten by it.
class CruxRecentList {
  /// Creates the list's providers.
  ///
  /// [accepts] screens entries before they are recorded (an internal file
  /// the user never opened returns false); entries it rejects are also
  /// dropped from the stored list when it is read. [onRemoved] runs for each
  /// entry removed or cleared, for a product that holds something per entry
  /// (a security-scoped bookmark).
  CruxRecentList({
    required this.name,
    required CruxRecentStore Function(Ref ref) store,
    this.capacity = 10,
    this.accepts,
    this.onRemoved,
  }) : assert(capacity > 0, 'capacity must be positive') {
    storeProvider = Provider<CruxRecentStore>(store, name: '${name}Store');
    provider = NotifierProvider<CruxRecentListNotifier, List<String>>(
      () => CruxRecentListNotifier._(this),
      name: name,
    );
    existsProvider = Provider<CruxRecentEntryExists>(
      (_) => cruxRecentEntryExists,
      name: '${name}Exists',
    );
  }

  /// A name for the providers, for diagnostics.
  final String name;

  /// The most entries the list keeps.
  final int capacity;

  /// Screens an entry before it is recorded; null accepts every entry.
  final bool Function(String path)? accepts;

  /// Runs for each entry removed or cleared.
  final FutureOr<void> Function(String path)? onRemoved;

  /// The store. Override it in tests.
  late final Provider<CruxRecentStore> storeProvider;

  /// The entries, most recent first. Starts empty and fills when the store
  /// has been read.
  late final NotifierProvider<CruxRecentListNotifier, List<String>> provider;

  /// The check that marks a missing entry. Override it in tests.
  late final Provider<CruxRecentEntryExists> existsProvider;
}

/// What happened when a Recent entry was opened through
/// [CruxRecentListNotifier.open].
enum CruxRecentOpenResult {
  /// The entry opened and moved to the front.
  opened,

  /// The entry did not open and was dropped from the list.
  removed,
}

/// The entries of one [CruxRecentList].
class CruxRecentListNotifier extends Notifier<List<String>> {
  CruxRecentListNotifier._(this._list);

  final CruxRecentList _list;

  bool _touched = false;
  bool _restored = false;
  bool _clearedBeforeRestore = false;
  final Set<String> _removed = <String>{};
  final Completer<void> _restoredCompleter = Completer<void>();

  /// Completes when the stored list has been read and merged.
  Future<void> get restored => _restoredCompleter.future;

  @override
  List<String> build() {
    unawaited(_restore());
    return const <String>[];
  }

  bool _accepts(String path) => _list.accepts?.call(path) ?? true;

  Future<void> _restore() async {
    var raw = const <String>[];
    try {
      raw = await ref.read(_list.storeProvider).load();
    } on Object {
      // A store that throws despite its contract reads as empty.
    }
    if (!ref.mounted) return;
    final stored = [
      for (final path in raw)
        if (_accepts(path)) path,
    ];
    _restored = true;
    if (!_touched) {
      state = List<String>.unmodifiable(stored.take(_list.capacity));
      // A rejected entry found in the stored list is cleaned out of it.
      if (stored.length != raw.length) unawaited(_persist(state));
    } else if (_clearedBeforeRestore) {
      // A clear is a decision about the stored history too: keep what was
      // opened since, and nothing older.
      _set(state);
    } else {
      _set(
        <String>[
          ...state,
          for (final path in stored)
            if (!state.contains(path) && !_removed.contains(path)) path,
        ].take(_list.capacity).toList(growable: false),
      );
    }
    if (!_restoredCompleter.isCompleted) _restoredCompleter.complete();
  }

  /// Records that [path] was opened: moves it to the front and saves.
  /// Ignored when the list's `accepts` rejects it.
  void markOpened(String path) {
    if (!_accepts(path)) return;
    _touched = true;
    _removed.remove(path);
    _set(
      <String>[
        path,
        for (final existing in state)
          if (existing != path) existing,
      ].take(_list.capacity).toList(growable: false),
    );
  }

  /// Removes [path]: the row's remove button, or an entry that no longer
  /// opens.
  void remove(String path) {
    if (_restored && !state.contains(path)) return;
    _touched = true;
    _removed.add(path);
    _set(<String>[
      for (final existing in state)
        if (existing != path) existing,
    ]);
    _notifyRemoved(<String>[path]);
  }

  /// Empties the list (the Clear Recent command). Entries opened afterwards
  /// are recorded as usual.
  void clear() {
    _touched = true;
    if (!_restored) _clearedBeforeRestore = true;
    final cleared = List<String>.of(state);
    _removed.addAll(cleared);
    _set(const <String>[]);
    _notifyRemoved(cleared);
  }

  /// Opens [path] through [open], which returns whether it opened. An entry
  /// that does not open (or whose open throws) is dropped, so the list stops
  /// offering it; one that opens moves to the front. The caller reports a
  /// failure, because only it knows why.
  Future<CruxRecentOpenResult> open(
    String path,
    Future<bool> Function(String path) open,
  ) async {
    var ok = false;
    try {
      ok = await open(path);
    } on Object {
      ok = false;
    }
    if (!ref.mounted) {
      return ok ? CruxRecentOpenResult.opened : CruxRecentOpenResult.removed;
    }
    if (ok) {
      markOpened(path);
      return CruxRecentOpenResult.opened;
    }
    remove(path);
    return CruxRecentOpenResult.removed;
  }

  void _notifyRemoved(List<String> paths) {
    final hook = _list.onRemoved;
    if (hook == null) return;
    for (final path in paths) {
      try {
        final result = hook(path);
        if (result is Future<void>) unawaited(result.catchError((Object _) {}));
      } on Object {
        // A per-entry hook failing must not stop the list changing.
      }
    }
  }

  void _set(List<String> next) {
    state = List<String>.unmodifiable(next);
    if (_restored) unawaited(_persist(state));
  }

  Future<void> _persist(List<String> entries) async {
    try {
      await ref.read(_list.storeProvider).save(entries);
    } on Object {
      // No preferences backend: the list still works for this session.
    }
  }
}
