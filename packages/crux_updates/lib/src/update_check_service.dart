// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/update_manifest.dart';

/// The extension point for checking whether a newer release is available.
///
/// The package ships **two** implementations: a `NoopUpdateCheckService` (for
/// tests, mobile store builds, and the pre-build-info window) and a live
/// `HttpUpdateCheckService` that fetches the product's public version manifest.
/// Unlike a telemetry seam — whose default is the no-op — the update-check
/// default binding is the **live** HTTP service, because a public
/// version-manifest fetch carries no secret.
///
/// ## Contract: never breaks a feature flow
///
/// [checkForUpdate] resolves to:
///   * a non-null [UpdateInfo] when a newer, supported release exists,
///   * `null` when the running build is current (no update),
///
/// and signals a network/parse failure by throwing exactly one typed
/// [UpdateCheckException] — never a raw `SocketException`, `FormatException`,
/// `TimeoutException`, or any other leaked error. The sole caller
/// (`updateStatusProvider`) wraps the call and maps that typed exception to a
/// typed error *state*, so no error ever escapes into a feature flow.
abstract class UpdateCheckService {
  /// Checks the version manifest for a newer supported release.
  ///
  /// Returns the [UpdateInfo] to offer, or `null` when current. Throws
  /// [UpdateCheckException] (and only that) on any network or parse failure.
  Future<UpdateInfo?> checkForUpdate();
}

/// The single typed failure an [UpdateCheckService] may surface from
/// [UpdateCheckService.checkForUpdate].
///
/// Wraps the underlying cause (a socket error, non-200 response, timeout, or a
/// soft-failed manifest parse) so the caller can render a generic "couldn't
/// check for updates" message without inspecting transport internals.
class UpdateCheckException implements Exception {
  /// Creates an exception describing why an update check failed.
  const UpdateCheckException(this.reason, [this.cause]);

  /// A short, non-localized reason code for diagnostics (e.g. `'network'`,
  /// `'http 503'`, `'parse'`). Never shown to the user verbatim.
  final String reason;

  /// The optional underlying error, retained for logging.
  final Object? cause;

  @override
  String toString() => 'UpdateCheckException($reason)';
}
