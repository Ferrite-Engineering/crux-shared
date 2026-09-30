// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/update_manifest.dart';
import 'package:crux_updates/src/models/update_policy.dart';
import 'package:crux_updates/src/update_check_service.dart';

/// An [UpdateCheckService] that withholds updates the organization's policy
/// does not allow.
///
/// A decorator rather than a branch inside `HttpUpdateCheckService`, for a
/// reason that is load-bearing: the fetch must still happen. The manifest's
/// `server_time` is what hardens `crux_license`'s beta expiry against a device
/// clock set backwards, and it is recorded by the inner service on every
/// successful fetch. Filtering *after* the fetch keeps a pinned or
/// stable-channel seat contributing that observation exactly like any other,
/// while a branch that skipped the fetch would quietly hand every Enterprise
/// seat a way to stop the beta clock.
///
/// It also means the constraint is one pure predicate — [UpdatePolicy.allows] —
/// applied at one place, instead of being threaded through HTTP, parsing, and
/// version comparison.
///
/// Errors pass through untouched: an [UpdateCheckException] from the inner
/// service is the same failure whether or not a policy governs the seat, and
/// converting one into "no update" would report a network outage as *current*.
class PolicyConstrainedUpdateCheckService implements UpdateCheckService {
  /// Wraps [inner] with [policy]'s constraints.
  const PolicyConstrainedUpdateCheckService({
    required this.inner,
    required this.policy,
  });

  /// The service that actually fetches — normally `HttpUpdateCheckService`.
  final UpdateCheckService inner;

  /// The constraints to apply to whatever [inner] returns.
  final UpdatePolicy policy;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    final info = await inner.checkForUpdate();
    if (info == null) return null;
    return policy.allows(info) ? info : null;
  }
}
