// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The result of probing the environment for a usable Yosys installation.
///
/// Produced by `YosysAvailabilityService` and consumed by the
/// elaboration pipeline. A [YosysAvailability] with [isAvailable] false
/// carries an [unavailableReason] explaining what to surface in the UI.
@immutable
class YosysAvailability {
  /// Creates an `available` availability record.
  const YosysAvailability.available({
    required this.executablePath,
    required this.versionString,
  }) : isAvailable = true,
       unavailableReason = null;

  /// Creates a not-found record.
  const YosysAvailability.notFound({String? reason})
    : isAvailable = false,
      executablePath = null,
      versionString = null,
      unavailableReason = reason ?? YosysUnavailableReason.notOnPath;

  /// Creates a found-but-broken record (the binary exists but `yosys -V`
  /// failed or returned an unparseable banner).
  const YosysAvailability.unusable({
    required String path,
    String? reason,
  }) : isAvailable = false,
       executablePath = path,
       versionString = null,
       unavailableReason = reason ?? YosysUnavailableReason.execFailed;

  /// True when a Yosys binary was located and successfully reported a
  /// version banner.
  final bool isAvailable;

  /// Absolute path of the Yosys executable when [isAvailable] is true, or
  /// the located-but-unusable binary when an exec attempt failed.
  final String? executablePath;

  /// Free-form version banner reported by `yosys -V`, e.g.
  /// `Yosys 0.50+1 (git sha1 ..., ...)`. `null` when [isAvailable] is
  /// false.
  final String? versionString;

  /// When [isAvailable] is false, a structured reason an i18n layer can
  /// translate into install instructions.
  final String? unavailableReason;
}

/// Stable string codes used as values of
/// [YosysAvailability.unavailableReason]. Not an enum so that the same
/// values can be persisted into JSON / shown in diagnostics reports
/// without a separate serialization layer.
abstract class YosysUnavailableReason {
  /// `yosys` was not present on `PATH`.
  static const String notOnPath = 'not_on_path';

  /// A Yosys binary was located but `yosys -V` failed (non-zero exit,
  /// missing shared library, sandbox denial, etc.).
  static const String execFailed = 'exec_failed';

  /// `yosys -V` succeeded but the banner could not be parsed.
  static const String bannerUnparsed = 'banner_unparsed';

  /// `yosys -V` did not respond within the probe budget and the
  /// subprocess was killed. Typically a binary on a stalled network mount
  /// or a wrapper script blocked reading stdin.
  static const String probeTimedOut = 'probe_timed_out';
}
