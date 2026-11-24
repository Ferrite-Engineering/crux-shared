// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The per-batch envelope: everything the ingestion Worker stores about a
/// batch that is not one of its events.
///
/// Every field here is a closed enum, a random id, or a version string, and
/// the Worker re-checks each one against the same closed sets — a mismatch
/// rejects the whole batch with a 400. That is deliberate on both sides: the
/// envelope is the part of the payload most likely to be quietly widened by a
/// future change, so it is the part that fails loudest.
///
/// There is no field here that identifies a person, a machine, a file, or a
/// design. [installationId] is a random UUID (never hardware-derived), and
/// `country` is not sent at all — the Worker stamps it from Cloudflare request
/// metadata, so the client never handles a location and the IP it is derived
/// from is never stored.
@immutable
class TelemetryEnvelope {
  /// Creates an envelope. Every value is expected to already be a slug from
  /// the closed vocabularies — see `telemetry_platform.dart` for [os], the
  /// `kTelemetryFormFactors` bucket list for [formFactor], and
  /// `LicenseTier.name` for [licenseTier].
  const TelemetryEnvelope({
    required this.installationId,
    required this.appVersion,
    required this.product,
    required this.os,
    required this.formFactor,
    required this.locale,
    required this.licenseTier,
    required this.sessionStart,
    required this.userAgentName,
  });

  /// Random v4 UUID minted once per installation.
  final String installationId;

  /// The running build's version string (`0.6.0`).
  final String appVersion;

  /// Product slug — `PRODUCTS` in the ingestion Worker (`wavecrux`,
  /// `netcrux`, `lintcrux`, `simcrux`). Supplied by
  /// `CruxTelemetryConfig.productSlug`; this package hardcodes no product.
  final String product;

  /// `macos | windows | linux | ios | android | web`.
  final String os;

  /// `desktop | phone | tablet | web`.
  final String formFactor;

  /// The resolved app locale (`en`, `zh_CN`, `ja`, `ko`).
  final String locale;

  /// `openCore | edu | pro | enterprise`.
  final String licenseTier;

  /// When this app session started. **Not** a duration signal: nothing
  /// reports when a session ends, and the Worker drops the field after
  /// validating it (Analytics Engine stamps its own row timestamp).
  final DateTime sessionStart;

  /// The product's display name as it appears in the `User-Agent`
  /// (`WaveCrux`, not `wavecrux`).
  ///
  /// Header-only, and deliberately separate from [product]: the body field is
  /// a slug the Worker validates against a closed set, while the header is the
  /// human-readable name the update check already sends. Never serialized —
  /// see [toJson].
  final String userAgentName;

  /// The envelope as the Worker expects it, without the `events` array.
  ///
  /// Key order matches the canonical `valid-batch.json` fixture so a hand-diff
  /// of a captured request against the fixture reads straight down.
  Map<String, Object?> toJson() => <String, Object?>{
    'installation_id': installationId,
    'app_version': appVersion,
    'product': product,
    'os': os,
    'form_factor': formFactor,
    'locale': locale,
    'license_tier': licenseTier,
    'session_start': telemetryIso8601(sessionStart),
  };

  /// `User-Agent` for the ingest POST, matching the update check's shape
  /// (`WaveCrux/0.6.0`).
  ///
  /// The version is already in the body; the header exists because a request
  /// with no `User-Agent` is treated as a bot by the edge, and because it
  /// keeps the two outbound calls a Crux app makes recognisable as the same
  /// application.
  String get userAgent => '$userAgentName/$appVersion';
}

/// ISO-8601 UTC to **whole seconds** — `2026-08-04T09:15:00Z`.
///
/// Dart's own `toIso8601String` emits milliseconds. They are dropped for two
/// reasons: the Worker bounds the field at 32 characters, and sub-second
/// precision on a session start is precision about a *person's* behaviour that
/// nothing downstream reads.
String telemetryIso8601(DateTime time) {
  final iso = time.toUtc().toIso8601String();
  final dot = iso.indexOf('.');
  return dot < 0 ? iso : '${iso.substring(0, dot)}Z';
}
