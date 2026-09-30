// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_grant.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/license_validation.dart';
import 'package:meta/meta.dart';

/// Where a licence stands, from the panel's point of view.
///
/// Broader than [LicenseValidation] on purpose. The validator answers "are
/// these bytes authentic and current"; this answers "what is this user's
/// situation", which additionally involves whether the machine is registered
/// with the issuer and whether a grace period is running — both of which are
/// each product's `LicenseService` to decide, not the validator's.
enum CruxLicenseActivation {
  /// No credential stored. **Not an error state** — Open Core is the absence
  /// of a licence, and it is where every user starts.
  openCore,

  /// Validated, current, and this machine is registered.
  active,

  /// Validated and current, but this machine has not been registered with the
  /// issuer yet. The tier still applies: a validated key works offline, and
  /// the first check-in that reaches the issuer registers the machine.
  notActivatedOnThisMachine,

  /// Validated and current, but the licence has no seat for this machine:
  /// every seat is taken and this machine was refused one, or the licence
  /// holds more registered machines than it has seats — its owner reduced
  /// the seat count after the machines registered. Falls back to Open Core
  /// until a seat is freed, and the credential stays stored so the next
  /// activation or check-in can take one.
  ///
  /// Only ever the issuer's explicit answer. A machine that cannot reach the
  /// issuer is never put here, because that is the offline case, and offline
  /// keeps the tier.
  noSeat,

  /// Past expiry, inside the grace period of `LicenseGracePolicy`. The tier
  /// still applies.
  grace,

  /// Past expiry and past grace. Falls back to Open Core.
  expired,

  /// A credential is stored but no longer validates — tampered, revoked, or
  /// issued against a SKU this build predates.
  invalid,
}

/// Everything the licence panel renders, in one immutable value.
///
/// The panel is a pure function of this. Each Pro overlay publishes it
/// from its own `LicenseService` through `licenseStatusProvider`; the shared
/// widget never reaches for a service, which is what lets one widget serve
/// four products whose services have nothing in common.
@immutable
class CruxLicenseStatus {
  /// Create a status.
  const CruxLicenseStatus({
    this.activation = CruxLicenseActivation.openCore,
    this.grant,
    this.graceEndsAt,
    this.seatsUsed,
    this.seatsTotal,
    this.rejection,
    this.lastCheckedAt,
    this.machineLabel,
    this.busy = false,
  });

  /// The unlicensed state — what a fresh install shows, and the default
  /// behind `licenseStatusProvider`.
  static const CruxLicenseStatus openCore = CruxLicenseStatus();

  /// Where the licence stands.
  final CruxLicenseActivation activation;

  /// The validated grant, when there is one. Present in the grace and
  /// expired states too: the licence still says what it said.
  final LicenseGrant? grant;

  /// When grace runs out, while [activation] is
  /// [CruxLicenseActivation.grace].
  final DateTime? graceEndsAt;

  /// Machines currently registered against this licence, when known.
  ///
  /// Only known after a successful check-in — a bare licence key carries no
  /// seat information at all, so an offline app cannot know it.
  final int? seatsUsed;

  /// Machines the licence permits, when known.
  final int? seatsTotal;

  /// Why a stored credential was refused, while [activation] is
  /// [CruxLicenseActivation.invalid].
  final LicenseRejection? rejection;

  /// When the app last reached the issuer. `null` means never — which is a
  /// perfectly good state to be in, since a validated key works offline.
  final DateTime? lastCheckedAt;

  /// Human-readable name of this machine as registered with the issuer.
  final String? machineLabel;

  /// Whether an operation is in flight. The panel disables its actions and
  /// shows a progress indicator.
  final bool busy;

  /// The tier this status runs at.
  ///
  /// Grace keeps the licensed tier — that is what grace *is*. Expired and
  /// invalid fall back to Open Core.
  LicenseTier get tier => switch (activation) {
    CruxLicenseActivation.active ||
    CruxLicenseActivation.notActivatedOnThisMachine ||
    CruxLicenseActivation.grace => grant?.tier ?? LicenseTier.openCore,
    CruxLicenseActivation.openCore ||
    CruxLicenseActivation.expired ||
    CruxLicenseActivation.noSeat ||
    CruxLicenseActivation.invalid => LicenseTier.openCore,
  };

  /// Whether a credential is stored at all, valid or not.
  bool get hasCredential => activation != CruxLicenseActivation.openCore;

  /// Days of grace left as of [now], or `null` when not in grace.
  int? graceDaysRemainingAt(DateTime now) {
    final end = graceEndsAt;
    if (activation != CruxLicenseActivation.grace || end == null) return null;
    final left = end.difference(now).inDays;
    return left < 0 ? 0 : left;
  }

  /// Copy with selected fields replaced.
  ///
  /// Nullable fields are not clearable through this — a service moving from
  /// "licensed" to "unlicensed" should publish [openCore] rather than try to
  /// null its way there one field at a time.
  CruxLicenseStatus copyWith({
    CruxLicenseActivation? activation,
    LicenseGrant? grant,
    DateTime? graceEndsAt,
    int? seatsUsed,
    int? seatsTotal,
    LicenseRejection? rejection,
    DateTime? lastCheckedAt,
    String? machineLabel,
    bool? busy,
  }) => CruxLicenseStatus(
    activation: activation ?? this.activation,
    grant: grant ?? this.grant,
    graceEndsAt: graceEndsAt ?? this.graceEndsAt,
    seatsUsed: seatsUsed ?? this.seatsUsed,
    seatsTotal: seatsTotal ?? this.seatsTotal,
    rejection: rejection ?? this.rejection,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    machineLabel: machineLabel ?? this.machineLabel,
    busy: busy ?? this.busy,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxLicenseStatus &&
          other.activation == activation &&
          other.grant == grant &&
          other.graceEndsAt == graceEndsAt &&
          other.seatsUsed == seatsUsed &&
          other.seatsTotal == seatsTotal &&
          other.rejection == rejection &&
          other.lastCheckedAt == lastCheckedAt &&
          other.machineLabel == machineLabel &&
          other.busy == busy;

  @override
  int get hashCode => Object.hash(
    activation,
    grant,
    graceEndsAt,
    seatsUsed,
    seatsTotal,
    rejection,
    lastCheckedAt,
    machineLabel,
    busy,
  );

  @override
  String toString() =>
      'CruxLicenseStatus(${activation.name}, ${tier.name}'
      '${busy ? ', busy' : ''})';
}
