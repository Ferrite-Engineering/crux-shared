// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/src/policy_document.dart';
import 'package:meta/meta.dart';

/// What the `telemetry` key says.
///
/// Mirrors `TelemetryPolicy` in `crux_telemetry` without depending on it — the
/// binding is the product's, and a dependency either way round would couple two
/// packages that have no other business with each other.
enum PolicyTelemetryDecision {
  /// The organization mandates collection.
  allow,

  /// The organization forbids collection.
  deny,

  /// No policy governs this installation.
  absent,
}

/// What the `updateChannel` key says.
enum PolicyUpdateChannel {
  /// Track stable releases.
  stable,

  /// Track beta releases.
  beta,

  /// Stay on [DayOnePolicy.pinnedVersion].
  pinned,
}

/// Where a policy licence credential came from.
enum PolicyLicenseKind {
  /// An inline credential in the file.
  inline,

  /// A path to a licence file on the organization's share.
  file,
}

/// A licence supplied by the policy file.
@immutable
class PolicyLicense {
  /// Creates a policy licence reference.
  const PolicyLicense({required this.kind, required this.value});

  /// Inline credential or path.
  final PolicyLicenseKind kind;

  /// The credential itself, or the path to a licence file.
  final String value;
}

/// The subset of the policy file that must resolve **before a licence exists**.
///
/// ### The constraint this whole class follows from
///
/// The first-launch telemetry disclosure fires **before any licence key has
/// been entered**, so at that instant the application's tier is unknown *by
/// construction*. Anything whose meaning depends on a resolved tier is unusable
/// at exactly the moment an Enterprise deployment needs it.
///
/// So these three keys — and only these three — resolve with no licence
/// present, no tier lookup, and nothing that could reach one
/// (<https://edacrux.app/policy-reference#three>).
///
/// A design that resolves a tier and then decides is wrong however elegantly it
/// is expressed, **and it will look like it works**, because in development a
/// licence is always already there.
///
/// This may ship ahead of the rest of the schema, and if item 4 slips it must:
/// an Enterprise pilot that prompts every engineer on first launch is a worse
/// launch-day story than an unshipped key.
@immutable
class DayOnePolicy {
  /// Creates a resolved day-one subset.
  const DayOnePolicy({
    this.telemetry = PolicyTelemetryDecision.absent,
    this.license,
    this.updateChannel,
    this.pinnedVersion,
    this.manifestUrl,
  });

  /// Read the day-one subset out of [document].
  ///
  /// Reads the raw document rather than going through `PolicyResolver`, because
  /// the resolver takes a user setting and a built-in default — and neither
  /// exists yet at the moment these three are needed.
  factory DayOnePolicy.of(PolicyDocument document) {
    final suite = document.suite;

    return DayOnePolicy(
      telemetry: switch (_unwrap(suite['telemetry'])) {
        'allow' => PolicyTelemetryDecision.allow,
        'deny' => PolicyTelemetryDecision.deny,
        // Anything else — absent, misspelled, the wrong type — is absent.
        // Never a throw, and never a guess.
        _ => PolicyTelemetryDecision.absent,
      },
      license: _license(_unwrap(suite['license'])),
      updateChannel: switch (_unwrap(suite['updateChannel'])) {
        'stable' => PolicyUpdateChannel.stable,
        'beta' => PolicyUpdateChannel.beta,
        'pinned' => PolicyUpdateChannel.pinned,
        _ => null,
      },
      pinnedVersion: _unwrap(suite['pinnedVersion']) is String
          ? _unwrap(suite['pinnedVersion'])! as String
          : null,
      manifestUrl: _unwrap(suite['manifestUrl']) is String
          ? _unwrap(suite['manifestUrl'])! as String
          : null,
    );
  }

  /// The state of every installation with no policy file. Behaves in every
  /// respect as if the seam did not exist.
  static const DayOnePolicy absent = DayOnePolicy();

  /// The org-wide telemetry decision.
  final PolicyTelemetryDecision telemetry;

  /// A licence the organization supplied, if any.
  final PolicyLicense? license;

  /// The update channel the organization set, if any.
  final PolicyUpdateChannel? updateChannel;

  /// The version to stay on when [updateChannel] is
  /// [PolicyUpdateChannel.pinned].
  final String? pinnedVersion;

  /// An on-prem update-manifest mirror, for a network that cannot reach ours.
  final String? manifestUrl;

  static PolicyLicense? _license(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final key = raw['key'];
    final file = raw['file'];
    // Exactly one. Both is invalid and guessing which the
    // administrator meant is worse than ignoring the key.
    if (key is String && file == null && key.trim().isNotEmpty) {
      return PolicyLicense(kind: PolicyLicenseKind.inline, value: key.trim());
    }
    if (file is String && key == null && file.trim().isNotEmpty) {
      return PolicyLicense(kind: PolicyLicenseKind.file, value: file.trim());
    }
    return null;
  }

  static Object? _unwrap(Object? raw) =>
      raw is Map<String, Object?> && raw.containsKey('value')
      ? raw['value']
      : raw;
}
