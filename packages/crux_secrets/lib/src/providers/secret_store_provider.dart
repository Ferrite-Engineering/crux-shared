// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_secrets/src/secret_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active [CruxSecretStore].
///
/// **Default: [UnavailableCruxSecretStore]** — writes throw, reads return
/// `null`. The default is deliberately not a working in-memory store: a
/// host that forgets to bind a real one would otherwise accept the user's
/// token, lose it at restart, and give no clue why.
///
/// Hosts bind the real store at bootstrap:
///
/// ```dart
/// cruxSecretStoreProvider.overrideWithValue(
///   const FlutterSecureStorageSecretStore(),
/// )
/// ```
///
/// and tests bind [InMemoryCruxSecretStore] so no test ever touches the
/// developer's keychain.
final Provider<CruxSecretStore> cruxSecretStoreProvider =
    Provider<CruxSecretStore>((ref) => const UnavailableCruxSecretStore());
