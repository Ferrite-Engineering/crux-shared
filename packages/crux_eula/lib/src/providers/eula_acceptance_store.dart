// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show Completer, unawaited;

import 'package:crux_eula/src/eula_document.dart';
import 'package:crux_eula/src/providers/eula_seam_providers.dart';
import 'package:crux_eula/src/storage/eula_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persisted record of **which version** of the agreement the user accepted.
///
/// **A version string, never a boolean.** EULA section 2.3 says a change to the
/// agreement applies to releases installed after it takes effect, and that the
/// application presents the updated agreement for acceptance. A boolean cannot
/// express "accepted, but an older one", so a boolean store would silently
/// carry a 1.0 acceptance forward over a 2.0 agreement the user has never seen.
/// Storing the version makes the comparison in
/// [cruxEulaAcceptanceRequiredProvider] a string equality, and makes raising
/// [kCruxEulaVersion] the whole mechanism for re-prompting.
///
/// [build] returns `null` — "nothing accepted" — **synchronously** and starts
/// the load. For the first few frames of a cold start an installation that
/// accepted long ago is indistinguishable from a fresh one, so every consumer
/// that must not act on that ambiguity waits on [loaded] rather than reading
/// the state. The gate does exactly that; mounting the dialog on the early
/// value would flash a licence agreement at a user who accepted it a year ago.
class CruxEulaAcceptanceStore extends Notifier<String?> {
  /// The storage key holding the accepted version.
  ///
  /// Re-exported so a call site holding the store does not also have to import
  /// the storage library for the one constant.
  static const String storageKey = kCruxEulaAcceptedVersionKey;

  final Completer<void> _loaded = Completer<void>();

  /// Completes once the persisted value has been read back — whatever the
  /// outcome, including "nothing was stored" and "the read threw".
  ///
  /// Signalled in a `finally` on purpose: a gate that waited forever on an
  /// unreadable store would render its child with no agreement ever presented,
  /// which is the one outcome section 2.1 forbids. An unreadable store must
  /// resolve to "ask", not to "never ask".
  Future<void> get loaded => _loaded.future;

  @override
  String? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    try {
      final storage = ref.read(cruxEulaStorageProvider);
      final stored = await storage.read(storageKey);
      // A container teardown mid-read still disposes the store; never touch
      // `state` across the gap without this.
      if (!ref.mounted) return;
      if (stored != null && stored.isNotEmpty) state = stored;
    } on Object catch (_) {
      // A storage layer that throws is a storage layer we do not have. The
      // state stays null, which presents the agreement — the safe direction.
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  /// Records acceptance of [version] and persists it.
  ///
  /// The in-memory state is set before the first async gap so a caller that
  /// immediately re-reads the provider sees the new value, and the persist is
  /// deliberately **not** guarded by `ref.mounted`: once the user has accepted,
  /// losing that because the container happened to tear down would present the
  /// agreement again on the next launch, having already been told it was
  /// accepted.
  Future<void> accept([String version = kCruxEulaVersion]) async {
    final storage = ref.read(cruxEulaStorageProvider);
    if (ref.mounted) state = version;
    await storage.write(storageKey, version);
  }
}

/// The persisted accepted-version record. `null` means nothing accepted yet.
///
/// Hand-written rather than generated: no package in `crux-shared` runs
/// `build_runner`.
final NotifierProvider<CruxEulaAcceptanceStore, String?>
cruxEulaAcceptanceStoreProvider =
    NotifierProvider<CruxEulaAcceptanceStore, String?>(
      CruxEulaAcceptanceStore.new,
      name: 'cruxEulaAcceptanceStoreProvider',
    );

/// Whether the agreement must be presented before the application proceeds.
///
/// `true` until the store has loaded *and* the loaded value equals
/// [kCruxEulaVersion]. Both halves matter: the load gate stops the dialog
/// flashing over a returning user, and the equality — rather than a null check
/// — is what makes a raised version re-prompt an installation that accepted an
/// earlier one.
final Provider<bool> cruxEulaAcceptanceRequiredProvider = Provider<bool>((ref) {
  final accepted = ref.watch(cruxEulaAcceptanceStoreProvider);
  return accepted != kCruxEulaVersion;
}, name: 'cruxEulaAcceptanceRequiredProvider');
