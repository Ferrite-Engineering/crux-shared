// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/providers/managed_install_provider.dart';
import 'package:crux_updates/src/providers/update_seam_providers.dart';
import 'package:crux_updates/src/services/http_update_check_service.dart';
import 'package:crux_updates/src/services/noop_update_check_service.dart';
import 'package:crux_updates/src/services/policy_constrained_update_check_service.dart';
import 'package:crux_updates/src/update_check_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The active [UpdateCheckService].
///
/// The default is the **live** [HttpUpdateCheckService] (a public manifest
/// fetch holds no secret), configured from [cruxUpdateConfigProvider] and the
/// running build's version and OS. Three cases fall back to
/// [NoopUpdateCheckService]:
///
/// * **A managed install** — deployed by MSI, `.deb` or `.rpm`, so the
///   organization's tooling owns the version. Checked FIRST and deliberately
///   ahead of everything else, including any policy key: `suite.updateChannel`
///   describes what an administrator configured, while this describes how the
///   app was installed, and letting the former re-enable self-update on an
///   SCCM-managed fleet is exactly the confusion this ordering prevents. The
///   *check* is suppressed, not the dialog — a managed install issues no
///   manifest fetch at all.
/// * **iOS/Android**, unless `CruxUpdateConfig.checkOnMobile` is set. Mobile
///   builds update through their store, so the in-app check is redundant —
///   and skipping it keeps the mobile build free of any outbound request,
///   which the store privacy declarations depend on.
/// * **Before [updateBuildInfoProvider] resolves**, so a check that races
///   startup reports "current" rather than comparing against an unknown
///   version. `updateStatusProvider` awaits the build info before reading this
///   provider, so the live service is in place by the time a real check runs.
///
/// When an organization's policy file sets any of `updateChannel`,
/// `pinnedVersion` or `manifestUrl` — [updatePolicyProvider] — the live service
/// is additionally *pointed at the mirror* and *wrapped* in a
/// [PolicyConstrainedUpdateCheckService]. Both are strictly after the
/// managed-install check above, and neither can produce an offer the
/// unconstrained graph would not have made.
///
/// The seat's edition ([updateEditionProvider]) is deliberately **not** applied
/// here. It changes at runtime when a licence is entered or lapses, so it is
/// applied where results are published — `updateStatusProvider` — over the last
/// release this service returned. A wrapper here would have to fetch again to
/// honour a licence change.
///
/// Override with a fake in tests.
final Provider<UpdateCheckService> updateCheckServiceProvider =
    Provider<UpdateCheckService>((ref) {
      final config = ref.watch(cruxUpdateConfigProvider);

      // First, and before the config is even consulted for anything else.
      if (ref.watch(managedInstallProvider).isManaged) {
        return const NoopUpdateCheckService();
      }

      if (!config.checkOnMobile &&
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)) {
        return const NoopUpdateCheckService();
      }

      final info = ref.watch(updateBuildInfoProvider).value;
      if (info == null) return const NoopUpdateCheckService();

      // Only NOW is a policy consulted, and it is a separate question from the
      // one above: `ManagedInstall` says the organization's tooling owns this
      // installation's version, `UpdatePolicy` says what the administrator
      // configured. A managed install has already returned.
      final policy = ref.watch(updatePolicyProvider);

      // Capture the sink NOW, at construction. The callback below fires after
      // the network fetch completes — by which point this provider's element
      // may already have been torn down. Reading through `ref` inside the
      // callback would then throw, and the status notifier would dutifully
      // convert that into "Couldn't check for updates" — the exact defect that
      // silently killed the WaveCrux updater in every build up to 0.2.0.
      final recordServerTime = ref.read(observedServerTimeSinkProvider);

      final service = HttpUpdateCheckService(
        // The on-prem mirror replaces the endpoint and nothing else: the
        // product name, timeouts and download targets stay the product's, so a
        // mirrored fleet sends the same `User-Agent` and lands on the same
        // download page as everyone else.
        config: policy.manifestUri == null
            ? config
            : config.copyWith(manifestUri: policy.manifestUri),
        currentVersion: info.version,
        osName: info.os,
        client: ref.watch(updateHttpClientProvider),
        onServerTimeObserved: recordServerTime,
      );

      // Unwrapped when nothing is configured, so the overwhelmingly common
      // case is the exact object graph it was before this existed.
      if (policy.isAbsent) return service;
      return PolicyConstrainedUpdateCheckService(
        inner: service,
        policy: policy,
      );
    }, name: 'updateCheckServiceProvider');
