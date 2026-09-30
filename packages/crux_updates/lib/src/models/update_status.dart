// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/update_manifest.dart';
import 'package:meta/meta.dart';

/// The state held by `updateStatusProvider` describing the most recent
/// update-check outcome.
///
/// A sealed hierarchy so callers `switch` exhaustively over the four outcomes
/// the mechanism distinguishes: nothing to do ([UpdateStatusCurrent]), a check
/// in flight ([UpdateStatusChecking]), an available update carrying its
/// [UpdateInfo] ([UpdateStatusAvailable]), and a failed check
/// ([UpdateStatusError]). Pure Dart — no Flutter imports.
@immutable
sealed class UpdateStatus {
  const UpdateStatus();
}

/// The running build is up to date — no newer supported version is available.
/// The banner renders nothing in this state.
@immutable
final class UpdateStatusCurrent extends UpdateStatus {
  /// Creates the up-to-date status.
  const UpdateStatusCurrent();

  @override
  bool operator ==(Object other) => other is UpdateStatusCurrent;

  @override
  int get hashCode => (UpdateStatusCurrent).hashCode;

  @override
  String toString() => 'UpdateStatusCurrent()';
}

/// A check is in flight. The banner renders nothing; the manual check entry
/// point shows a transient "Checking…" affordance.
@immutable
final class UpdateStatusChecking extends UpdateStatus {
  /// Creates the in-flight status.
  const UpdateStatusChecking();

  @override
  bool operator ==(Object other) => other is UpdateStatusChecking;

  @override
  int get hashCode => (UpdateStatusChecking).hashCode;

  @override
  String toString() => 'UpdateStatusChecking()';
}

/// A newer, supported version is available. Carries the parsed [info] that the
/// banner renders (`NetCrux 1.2.0 is available.`).
@immutable
final class UpdateStatusAvailable extends UpdateStatus {
  /// Creates an available-update status wrapping [info].
  const UpdateStatusAvailable(this.info);

  /// The release the user can move to.
  final UpdateInfo info;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateStatusAvailable &&
          runtimeType == other.runtimeType &&
          info == other.info;

  @override
  int get hashCode => info.hashCode;

  @override
  String toString() => 'UpdateStatusAvailable($info)';
}

/// The most recent check failed (network or malformed-manifest). The banner
/// renders nothing — a failed silent check must not nag — while the manual
/// entry point surfaces a non-fatal "couldn't check" message.
@immutable
final class UpdateStatusError extends UpdateStatus {
  /// Creates the failed-check status.
  const UpdateStatusError();

  @override
  bool operator ==(Object other) => other is UpdateStatusError;

  @override
  int get hashCode => (UpdateStatusError).hashCode;

  @override
  String toString() => 'UpdateStatusError()';
}
