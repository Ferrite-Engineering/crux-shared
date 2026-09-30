// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// The `os` slug the ingestion Worker accepts (`OPERATING_SYSTEMS`). A value
/// outside this set rejects the **whole batch** with a 400, so the derivation
/// below is closed by construction rather than by string formatting.
///
/// Note what this is *not*: `ApplicationBuildInfo.os` is a display string —
/// `macOS 15.0`, `Linux 6.8.0-generic` — built for the About box. Sending it
/// would fail the enum check on every platform, and on Linux it would also
/// smuggle a kernel build string into an envelope field, which is exactly the
/// class of free text the never-collect list rules out.
const List<String> kTelemetryOperatingSystems = <String>[
  'macos',
  'windows',
  'linux',
  'ios',
  'android',
  'web',
];

/// The `form_factor` buckets the Worker accepts (`FORM_FACTORS`).
///
/// Deriving the bucket is a **product** concern: each app already classifies
/// its own layout idiom (WaveCrux's `DeviceClass`, and each other product's
/// equivalent), and telemetry must report the idiom the app actually drew
/// rather than a second, disagreeing breakpoint set. Products bind
/// `telemetryFormFactorProvider`; this list is the vocabulary that binding must
/// land inside, asserted by each product's own derivation test.
///
/// `'vscode'` means **the app is running inside an editor host** — a VSCode
/// webview or a VSCode extension host — rather than a browser tab or a native
/// window. It is not a layout idiom like the other four, and that is the point:
/// an editor-hosted build is a distinct distribution channel (the Marketplace)
/// whose adoption has to be countable on its own.
///
/// Without it the bucket would be `'web'`, because `kIsWeb` is true inside a
/// webview. That single collapse would break two numbers at once: extension
/// adoption would be unmeasurable, and the `web`-vs-`desktop` split — which
/// exists to answer "does the web build earn its maintenance" — would silently
/// absorb extension traffic and read as fact forever after.
///
/// Editor-hosted builds keep reporting `os: 'web'`. That stays honest, and the
/// host OS is not worth a second mechanism to recover.
const List<String> kTelemetryFormFactors = <String>[
  'desktop',
  'phone',
  'tablet',
  'web',
  'vscode',
];

/// The tier names the Worker accepts (`LICENSE_TIERS`), asserted against
/// `LicenseTier` by the payload-contract test so a future tier cannot be added
/// to the enum without someone noticing the Worker would reject it.
const List<String> kTelemetryLicenseTiers = <String>[
  'openCore',
  'edu',
  'pro',
  'enterprise',
];

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
