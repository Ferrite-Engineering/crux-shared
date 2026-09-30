// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite secret storage for the EDACrux suite.
///
/// A narrow read/write/delete seam over the operating system's credential
/// store, for the one class of data that must never reach
/// `shared_preferences`: a credential the user typed.
///
/// `shared_preferences` is a plist on macOS, a registry key on Windows and a
/// JSON file on Linux — all readable by anything running as the user. That
/// is fine for a theme choice and wrong for a token that can push commit
/// statuses to a company's repositories or open a connection to their
/// database.
///
/// Consumers:
///
/// * SimCrux — PR-annotation auth tokens (GitHub / GitLab / webhook bearer).
/// * SimCrux + LintCrux — the Enterprise shared-team-database password.
///
/// Wiring:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     cruxSecretStoreProvider.overrideWithValue(
///       const FlutterSecureStorageSecretStore(),
///     ),
///   ],
///   child: const MyApp(),
/// )
/// ```
///
/// The default binding is `UnavailableCruxSecretStore`, which throws on
/// write — an unbound host fails loudly rather than silently discarding
/// the user's credential.
library;

export 'src/providers/secret_store_provider.dart';
export 'src/secret_store.dart';
export 'src/services/flutter_secure_storage_secret_store.dart';
