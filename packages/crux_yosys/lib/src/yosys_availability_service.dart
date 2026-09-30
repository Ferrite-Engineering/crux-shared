// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/src/process_runner.dart';
import 'package:crux_yosys/src/yosys_availability.dart';

/// Resolves whether Yosys is available on the host and, when it is,
/// captures the version banner. The service is intentionally narrow: it
/// answers one question (`is yosys usable?`) and leaves elaboration to
/// the runner.
///
/// Designed for dependency injection: pass a fake [ProcessRunner] in
/// tests to avoid spawning real subprocesses. The optional
/// `executableNameOverride` lets the user pin a specific binary.
class YosysAvailabilityService {
  /// Creates a service.
  YosysAvailabilityService({
    ProcessRunner? runner,
    String? executableNameOverride,
    this.probeTimeout = defaultProbeTimeout,
  }) : _runner = runner ?? const DefaultProcessRunner(),
       _executableName = executableNameOverride ?? _defaultExecutableName();

  /// Default budget for `yosys -V`.
  ///
  /// A version banner is a sub-second operation on any healthy install, so
  /// this is generous. It exists for the unhealthy cases: a binary on a
  /// stalled network mount, or a wrapper script that blocks reading stdin.
  /// Without a bound, either one hangs the probe forever with the child
  /// never killed — and the probe usually runs at startup, so the hang is
  /// in front of the user before they have done anything.
  static const Duration defaultProbeTimeout = Duration(seconds: 10);

  /// How long [probe] waits for `yosys -V` before killing the subprocess
  /// and reporting the install unusable.
  final Duration probeTimeout;

  final ProcessRunner _runner;
  final String _executableName;

  /// Default executable name to invoke. Windows prefers `yosys.exe`;
  /// other platforms use the bare name (`PATH` resolution handles the
  /// rest).
  static String _defaultExecutableName() =>
      Platform.isWindows ? 'yosys.exe' : 'yosys';

  /// Probes the environment. Always returns a [YosysAvailability] —
  /// never throws, and never hangs — so callers can render a "Yosys not
  /// found" hint without try/catch noise.
  ///
  /// The subprocess is bounded by [probeTimeout]; a binary that never
  /// responds is killed and reported as unusable with
  /// [YosysUnavailableReason.probeTimedOut] rather than leaving the
  /// returned future pending forever.
  Future<YosysAvailability> probe() async {
    try {
      final result = await _runner.run(
        _executableName,
        const <String>['-V'],
        timeout: probeTimeout,
      );
      if (result.termination == ProcessTermination.timedOut) {
        return YosysAvailability.unusable(
          path: _executableName,
          reason: YosysUnavailableReason.probeTimedOut,
        );
      }
      if (result.exitCode != 0) {
        return YosysAvailability.unusable(
          path: _executableName,
          reason: YosysUnavailableReason.execFailed,
        );
      }
      final banner = _extractVersionBanner(result.stdout, result.stderr);
      if (banner == null) {
        return YosysAvailability.unusable(
          path: _executableName,
          reason: YosysUnavailableReason.bannerUnparsed,
        );
      }
      return YosysAvailability.available(
        executablePath: _executableName,
        versionString: banner,
      );
    } on ProcessException {
      return const YosysAvailability.notFound();
    }
  }

  /// Pulls the first non-empty line out of `yosys -V` output. Yosys
  /// writes the banner to stdout in current releases but historically
  /// has used stderr; we accept either.
  static String? _extractVersionBanner(String stdout, String stderr) {
    for (final source in <String>[stdout, stderr]) {
      for (final raw in source.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (line.toLowerCase().startsWith('yosys')) {
          return line;
        }
      }
    }
    return null;
  }
}
