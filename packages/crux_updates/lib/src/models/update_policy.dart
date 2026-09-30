// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/semantic_version.dart';
import 'package:crux_updates/src/models/update_manifest.dart';
import 'package:meta/meta.dart';

/// What the policy file's `suite.updateChannel` key says.
///
/// Mirrors `PolicyUpdateChannel` in `crux_policy` without depending on it, the
/// same way `TelemetryPolicy` mirrors `PolicyTelemetryDecision`. This package
/// does not know the policy format, where the file lives, or how its signature
/// is checked — it knows the shape of the answer and the behaviour that answer
/// selects.
enum UpdateChannelPolicy {
  /// Offer stable releases only.
  stable,

  /// Offer stable and beta releases.
  beta,

  /// Stay at [UpdatePolicy.pinnedVersion].
  pinned,
}

/// The organization's update constraints, if any govern this installation.
///
/// Three keys, all Enterprise, all optional, all defaulting to *unconstrained*:
///
/// * `suite.updateChannel` — which releases may be offered at all;
/// * `suite.pinnedVersion` — the ceiling, when the channel is `pinned`;
/// * `suite.manifestUrl` — an on-prem mirror, for a network that cannot reach
///   ours.
///
/// ### What this is NOT
///
/// It is **not** the managed-install verdict. `ManagedInstall` describes how
/// the app was deployed and suppresses the manifest fetch outright; this says
/// what an administrator configured, and it is checked strictly *after*. The
/// doc comment on `ManagedInstall` states that ordering and why inverting it
/// would let `updateChannel: stable` silently re-enable self-update across an
/// SCCM-managed fleet.
///
/// ### Constraints withhold the offer; they never fabricate one
///
/// Every path through [allows] can only turn an update the manifest advertised
/// into no-update. None of them can produce an offer that the unconstrained
/// check would not have made, and none of them touches the manifest fetch
/// itself — so the `server_time` that hardens beta expiry against a clock
/// rollback is still observed on a pinned seat, on every fetch, exactly as it
/// is everywhere else. That is deliberate: pinning the version an organization
/// runs must not hand its engineers a way to defer the beta clock.
@immutable
final class UpdatePolicy {
  /// Creates a set of constraints.
  const UpdatePolicy({this.channel, this.pinnedVersion, this.manifestUri});

  /// Builds constraints from the policy file's own vocabulary.
  ///
  /// **This is the binding.** The words are the ones in the file — `stable`,
  /// `beta`, `pinned` — so nothing but the wire format crosses the boundary and
  /// this package keeps its independence from `crux_policy`. In a Pro overlay:
  ///
  /// ```dart
  /// updatePolicyProvider.overrideWith((ref) {
  ///   final policy = ref.watch(dayOnePolicyProvider);
  ///   return UpdatePolicy.fromNames(
  ///     channel: policy.updateChannel?.name,
  ///     pinnedVersion: policy.pinnedVersion,
  ///     manifestUrl: policy.manifestUrl,
  ///   );
  /// }),
  /// ```
  ///
  /// Fails soft in both directions, matching `DayOnePolicy.of`: an unrecognised
  /// channel name leaves [channel] null (unconstrained), and a [manifestUrl]
  /// that is not an absolute `http`/`https` URL leaves [manifestUri] null (the
  /// product's own endpoint). Neither is an error and neither throws — an
  /// administrator's typo must not brick the deployment it was meant to
  /// configure, and `crux_policy`'s `policyLint` is where a typo gets reported.
  ///
  /// `file:` and `data:` URLs are rejected here rather than merely failing at
  /// fetch time: the manifest decides what version the fleet is told about, and
  /// a local file is not a mirror an administrator deployed. `http:` **is**
  /// honoured — an internal mirror on a closed network commonly has no
  /// certificate, and the manifest is public data whose only power is to
  /// advertise a version string and a changelog link.
  factory UpdatePolicy.fromNames({
    String? channel,
    String? pinnedVersion,
    String? manifestUrl,
  }) {
    return UpdatePolicy(
      channel: switch (channel) {
        'stable' => UpdateChannelPolicy.stable,
        'beta' => UpdateChannelPolicy.beta,
        'pinned' => UpdateChannelPolicy.pinned,
        _ => null,
      },
      pinnedVersion: (pinnedVersion == null || pinnedVersion.trim().isEmpty)
          ? null
          : pinnedVersion.trim(),
      manifestUri: _mirrorUri(manifestUrl),
    );
  }

  /// The state of every installation no policy file governs. Behaves in every
  /// respect as if the seam did not exist.
  static const UpdatePolicy absent = UpdatePolicy();

  /// Which releases may be offered, or `null` when the organization set no
  /// channel (or set one this build does not recognise).
  final UpdateChannelPolicy? channel;

  /// The version the fleet stays at under [UpdateChannelPolicy.pinned].
  final String? pinnedVersion;

  /// The on-prem manifest mirror to fetch instead of the product's own
  /// endpoint, or `null` to use the product's.
  final Uri? manifestUri;

  /// Whether these constraints change any behaviour at all.
  bool get isAbsent =>
      channel == null && pinnedVersion == null && manifestUri == null;

  /// Whether [info] may be offered to the user.
  ///
  /// Pure, and the whole of the filtering rule:
  ///
  /// * **No channel set** — everything the manifest advertises is offered, and
  ///   `pinnedVersion` on its own does nothing. A version ceiling that took
  ///   effect without the channel that declares it would mean an administrator
  ///   who wrote `pinnedVersion` while trialling it had already pinned the
  ///   fleet.
  /// * **`stable`** — only releases whose `channel` is `stable`. This is the
  ///   only value that can *narrow* the default: an unlabelled release parses
  ///   as `stable` (see `UpdateInfo.fromJson`), so a manifest that says nothing
  ///   about channels behaves for a `stable` fleet exactly as it does for an
  ///   unconstrained one.
  /// * **`beta`** — `stable` or `beta`, and nothing else. It widens by exactly
  ///   one channel; an `alpha` or `nightly` release is still withheld, because
  ///   an administrator who opted into betas did not thereby opt into whatever
  ///   channel name the release side invents next.
  /// * **`pinned`** — a ceiling at [pinnedVersion]: offered only when the
  ///   advertised version is not newer than the pin. That is a *ceiling*, not
  ///   an equality test, so a seat still on 1.2.0 in a fleet pinned at 1.4.0 is
  ///   correctly offered 1.4.0 by a mirror advertising it — which is precisely
  ///   the deployment `manifestUrl` and `pinned` exist to serve together.
  ///   Anything unparseable — either version, or a missing pin — withholds:
  ///   under a pin the administrator owns the fleet's version, and an offer we
  ///   cannot prove is within the ceiling is one we must not make.
  ///
  /// Channel comparison is case-insensitive and trimmed. Version comparison is
  /// semver via [SemanticVersion].
  bool allows(UpdateInfo info) {
    final channel = this.channel;
    if (channel == null) return true;

    final advertised = info.channel.trim().toLowerCase();
    return switch (channel) {
      UpdateChannelPolicy.stable => advertised == 'stable',
      UpdateChannelPolicy.beta =>
        advertised == 'stable' || advertised == 'beta',
      UpdateChannelPolicy.pinned => _withinPin(info.version),
    };
  }

  bool _withinPin(String advertised) {
    final pin = pinnedVersion;
    if (pin == null) return false;
    final ceiling = SemanticVersion.tryParse(pin);
    final offered = SemanticVersion.tryParse(advertised);
    if (ceiling == null || offered == null) return false;
    return offered <= ceiling;
  }

  static Uri? _mirrorUri(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.isAbsolute) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdatePolicy &&
          runtimeType == other.runtimeType &&
          channel == other.channel &&
          pinnedVersion == other.pinnedVersion &&
          manifestUri == other.manifestUri;

  @override
  int get hashCode => Object.hash(channel, pinnedVersion, manifestUri);

  @override
  String toString() =>
      'UpdatePolicy(channel: ${channel?.name}, pinnedVersion: $pinnedVersion, '
      'manifestUri: $manifestUri)';
}
