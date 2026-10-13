// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:ui' show AppExitResponse, AppLifecycleState;

import 'package:crux_license/crux_license.dart' show kBetaPeriod;
import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:crux_telemetry/src/telemetry_endpoint.dart' show kTelemetryDev;
import 'package:crux_telemetry/src/telemetry_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

/// The event recorded at launch when the previous session of this product on
/// this machine ended without a clean exit.
///
/// Recorded by [TelemetryUncleanShutdownDetector] on behalf of every product,
/// never by a product call site, so each product's catalog lists it as a
/// shared event the way it lists `app.uncaught_error`. It carries no
/// properties: the envelope (product, platform, version, tier) is the whole
/// record.
const String kTelemetryUncleanShutdownEvent = 'app.unclean_shutdown';

/// Whether [kTelemetryUncleanShutdownEvent] may be recorded at all.
///
/// **Off until the privacy policy names the event.** While this is `false`
/// the detector still keeps its session marker (so the logic and its tests
/// run in every build), but no event is ever constructed, buffered or handed
/// to a telemetry service. Turning it on is this one line, in the release
/// whose privacy policy lists the event.
const bool kCruxUncleanShutdownEventEnabled = false;

/// Signature of the probe that says whether another live process still holds
/// a session marker file's lock.
typedef TelemetrySessionMarkerProbe = bool Function(File marker);

/// Detects that the previous session ended without a clean exit and records
/// [kTelemetryUncleanShutdownEvent] once for it.
///
/// **How.** Each running session keeps a marker file,
/// `session.<pid>.running` in the application-support directory, and holds an
/// exclusive lock on it for its whole life. A clean exit (the desktop quit
/// path, `AppLifecycleListener.onExitRequested`, or the `detached` state)
/// releases and deletes it. At the next launch, a marker that is still on
/// disk and that no live process holds belonged to a session that never
/// reached its exit path: one event is recorded, however many such markers
/// there are, and they are deleted. A marker another running instance still
/// holds is left alone, so a second window of the same product is not read as
/// a crash of the first. The operating system drops a dead process's lock, so
/// no process id is ever compared.
///
/// **What it cannot tell apart.** A native crash, an out-of-memory kill, a
/// force quit, a kill from a terminal, a power loss and an operating system
/// that shut down without asking the app all look the same: the marker was
/// never removed. The event counts sessions that did not end cleanly, not
/// crashes. A quit that another listener cancels after this one removed the
/// marker leaves the rest of that session unmarked, so the error is always an
/// under-count, never an over-count.
///
/// **Where it runs.** Desktop only: iOS and Android end backgrounded apps
/// routinely, which would read as crashes, and the web has no file. Never in
/// a debug build, where every hot restart and every stop from the IDE would
/// count.
///
/// **Gating.** The event goes to whichever `TelemetryService`
/// `telemetryServiceProvider` resolved, exactly like `app.uncaught_error`: the
/// live service records it, the pending one holds it until consent is known,
/// the no-op discards it. The marker is rotated either way, so a session with
/// telemetry off still leaves the next launch an accurate answer. In a build
/// that can never transmit (`kBetaPeriod` on, `TELEMETRY_DEV` off) no event is
/// constructed, and none is while [kCruxUncleanShutdownEventEnabled] is off.
class TelemetryUncleanShutdownDetector {
  /// Creates a detector.
  ///
  /// Every argument defaults to the production value; tests pass their own.
  TelemetryUncleanShutdownDetector({
    Future<Directory> Function()? directoryFactory,
    TelemetrySessionMarkerProbe? markerHeld,
    bool? eventEnabled,
    bool? supported,
    bool? inert,
    int? processId,
    this.installLifecycleListener = true,
  }) : _directoryFactory = directoryFactory ?? getApplicationSupportDirectory,
       _markerHeld = markerHeld ?? _markerHeldByLiveProcess,
       eventEnabled = eventEnabled ?? kCruxUncleanShutdownEventEnabled,
       supported = supported ?? _desktopReleaseBuild(),
       inert = inert ?? (kBetaPeriod && !kTelemetryDev),
       _processId = processId ?? pid;

  /// The process-wide detector `telemetryServiceProvider` attaches and
  /// starts. A session is a process, so there is one.
  static final TelemetryUncleanShutdownDetector instance =
      TelemetryUncleanShutdownDetector();

  /// Marker file name prefix; the full name is `session.<pid>.running`.
  static const String markerPrefix = 'session.';

  /// Marker file name suffix.
  static const String markerSuffix = '.running';

  final Future<Directory> Function() _directoryFactory;
  final TelemetrySessionMarkerProbe _markerHeld;
  final int _processId;

  /// Whether the event may be recorded. See
  /// [kCruxUncleanShutdownEventEnabled].
  final bool eventEnabled;

  /// Whether this host and build run the detector at all: a desktop platform
  /// and not a debug build. When `false`, [start] does nothing.
  final bool supported;

  /// Whether this build can never transmit, so no event is constructed. The
  /// marker is still kept.
  final bool inert;

  /// Whether [start] installs the `AppLifecycleListener` that removes the
  /// marker on a clean exit. Tests that drive [markCleanExit] directly turn
  /// it off.
  final bool installLifecycleListener;

  Future<bool>? _started;
  File? _marker;
  RandomAccessFile? _lock;
  AppLifecycleListener? _listener;
  TelemetryService? _service;
  TelemetryEvent? _unattached;

  /// Checks for an unclean previous session, records the event if there was
  /// one and recording is allowed, and marks this session as running.
  ///
  /// Idempotent: every call after the first returns the first call's result.
  /// Completes with whether a previous session ended uncleanly, whether or
  /// not an event was recorded for it. Never throws.
  Future<bool> start() => _started ??= _start();

  Future<bool> _start() async {
    if (!supported) return false;
    try {
      final dir = await _directoryFactory();
      final unclean = _sweepStaleMarkers(dir);
      _claimMarker(dir);
      if (installLifecycleListener) {
        _listener = AppLifecycleListener(
          onExitRequested: () async {
            markCleanExit();
            return AppExitResponse.exit;
          },
          onStateChange: (state) {
            if (state == AppLifecycleState.detached) markCleanExit();
          },
        );
      }
      if (unclean && eventEnabled && !inert) {
        _record(TelemetryEvent(kTelemetryUncleanShutdownEvent));
      }
      return unclean;
    } on Object catch (_) {
      // Swallowed by design: telemetry never throws into a launch.
      return false;
    }
  }

  /// Removes this session's marker: the session ended cleanly.
  ///
  /// Called from the exit paths [start] listens to; safe to call more than
  /// once, before [start], and from a product's own quit path.
  void markCleanExit() {
    try {
      _listener?.dispose();
      _listener = null;
      final lock = _lock;
      _lock = null;
      lock?.closeSync();
      final marker = _marker;
      _marker = null;
      if (marker != null && marker.existsSync()) marker.deleteSync();
    } on Object catch (_) {
      // A marker that cannot be removed reads as one unclean session next
      // launch; there is nothing better to do with the failure here.
    }
  }

  /// Routes the event to [service] from now on, handing it the one recorded
  /// before anything was attached.
  void attach(TelemetryService service) {
    try {
      _service = service;
      final waiting = _unattached;
      _unattached = null;
      if (waiting != null) service.record(waiting);
    } on Object catch (_) {
      // Swallowed by design.
    }
  }

  /// Stops routing to [service], if it is still the attached one.
  void detach(TelemetryService service) {
    if (identical(_service, service)) _service = null;
  }

  /// The event recorded while no service was attached, if any. Exposed for
  /// tests.
  @visibleForTesting
  TelemetryEvent? get unattached => _unattached;

  /// This session's marker file, once [start] has claimed it. Exposed for
  /// tests.
  @visibleForTesting
  File? get marker => _marker;

  void _record(TelemetryEvent event) {
    final service = _service;
    if (service == null) {
      _unattached = event;
    } else {
      service.record(event);
    }
  }

  /// Deletes every marker no live process holds and says whether there was
  /// one.
  bool _sweepStaleMarkers(Directory dir) {
    var unclean = false;
    if (!dir.existsSync()) return false;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(markerPrefix) || !name.endsWith(markerSuffix)) {
        continue;
      }
      if (_markerHeld(entity)) continue;
      unclean = true;
      try {
        entity.deleteSync();
      } on FileSystemException catch (_) {
        // Left for the next launch, which will count it again only if this
        // session also fails to exit cleanly.
      }
    }
    return unclean;
  }

  void _claimMarker(Directory dir) {
    dir.createSync(recursive: true);
    final marker = File(
      '${dir.path}${Platform.pathSeparator}'
      '$markerPrefix$_processId$markerSuffix',
    );
    final handle = marker.openSync(mode: FileMode.write)..lockSync();
    _marker = marker;
    _lock = handle;
  }
}

bool _desktopReleaseBuild() =>
    !kIsWeb &&
    !kDebugMode &&
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// Whether a live process holds [marker]'s lock: a non-blocking attempt to
/// take it fails exactly when one does.
bool _markerHeldByLiveProcess(File marker) {
  RandomAccessFile? handle;
  try {
    handle = marker.openSync(mode: FileMode.append)
      ..lockSync()
      ..unlockSync();
    return false;
  } on FileSystemException catch (_) {
    return true;
  } finally {
    try {
      handle?.closeSync();
    } on Object catch (_) {
      // Nothing to release.
    }
  }
}
