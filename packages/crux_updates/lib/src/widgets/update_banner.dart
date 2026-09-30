// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_updates/src/models/update_status.dart';
import 'package:crux_updates/src/providers/update_seam_providers.dart';
import 'package:crux_updates/src/providers/update_status_provider.dart';
import 'package:crux_updates/src/widgets/update_available_banner.dart';
import 'package:crux_updates/src/widgets/update_banner_metrics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mounts the in-app update notification above the routed app content.
///
/// Watches [updateStatusProvider]: renders [child] unchanged while current /
/// checking / errored, and a non-intrusive [UpdateAvailableBanner] above
/// [child] when an update is available. "View Changes" opens the manifest's
/// changelog URL; "Update Now" opens the platform target resolved by
/// `CruxUpdateConfig.updateTargetFor` (download page on desktop/web, app store
/// on mobile) — there is no in-place download/relaunch. "Dismiss" hides the
/// strip until a *newer* version is offered; dismissal is unavailable when the
/// update is mandatory.
///
/// Re-checks on app resume through the gated auto-check path. Mount it inside
/// `MaterialApp` (so the host's localization delegates resolve) but above the
/// routed content — typically from `MaterialApp.builder`.
///
/// **Never renders on web.** A web app self-updates on deploy — a user is at
/// most one reload away from the latest build — so a "download the new version"
/// banner is meaningless there (it fires transiently around every release,
/// between the manifest bump and the web deploy / edge-cache expiry). The
/// update *check* itself still runs on web: its manifest fetch observes
/// `server_time`, which feeds the beta-expiry clock-tampering hardening.
class UpdateBanner extends ConsumerStatefulWidget {
  /// Creates the update-notification gate wrapping [child].
  const UpdateBanner({
    required this.child,
    this.metrics = const CruxUpdateBannerMetrics(),
    this.isWeb = kIsWeb,
    super.key,
  });

  /// The routed app content the banner wraps.
  final Widget child;

  /// Host-supplied touch-target, icon and font sizing for the strip.
  final CruxUpdateBannerMetrics metrics;

  /// Whether the running build is the web app (test seam; defaults to the
  /// real [kIsWeb]).
  final bool isWeb;

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner>
    with WidgetsBindingObserver {
  /// The version the user dismissed this session, or `null`. A newer available
  /// version clears the suppression (the equality check below no longer holds).
  String? _dismissedVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Re-run the gated auto-check on resume. Honors the auto-check setting; a
    // manual check is always available via the action.
    unawaited(ref.read(updateStatusProvider.notifier).runScheduledCheck());
  }

  void _open(Uri uri) {
    unawaited(ref.read(updateUrlLauncherProvider)(uri));
  }

  void _updateNow() {
    final config = ref.read(cruxUpdateConfigProvider);
    _open(
      config.updateTargetFor(Theme.of(context).platform, isWeb: widget.isWeb),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Web self-updates on reload — never show the download banner there.
    if (widget.isWeb) return widget.child;
    // No mobile guard is needed here: `updateCheckServiceProvider` already
    // returns a NoopUpdateCheckService on iOS/Android unless the product opts
    // in, so the status never reaches `available` on a default store build.
    final status = ref.watch(updateStatusProvider);
    if (status is! UpdateStatusAvailable) return widget.child;

    final info = status.info;
    if (!info.mandatory && info.version == _dismissedVersion) {
      return widget.child;
    }

    final changelogUrl = info.changelogUrl;
    final changelog = (changelogUrl == null || changelogUrl.isEmpty)
        ? null
        : Uri.tryParse(changelogUrl);

    return Column(
      children: [
        UpdateAvailableBanner(
          version: info.version,
          mandatory: info.mandatory,
          strings: ref.watch(cruxUpdateStringsProvider),
          metrics: widget.metrics,
          onUpdateNow: _updateNow,
          onViewChanges: changelog == null ? null : () => _open(changelog),
          onDismiss: info.mandatory
              ? null
              : () => setState(() => _dismissedVersion = info.version),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
