// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

// The closed vocabularies the Worker checks live in the Flutter-free
// `crux_telemetry_core`, so a headless binary sends from the same lists.
export 'package:crux_telemetry_core/crux_telemetry_core.dart'
    show
        kTelemetryFormFactors,
        kTelemetryLicenseTiers,
        kTelemetryOperatingSystems;

/// The running platform as an `os` slug.
String telemetryOsSlug() =>
    telemetryOsSlugFor(isWeb: kIsWeb, platform: defaultTargetPlatform);

/// [telemetryOsSlug] with its two inputs injected, so every branch is
/// reachable from a test on one host.
///
/// `kIsWeb` wins over [platform] because on web `defaultTargetPlatform`
/// reports the *emulated* host (a browser on a Mac says `macOS`), and the
/// question `os` answers is "which build is this", not "which OS is under the
/// browser". [TargetPlatform.fuchsia] — the one value with no slug — falls
/// back to `linux`, matching how the suite already treats it everywhere else.
String telemetryOsSlugFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'web';
  return switch (platform) {
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux || TargetPlatform.fuchsia => 'linux',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
  };
}
