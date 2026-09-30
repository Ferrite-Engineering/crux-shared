// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_updates/src/models/semantic_version.dart';
import 'package:meta/meta.dart';

/// One release entry from a product's update manifest (the `latest` object of
/// the suite-wide version-manifest format).
///
/// Pure Dart, no Flutter imports. Every instance parsed from the wire comes
/// from [fromJson], which **fails soft**: a malformed or missing required field
/// yields `null` ("no update info") rather than throwing. The only strictly
/// required field is [version]; everything else carries a benign default.
@immutable
final class UpdateInfo {
  /// Creates an [UpdateInfo] from already-validated components.
  const UpdateInfo({
    required this.version,
    this.channel = 'stable',
    this.releaseDate,
    this.changelogUrl,
    this.mandatory = false,
    this.minSupportedVersion,
    this.openCoreVersion,
    this.downloads = const <String, String>{},
    this.checksums = const <String, String>{},
    this.serverTime,
  });

  /// Parses a single release object. Returns `null` when [raw] is not a JSON
  /// object or lacks a non-empty `version`. Unknown/missing optional fields
  /// fall back to defaults; type-mismatched optional fields are dropped rather
  /// than throwing.
  static UpdateInfo? fromJson(Object? raw) {
    final json = _asStringMap(raw);
    if (json == null) return null;

    final version = json['version'];
    if (version is! String || version.trim().isEmpty) return null;

    return UpdateInfo(
      version: version,
      channel: json['channel'] is String
          ? json['channel']! as String
          : 'stable',
      releaseDate: _asDate(json['release_date']),
      changelogUrl: json['changelog_url'] is String
          ? json['changelog_url']! as String
          : null,
      mandatory: json['mandatory'] == true,
      minSupportedVersion: json['min_supported_version'] is String
          ? json['min_supported_version']! as String
          : null,
      openCoreVersion: json['open_core_version'] is String
          ? json['open_core_version']! as String
          : null,
      downloads: _asStringValueMap(json['downloads']),
      checksums: _asStringValueMap(json['checksums']),
      serverTime: _asDate(json['server_time']),
    );
  }

  /// The advertised version string, e.g. `"1.2.0"`. Always non-empty.
  final String version;

  /// Release channel. Defaults to `stable` when the manifest does not say, so
  /// a manifest that has never heard of channels reads as an all-stable one.
  ///
  /// Honoured by `UpdatePolicy`: an organization that set `suite.updateChannel`
  /// is offered only the channels it asked for. Nothing outside that Enterprise
  /// seam reads this field — an unconstrained installation is offered whatever
  /// the manifest advertises.
  final String channel;

  /// Release date (`YYYY-MM-DD`), or `null` when absent/unparseable.
  final DateTime? releaseDate;

  /// URL of the human-readable changelog / release notes, or `null`.
  final String? changelogUrl;

  /// When `true`, the update is non-dismissible (critical fix). The policy that
  /// *sets* this lives on the release side; this package merely *honors* it.
  final bool mandatory;

  /// The oldest still-supported version, or `null` when unspecified. See
  /// [meetsMinSupported].
  final String? minSupportedVersion;

  /// The newest release that changed what a seat with no paid features
  /// unlocked actually gets, or `null` when the manifest does not say.
  ///
  /// Every desktop download is one binary per product, and a licence key
  /// unlocks paid features in place — so a user who never buys runs the same
  /// build a paying customer does. A release whose every change sits behind a
  /// paid-tier gate would still be newer for them, and without this field it
  /// would put an update banner in front of the free majority for a build with
  /// nothing in it they can use. The release side leaves this field at its
  /// previous value for such a release and moves it to [version] for any
  /// other.
  ///
  /// It never names a different download: what is offered is always
  /// [version], which carries every earlier release's changes. See
  /// [changesOpenCoreSince] for the comparison and `UpdateEdition.offers` for
  /// who it applies to.
  final String? openCoreVersion;

  /// Per-platform download URLs keyed by platform id (`linux_x64`,
  /// `macos_universal`, `windows_x64`, …). Parsed and retained for a future
  /// in-place-update transport; the banner deep-links to the product's download
  /// page rather than fetching these directly.
  final Map<String, String> downloads;

  /// Per-platform `sha256:` checksums keyed by the same platform ids as
  /// [downloads]. Retained for the future in-place-update transport.
  final Map<String, String> checksums;

  /// Authoritative server-supplied wall-clock time (ISO-8601), or `null`.
  ///
  /// Feeds `crux_license`'s beta-expiry clock-tampering hardening: the most
  /// recently observed value becomes the trusted "now", so setting the device
  /// clock back can no longer defer beta expiry.
  final DateTime? serverTime;

  /// Whether [version] is strictly newer than [current].
  ///
  /// Returns `false` when either string is not valid semver — a parse failure
  /// must never *manufacture* an update notification.
  bool isNewerThan(String current) {
    final here = SemanticVersion.tryParse(version);
    final there = SemanticVersion.tryParse(current);
    if (here == null || there == null) return false;
    return here > there;
  }

  /// Whether [current] still satisfies this release's [minSupportedVersion]
  /// floor (i.e. `current >= min_supported_version`).
  ///
  /// Returns `true` when no floor is declared or the floor is unparseable
  /// (no restriction). Returns `false` when [current] itself is unparseable
  /// (cannot prove eligibility). A newer update is always surfaced regardless;
  /// when this is `false` the update-check service forces it non-dismissible
  /// (`mandatory`), since a build below the floor is no longer supported (see
  /// `HttpUpdateCheckService`).
  bool meetsMinSupported(String current) {
    final floor = minSupportedVersion;
    if (floor == null || floor.trim().isEmpty) return true;
    final min = SemanticVersion.tryParse(floor);
    if (min == null) return true;
    final here = SemanticVersion.tryParse(current);
    if (here == null) return false;
    return here >= min;
  }

  /// Whether a build at [current] is missing a change that matters to a seat
  /// with no paid features unlocked — `current < open_core_version`.
  ///
  /// Returns `true` when no [openCoreVersion] is declared, or when either
  /// version is unparseable. The field exists only to *withhold* an offer, so
  /// data it cannot read falls back to the behaviour from before it existed —
  /// offer the release — rather than hiding one from the users it was never
  /// meant to hide from. (An unparseable [current] is never offered anything
  /// anyway: [isNewerThan] is already `false` for it.)
  bool changesOpenCoreSince(String current) {
    final raw = openCoreVersion;
    if (raw == null || raw.trim().isEmpty) return true;
    final changed = SemanticVersion.tryParse(raw);
    final here = SemanticVersion.tryParse(current);
    if (changed == null || here == null) return true;
    return here < changed;
  }

  /// The download URL for [platformId], or `null` when none is listed.
  String? downloadUrlFor(String platformId) => downloads[platformId];

  /// The `sha256:`-prefixed checksum for [platformId], or `null` when none is
  /// listed or the listed value is not a well-formed sha256 digest.
  ///
  /// The symmetric partner of [downloadUrlFor]. Both fields are retained for
  /// the future in-place-update transport; until then a product may surface
  /// this next to its download link so a user can verify a manual download,
  /// which is a real trust signal for a binary that ships unsigned by default.
  ///
  /// Malformed values resolve to `null` rather than being handed back
  /// verbatim: a checksum a user might paste into `shasum -c` must be either
  /// correct or absent, never plausible-looking rubbish.
  String? checksumFor(String platformId) {
    final raw = checksums[platformId];
    if (raw == null) return null;
    final match = RegExp(
      r'^sha256:([0-9a-f]{64})$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    return match == null ? null : 'sha256:${match.group(1)!.toLowerCase()}';
  }

  /// Returns a copy with the given fields replaced.
  UpdateInfo copyWith({
    String? version,
    String? channel,
    DateTime? releaseDate,
    String? changelogUrl,
    bool? mandatory,
    String? minSupportedVersion,
    String? openCoreVersion,
    Map<String, String>? downloads,
    Map<String, String>? checksums,
    DateTime? serverTime,
  }) {
    return UpdateInfo(
      version: version ?? this.version,
      channel: channel ?? this.channel,
      releaseDate: releaseDate ?? this.releaseDate,
      changelogUrl: changelogUrl ?? this.changelogUrl,
      mandatory: mandatory ?? this.mandatory,
      minSupportedVersion: minSupportedVersion ?? this.minSupportedVersion,
      openCoreVersion: openCoreVersion ?? this.openCoreVersion,
      downloads: downloads ?? this.downloads,
      checksums: checksums ?? this.checksums,
      serverTime: serverTime ?? this.serverTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateInfo &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          channel == other.channel &&
          releaseDate == other.releaseDate &&
          changelogUrl == other.changelogUrl &&
          mandatory == other.mandatory &&
          minSupportedVersion == other.minSupportedVersion &&
          openCoreVersion == other.openCoreVersion &&
          _stringMapEquals(downloads, other.downloads) &&
          _stringMapEquals(checksums, other.checksums) &&
          serverTime == other.serverTime;

  @override
  int get hashCode => Object.hash(
    version,
    channel,
    releaseDate,
    changelogUrl,
    mandatory,
    minSupportedVersion,
    openCoreVersion,
    Object.hashAllUnordered(
      downloads.entries.map((e) => '${e.key}=${e.value}'),
    ),
    Object.hashAllUnordered(
      checksums.entries.map((e) => '${e.key}=${e.value}'),
    ),
    serverTime,
  );

  @override
  String toString() =>
      'UpdateInfo(version: $version, channel: $channel, '
      'mandatory: $mandatory, minSupportedVersion: $minSupportedVersion, '
      'openCoreVersion: $openCoreVersion, serverTime: $serverTime)';
}

/// The top-level update manifest document fetched from a product's version
/// endpoint.
///
/// Wraps the single `latest` release object. [tryParse] decodes a raw JSON
/// string and fails soft — any decode error, non-object root, or
/// missing/invalid `latest` yields `null`.
@immutable
final class UpdateManifest {
  /// Creates a manifest wrapping its [latest] release.
  const UpdateManifest({required this.latest});

  /// Decodes [jsonText] into a manifest, or `null` on any malformed input.
  static UpdateManifest? tryParse(String jsonText) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    return fromJson(decoded);
  }

  /// Builds a manifest from already-decoded JSON, or `null` when [raw] is not
  /// an object or its `latest` entry is missing/invalid.
  static UpdateManifest? fromJson(Object? raw) {
    final json = _asStringMap(raw);
    if (json == null) return null;
    final latest = UpdateInfo.fromJson(json['latest']);
    if (latest == null) return null;
    return UpdateManifest(latest: latest);
  }

  /// The most recent release advertised by the manifest.
  final UpdateInfo latest;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateManifest &&
          runtimeType == other.runtimeType &&
          latest == other.latest;

  @override
  int get hashCode => latest.hashCode;

  @override
  String toString() => 'UpdateManifest(latest: $latest)';
}

/// Coerces [raw] to a `Map<String, Object?>`, or `null` when it is not a map.
Map<String, Object?>? _asStringMap(Object? raw) {
  if (raw is! Map) return null;
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

/// Extracts the string-valued entries of a JSON map; non-string values and
/// non-map inputs yield an empty map.
Map<String, String> _asStringValueMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((key, value) {
    if (value is String) out[key.toString()] = value;
  });
  return out;
}

/// Parses an ISO-8601 date/timestamp string, or `null` when absent/invalid.
DateTime? _asDate(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

/// Order-independent equality for two `Map<String, String>`s.
bool _stringMapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
