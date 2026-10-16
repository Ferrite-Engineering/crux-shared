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
/// **On, because the privacy policy names the event.** It ships through the
/// same gate as every other event: consent, the Enterprise policy and the
/// beta condition still decide whether it is kept. Setting this to `false`
/// holds the event back in every build while the detector keeps its session
/// marker whenever measurement is on (so the logic and its tests still run):
/// no event is then constructed, buffered or handed to a telemetry service.
const bool kCruxUncleanShutdownEventEnabled = true;

/// Ends the process with exit [code], after marking this session's exit
/// clean.
///
/// The one way a product ends its own process: a Quit or Exit menu item, a
/// quit shortcut, a declined EULA, an expired build, a headless run that has
/// finished. `dart:io`'s `exit` ends the process without running any Dart, so
/// a session that quit through it left its marker behind and the next launch
/// recorded [kTelemetryUncleanShutdownEvent] for a normal quit. This removes
/// the marker of every started [TelemetryUncleanShutdownDetector] first, then
/// exits. `cruxAuditProcessExit` in `crux_guards` finds any direct `exit`
/// left in a product.
///
/// Quitting from the system (the Dock, an Apple Event, logout, closing the
/// last window) does not come here: it reaches Dart as an exit request,
/// which the detector answers on its own.
Never cruxExit([int code = 0]) {
  TelemetryUncleanShutdownDetector._markEveryCleanExit();
  (debugCruxExitOverride ?? exit)(code);
}

/// Replaces the process exit [cruxExit] ends with, so a test can watch a quit
/// without ending the test runner. It must throw (the type is `Never`); the
/// marker is already removed by the time it is called. Reset it to `null` in
/// the test's tear-down.
@visibleForTesting
Never Function(int code)? debugCruxExitOverride;

/// Signature of the probe that says whether another live process still holds
/// a session marker file's lock.
typedef TelemetrySessionMarkerProbe = bool Function(File marker);

/// Detects that the previous session ended without a clean exit and records
/// [kTelemetryUncleanShutdownEvent] once for it.
///
/// **How.** Each running session keeps a marker file,
/// `session.<pid>.running` in the application-support directory, and holds an
/// exclusive lock on it for its whole life. A clean exit releases and deletes
/// it. At the next launch, a marker that is still on disk and that no live
/// process holds belonged to a session that never reached its exit path: one
/// event is recorded, however many such markers there are, and they are
/// deleted. A marker another running instance still holds is left alone, so
/// a second window of the same product is not read as a crash of the first.
/// The operating system drops a dead process's lock, so no process id is ever
/// compared.
///
/// **Every orderly exit removes it.** There are two kinds, and both end in
/// [markCleanExit]:
///
/// - **The embedder asks.** Quitting from the system (an Apple Event, the
///   Dock, logout, closing the last window, `WM_CLOSE`, a GTK delete event)
///   reaches Dart as an exit request, which the listener [setMeasuring]
///   installs answers, and as the `detached` state. On macOS the request is
///   asynchronous: the app answers the system's quit with "cancel" and
///   terminates itself once Dart replies, so the request can arrive before
///   [setMeasuring] has found the directory. The listener is installed before
///   that lookup, and a clean exit seen first keeps [setMeasuring] from
///   claiming a marker at all.
/// - **The product ends the process itself.** A Quit or Exit item, a quit
///   shortcut, a declined EULA, an expired build or a finished headless run
///   calls `cruxExit`, never `dart:io`'s `exit`, which ends the process
///   without running any Dart. `cruxExit` removes the marker of every
///   detector in the process first. `cruxAuditProcessExit` in `crux_guards`
///   keeps a direct `exit` out of a product.
///
/// [markCleanExit] is idempotent and never throws, so a product may also call
/// it on a quit path of its own, before work that a second quit could cut
/// short.
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
/// **The marker exists only while usage measurement is on.** The marker is a
/// file on the user's device, and in the EEA, the UK, Switzerland and South
/// Korea storage on the device for measurement needs consent first, so the
/// detector keeps it only while the telemetry gate is open. The privacy
/// policy says so. `telemetryServiceProvider` tells the detector through
/// [setMeasuring] whenever the gate settles:
///
/// - **On**: the first call sweeps stale markers and records the event if
///   there were any; every call claims this session's marker if it has none.
/// - **Off**: the first call sweeps stale markers and records nothing; every
///   call deletes this session's marker if it has one. Turning measurement off
///   mid-session therefore removes the file at once, and turning it back on
///   claims a new one.
///
/// A stale marker can only exist if the session that left it had measurement
/// on, so the sweep at an "off" launch is clearing what an earlier "on"
/// session left behind, not recording anything about it.
///
/// **Gating.** The event goes to whichever `TelemetryService`
/// `telemetryServiceProvider` resolved, exactly like `app.uncaught_error`, and
/// is only ever constructed at a launch where measurement is on. In a build
/// that can never transmit (`kBetaPeriod` on, `TELEMETRY_DEV` off) no event is
/// constructed, and none is while [kCruxUncleanShutdownEventEnabled] is off.
class TelemetryUncleanShutdownDetector {
  /// Creates a detector.
  ///
  /// Every argument defaults to the production value; tests pass their own.
  ///
  /// Construction reads nothing from `dart:io`: the default instance is built
  /// on the first recorded event in every edition, the web included, where
  /// `pid` and every file API throw. The process id is read only when
  /// [setMeasuring] claims a marker, which an unsupported host never reaches.
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
       _processIdOverride = processId;

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
  final int? _processIdOverride;

  /// Read lazily: `pid` throws in a browser.
  int get _processId => _processIdOverride ?? pid;

  /// Whether the event may be recorded. See
  /// [kCruxUncleanShutdownEventEnabled].
  final bool eventEnabled;

  /// Whether this host and build run the detector at all: a desktop platform
  /// and not a debug build. When `false`, [setMeasuring] does nothing.
  final bool supported;

  /// Whether this build can never transmit, so no event is constructed. The
  /// marker still follows [setMeasuring].
  final bool inert;

  /// Whether [setMeasuring] installs the `AppLifecycleListener` that removes
  /// the marker on a clean exit. Tests that drive [markCleanExit] directly
  /// turn it off.
  final bool installLifecycleListener;

  /// Every detector that has started and not yet seen a clean exit.
  /// `cruxExit` ends them all; in production that is [instance] alone.
  static final Set<TelemetryUncleanShutdownDetector> _running =
      <TelemetryUncleanShutdownDetector>{};

  /// Calls [markCleanExit] on every detector that has started and not yet
  /// seen a clean exit. For [cruxExit], just before the process ends.
  static void _markEveryCleanExit() {
    for (final detector in List.of(_running)) {
      detector.markCleanExit();
    }
  }

  Future<bool>? _started;
  Future<void> _work = Future<void>.value();
  bool _began = false;
  bool _swept = false;
  bool _unclean = false;
  Directory? _directory;
  bool _exited = false;
  File? _marker;
  RandomAccessFile? _lock;
  AppLifecycleListener? _listener;
  TelemetryService? _service;
  TelemetryEvent? _unattached;

  /// Starts the detector for a session whose usage measurement is on:
  /// [setMeasuring] with `measuring: true`.
  ///
  /// For a host that keeps the marker itself, outside
  /// `telemetryServiceProvider`. Idempotent: every call after the first
  /// returns the first call's result. Completes with whether a previous
  /// session ended uncleanly, whether or not an event was recorded for it.
  /// Never throws.
  Future<bool> start() =>
      _started ??= setMeasuring(measuring: true).then((_) => _unclean);

  /// Tells the detector whether usage measurement is on, which is whether
  /// this session may keep a marker on the device.
  ///
  /// The first call checks for an unclean previous session: it deletes every
  /// stale marker, and records the event for them only when [measuring] is
  /// `true` and recording is allowed. Every call then claims this session's
  /// marker when [measuring] is `true` and it has none, or deletes it when
  /// [measuring] is `false` and it has one.
  ///
  /// Calls are applied in order, each after the previous one finishes. Does
  /// nothing on the web, off the desktop, in a debug build, or after a clean
  /// exit. Never throws.
  Future<void> setMeasuring({required bool measuring}) {
    // The web has no file and no process id, whatever a caller passed as
    // [supported]: inert there, with no file access and no listener.
    if (kIsWeb || !supported || _exited) return Future<void>.value();
    if (!_began) {
      _began = true;
      _running.add(this);
      // Listening comes first, and synchronously: an exit request that lands
      // while the directory lookup is in flight must still be seen, or the
      // marker claimed after it would outlive a session that ended cleanly.
      try {
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
      } on Object catch (_) {
        // Without a listener, `cruxExit` still removes the marker.
      }
    }
    return _work = _work.then((_) => _apply(measuring));
  }

  Future<void> _apply(bool measuring) async {
    if (_exited) return;
    try {
      final dir = _directory ??= await _directoryFactory();
      if (!_swept) {
        _swept = true;
        _unclean = _sweepStaleMarkers(dir);
        if (_unclean && measuring && eventEnabled && !inert) {
          _record(TelemetryEvent(kTelemetryUncleanShutdownEvent));
        }
      }
      // A clean exit while the directory was being found means this session
      // is already over: it is never marked as running.
      if (_exited) return;
      if (measuring) {
        if (_marker == null) _claimMarker(dir);
      } else {
        _releaseMarker();
      }
    } on Object catch (_) {
      // Swallowed by design: telemetry never throws into a launch.
    }
  }

  /// Removes this session's marker: the session ended cleanly.
  ///
  /// Called from the exit paths the detector listens to and by `cruxExit`;
  /// safe to call more than once, before [setMeasuring] (which then claims
  /// nothing), and from a product's own quit path. Never throws.
  ///
  /// Each step is attempted on its own, so a listener that fails to dispose
  /// still leaves the marker deleted. A marker whose delete fails is kept for
  /// a later call to retry.
  void markCleanExit() {
    _exited = true;
    final listener = _listener;
    _listener = null;
    try {
      listener?.dispose();
    } on Object catch (_) {
      // The marker below matters more than the listener.
    }
    if (_releaseMarker()) _running.remove(this);
  }

  /// Releases and deletes this session's marker, if it has one. Returns
  /// whether no marker is left. Never throws.
  ///
  /// The lock is released before the delete because Windows refuses to
  /// delete a file that is open, and a lock that fails to close still leaves
  /// the delete attempted.
  bool _releaseMarker() {
    final lock = _lock;
    _lock = null;
    try {
      lock?.closeSync();
    } on Object catch (_) {
      // Closing is only what lets Windows delete the file; try anyway.
    }
    final marker = _marker;
    if (marker == null) return true;
    try {
      if (marker.existsSync()) marker.deleteSync();
      _marker = null;
      return true;
    } on Object catch (_) {
      // A marker that cannot be removed reads as one unclean session next
      // launch; there is nothing better to do with the failure here.
      return false;
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

  /// This session's marker file, once [setMeasuring] has claimed it. Exposed
  /// for tests.
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
