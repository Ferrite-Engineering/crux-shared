// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The scan runs every couple of seconds for the life of the process, on the
// isolate that started discovery — the UI isolate, in the products. The
// avoid_slow_async_io lint prefers the *Sync() calls, which hold that isolate
// for the whole system call; this file stays on the asynchronous API so the
// scan never does.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/src/cxp_auth_token.dart';
import 'package:crux_cxp/src/cxp_private_files.dart';
import 'package:crux_cxp/src/peer_identity.dart';
import 'package:crux_cxp/src/process_liveness.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The default cadence at which [CxpManifestWriter] refreshes `started_at`.
///
/// Exposed as a named constant because the discovery TTL is derived from it:
/// a peer that is alive rewrites its manifest every heartbeat, so a manifest
/// more than a few heartbeats stale is (absent a definitive pid-liveness
/// answer) presumed dead.
const Duration cxpDefaultManifestHeartbeat = Duration(seconds: 30);

/// The pretty-printer manifests are written with — `crux_io`'s, so a
/// manifest reads the same whichever writer produced it.
const JsonEncoder _manifestEncoder = JsonEncoder.withIndent('  ');

/// Snapshot of a CXP peer recovered from its manifest file on disk.
@immutable
class CxpPeerManifest {
  /// Creates a manifest snapshot.
  const CxpPeerManifest({
    required this.identity,
    required this.host,
    required this.port,
    required this.startedAt,
    required this.manifestPath,
    this.token,
  });

  /// Decodes a manifest from its JSON form. Throws [FormatException] on
  /// missing required fields, and on a field whose value is outside what
  /// the field can mean: a port off the TCP range, or a `started_at` that
  /// `DateTime` cannot represent.
  ///
  /// The range checks are what make this decoder **total over
  /// `FormatException`**. Without them a `started_at` past
  /// ±8640000000000000 reached `DateTime.fromMillisecondsSinceEpoch`, which
  /// raises `RangeError` — an `Error`, not an `Exception` — straight through
  /// every `on FormatException` a scanner puts around this call. The manifest
  /// directory is writable by any process running as the user, so an int
  /// that size is one 200-byte file away.
  factory CxpPeerManifest.fromJson({
    required Map<String, Object?> json,
    required String manifestPath,
  }) {
    final identityJson = json['identity'];
    if (identityJson is! Map<String, Object?> && identityJson is! Map) {
      throw const FormatException('CxpPeerManifest: missing "identity"');
    }
    final identityMap = identityJson is Map<String, Object?>
        ? identityJson
        : (identityJson! as Map).cast<String, Object?>();
    final host = json['host'];
    final port = json['port'];
    final startedAt = json['started_at'];
    if (host is! String) {
      throw const FormatException('CxpPeerManifest: missing "host"');
    }
    if (port is! int) {
      throw const FormatException('CxpPeerManifest: missing "port"');
    }
    if (port < 1 || port > 65535) {
      throw FormatException('CxpPeerManifest: "port" $port is not a TCP port');
    }
    if (startedAt is! int) {
      throw const FormatException('CxpPeerManifest: missing "started_at"');
    }
    if (startedAt < -maxEpochMillis || startedAt > maxEpochMillis) {
      throw FormatException(
        'CxpPeerManifest: "started_at" $startedAt is outside the '
        'representable range',
      );
    }
    final token = json['token'];
    return CxpPeerManifest(
      identity: PeerIdentity.fromJson(identityMap),
      host: host,
      port: port,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true),
      manifestPath: manifestPath,
      // Optional (wire 1.2): a pre-1.2 peer publishes none, and a dialler
      // then presents none, which a receiver that requires one refuses.
      token: token is String && token.isNotEmpty ? token : null,
    );
  }

  /// The largest magnitude `DateTime.fromMillisecondsSinceEpoch` accepts —
  /// the inclusive bound on a manifest's `started_at`. Measured: the
  /// constructor raises `RangeError` one past it in either direction.
  static const int maxEpochMillis = 8640000000000000;

  /// The peer's identity (peer ID, product, version, capabilities).
  final PeerIdentity identity;

  /// Host the peer is listening on (typically `127.0.0.1`).
  final String host;

  /// Port the peer's CXP server is bound to.
  final int port;

  /// UTC timestamp at which the peer wrote the manifest.
  final DateTime startedAt;

  /// Filesystem path the manifest was loaded from. Used for cleanup of
  /// stale manifests.
  final String manifestPath;

  /// The token a dialler must present in its `hello` to be accepted by
  /// this peer, or null when the manifest carries none (a pre-1.2 peer).
  /// See `cxpProcessAuthToken`.
  final String? token;

  /// JSON form suitable for writing to disk.
  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity.toJson(),
    'host': host,
    'port': port,
    'started_at': startedAt.millisecondsSinceEpoch,
    'token': ?token,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpPeerManifest &&
          other.identity == identity &&
          other.host == host &&
          other.port == port &&
          other.startedAt == startedAt &&
          other.token == token);

  @override
  int get hashCode => Object.hash(identity, host, port, startedAt, token);

  /// Deliberately omits [token]: this string reaches logs and event rows.
  @override
  String toString() =>
      'CxpPeerManifest(${identity.peerId} @ $host:$port, '
      'startedAt=$startedAt)';
}

/// Event emitted by [CxpDiscovery] as peers appear or vanish in the
/// manifest directory.
@immutable
class CxpDiscoveryEvent {
  /// Creates a discovery event.
  const CxpDiscoveryEvent({required this.added, required this.manifest});

  /// True for a new peer; false for a removed peer.
  final bool added;

  /// The manifest that appeared or disappeared.
  final CxpPeerManifest manifest;

  @override
  String toString() {
    final action = added ? 'added' : 'removed';
    return 'CxpDiscoveryEvent($action: $manifest)';
  }
}

/// Watches the CXP manifest directory and emits peer-presence events.
///
/// Each running CxpServer writes a manifest at
/// `${manifestDirectory}/<peer_id>.json` describing the peer's listening
/// host, port, and identity. The watcher periodically scans the directory
/// (debounced) so multiple sequential writes within the
/// [scanInterval] coalesce into a single event.
///
/// Stale-manifest pruning: any manifest whose `started_at` is older than
/// [staleThreshold] is treated as a dead peer and removed from the
/// watcher's view. Peers SHOULD refresh their manifest's `started_at`
/// timestamp every ~30 seconds (NOT enforced by this library — the
/// product that wires CXP into its app lifecycle owns the refresh
/// schedule).
///
/// ### Cost to the isolate that runs it
///
/// A scan holds its isolate only between one file operation and the next:
/// the listing, each manifest's read and each reap are asynchronous, and a
/// peer's pid is checked with a system call rather than a process launch.
/// Only regular files are read — a FIFO named like a manifest would block
/// any read of it until something wrote to it. A scan still running when
/// the next [scanInterval] tick falls due is left to finish, and that tick
/// is skipped rather than queued behind it.
class CxpDiscovery {
  /// Creates a discovery service rooted at [manifestDirectory].
  CxpDiscovery({
    required this.manifestDirectory,
    this.selfPeerId,
    this.scanInterval = const Duration(seconds: 2),
    this.staleThreshold = const Duration(minutes: 5),
    this.reapThreshold = const Duration(hours: 24),
    this.operatingSystemOverride,
  });

  /// Operating system used to select the pid-liveness probe. Injectable for
  /// tests; null (the default) uses the live `Platform.operatingSystem`.
  @visibleForTesting
  final String? operatingSystemOverride;

  /// Directory holding `<peer_id>.json` manifest files.
  final String manifestDirectory;

  /// This process's own peer ID, when known.
  ///
  /// A stale manifest matching this ID is deleted from disk *as soon as it
  /// is stale* — it should never be, since [CxpManifestWriter]'s heartbeat
  /// keeps our own file fresh, so a stale self-manifest is a leftover from a
  /// prior run and safe to remove at once. Every *other* peer's stale
  /// manifest is only pruned from this watcher's view, and reaped from disk
  /// far more conservatively — see [reapThreshold].
  ///
  /// Deleting other processes' files at [staleThreshold] once turned a
  /// laptop sleep into a spurious full cross-product disconnect: on wake
  /// every product's scan runs before any product's 30 s heartbeat, so all
  /// four apps deleted each other's manifests and every connector tore
  /// down every link. Leaving them alone until [reapThreshold] lets the
  /// owning process's next heartbeat re-freshen its own file.
  ///
  /// Null (the default) means this discovery owns nothing, so no manifest
  /// is deleted at [staleThreshold]; other peers' files are still reaped at
  /// [reapThreshold].
  final String? selfPeerId;

  /// How often the directory is rescanned.
  final Duration scanInterval;

  /// Manifests older than this are treated as dead peers and pruned from
  /// this watcher's view.
  final Duration staleThreshold;

  /// A stale *other-peer* manifest is deleted from disk once it is older
  /// than this — long past the point where a merely-asleep-but-alive peer
  /// would have re-freshened it on wake. This bounds on-disk manifest
  /// accumulation (resilience R9: `<peer_id>.json` files from dead sessions
  /// otherwise pile up, since every process start mints a fresh peer ID and
  /// so never overwrites a prior run's file) without reintroducing the
  /// on-wake mass-delete described in [selfPeerId]. Kept well above
  /// [staleThreshold] and any ordinary sleep window; the default is a day.
  final Duration reapThreshold;

  Timer? _timer;
  final Map<String, CxpPeerManifest> _known = <String, CxpPeerManifest>{};
  // Not `final`: [stop] closes the controller and [start] recreates it,
  // so a stop/start cycle yields a discovery that still emits.
  StreamController<CxpDiscoveryEvent> _events =
      StreamController<CxpDiscoveryEvent>.broadcast();
  var _running = false;

  /// Moved by every [start] and [stop]. A scan keeps the value it began
  /// under and, after each `await`, gives up if it has changed, so a scan
  /// still in flight when [stop] is called emits nothing, reaps nothing and
  /// leaves [peers] as they were — as if it had never begun, which is all a
  /// scan could be when scanning was synchronous.
  var _session = 0;

  /// The scan in progress, if any. A tick that finds one does nothing.
  Future<void>? _scanInFlight;

  /// Stream of discovery events.
  Stream<CxpDiscoveryEvent> get events => _events.stream;

  /// Snapshot of currently-known peers.
  List<CxpPeerManifest> get peers => List.unmodifiable(_known.values);

  /// Start watching the manifest directory.
  ///
  /// Completes once an initial scan has finished (emitting added events for
  /// any pre-existing manifests), so [peers] is current when it does, then
  /// continues scanning every [scanInterval].
  Future<void> start() async {
    if (_running) return;
    if (_events.isClosed) {
      _events = StreamController<CxpDiscoveryEvent>.broadcast();
      _known.clear();
    }
    _running = true;
    final session = ++_session;
    await _ensureDirectory();
    // Stopped while the directory was being made: no scan, and no timer
    // left running after the stop.
    if (session != _session) return;
    await _runScan(session);
    if (session != _session) return;
    _timer = Timer.periodic(scanInterval, (_) => _onTick(session));
  }

  /// Stop the periodic scan and close the events stream.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _session++;
    _timer?.cancel();
    _timer = null;
    await _events.close();
  }

  /// Creates the manifest directory when it is missing, owner-only — it
  /// holds every local peer's token (§10.1). See
  /// [ensureCxpPrivateDirectory].
  Future<void> _ensureDirectory() => ensureCxpPrivateDirectory(
    manifestDirectory,
  );

  /// A timer tick: scans, unless the previous scan has not finished.
  ///
  /// Skipping rather than queueing is what keeps a slow disk from stacking
  /// scans up — each would read the same files for the same answer — and
  /// keeps two scans from reaping the same file at once.
  void _onTick(int session) {
    if (_scanInFlight != null) return;
    unawaited(_runScan(session));
  }

  /// Runs one scan and marks it in flight until it completes.
  Future<void> _runScan(int session) {
    final scan = _scanGuarded(session);
    _scanInFlight = scan;
    return scan.whenComplete(() {
      // A scan abandoned by [stop] may finish after the next session's
      // first scan has begun; it must not clear that scan's mark.
      if (identical(_scanInFlight, scan)) _scanInFlight = null;
    });
  }

  /// One scan that cannot take the timer with it.
  ///
  /// Nothing awaits a scan a tick starts, so a throw from it would reach the
  /// zone as an unhandled error, and the timer fires again anyway: an
  /// exception that recurs every tick is an error dialog (or a log line)
  /// every two seconds for the life of the process, with discovery frozen
  /// underneath. [_scan] is written to be total — every per-file failure is
  /// contained inside the loop — so anything reaching here is a bug in the
  /// scan itself, and the honest response to a bug in a background sweep is
  /// to skip the tick, not to keep the bug and lose the sweep.
  Future<void> _scanGuarded(int session) async {
    try {
      await _scan(session);
    } on Object {
      // Next tick retries from scratch; nothing here is stateful across a
      // failed tick except _known, which the failed tick did not reach.
    }
  }

  Future<void> _scan(int session) async {
    // True once [stop] (and perhaps a new [start]) has come between this
    // scan and its next step.
    bool abandoned() => session != _session;
    final dir = Directory(manifestDirectory);
    if (!await dir.exists() || abandoned()) return;
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(staleThreshold);

    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      // The directory vanished or became unreadable between the existence
      // check and the listing. Nothing to scan this tick.
      return;
    }
    final found = <String, CxpPeerManifest>{};
    for (final entity in entries) {
      if (abandoned()) return;
      if (entity is! File) continue;
      // Atomic writes rename from a scratch file named
      // `<peer>.json.<micros>-<counter>.tmp` (see `writeStringAtomic`), so a
      // real orphan does NOT end in `.json.tmp` — it ends in `.tmp` with the
      // discriminator in between. Match any `.tmp`, or genuine orphans slip
      // through and accumulate. A live write's temp file is
      // younger than the cutoff and is left alone by [_sweepOrphanedTemp].
      if (entity.path.endsWith('.tmp')) {
        await _sweepOrphanedTemp(entity, cutoff, session);
        continue;
      }
      if (!entity.path.endsWith('.json')) continue;
      try {
        // A listing reports a FIFO, a socket or a device as a `File`. Opening
        // a FIFO for reading blocks until something writes to it, so one
        // named `*.json` would stall this scan — and, since a tick never
        // overlaps a running scan, every scan after it. (Read synchronously,
        // it froze the whole isolate.) Only a regular file can be a manifest.
        final stat = await entity.stat();
        if (abandoned()) return;
        if (stat.type != FileSystemEntityType.file) continue;
        final content = await entity.readAsString();
        if (abandoned()) return;
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, Object?> && decoded is! Map) continue;
        final manifestJson = decoded is Map<String, Object?>
            ? decoded
            : (decoded as Map).cast<String, Object?>();
        final manifest = CxpPeerManifest.fromJson(
          json: manifestJson,
          manifestPath: entity.path,
        );
        // (a) Definitive pid liveness: a manifest whose owning process is
        // provably gone is reaped at once — file and view — regardless of
        // owner or age. Unlike a stale timestamp (which a merely-asleep peer
        // also produces), a dead pid is unambiguous, so deleting a foreign
        // dead peer's file here is safe and does NOT re-arm the sleep/wake
        // mass-delete regression: an asleep peer's process is still alive, so
        // its liveness reads `alive`, never `dead`. Indeterminate liveness
        // (Windows, EPERM, unparseable pid) falls through to the TTL.
        //
        // The *current* self manifest is exempt: if this code is executing,
        // our own process is alive by construction, so a `dead` reading for
        // `selfPeerId` can only be a pid the OS has since recycled to another
        // process (or, in tests, a synthetic pid). Reaping our own live file
        // would erase us from every peer's discovery mid-run. A stale
        // *leftover* self file from a prior crashed session carries a
        // different peerId (an older pid) and is not `selfPeerId`, so it is
        // still reaped here.
        final isSelf =
            selfPeerId != null && manifest.identity.peerId == selfPeerId;
        if (!isSelf &&
            peerIdLiveness(
                  manifest.identity.peerId,
                  operatingSystem: operatingSystemOverride,
                ) ==
                PidLiveness.dead) {
          await _reapDeadManifest(entity);
          continue;
        }
        // (b) TTL fallback: prune from view unconditionally; delete from
        // disk only under the tighter rules in [_reapStaleManifest].
        if (manifest.startedAt.isBefore(cutoff)) {
          await _reapStaleManifest(entity, manifest, now);
          continue;
        }
        found[manifest.identity.peerId] = manifest;
      } on FileSystemException {
        // Raced with the owner's rename or delete; the file may be perfectly
        // good on the next tick, so it is never reaped from here.
        continue;
      } on Object {
        // Everything else — non-JSON bytes, a JSON array, a manifest whose
        // decoder threw, or a decoder that raised an Error rather than an
        // Exception — costs exactly this file and nothing after it.
        //
        // `on Object` and not `on FormatException` is the point. The typed
        // handler that used to stand here let a `RangeError` from
        // `CxpPeerManifest.fromJson` (a `started_at` past what `DateTime`
        // represents) abort the loop, and because the add/remove events and
        // the `_known` update sit after the loop, the abort did not lose one
        // peer — it froze discovery entirely: nothing new was ever added and
        // nothing gone was ever removed for as long as the bad file existed,
        // with the timer re-throwing every two seconds. The decoder is now
        // total over FormatException as well; the wide handler is what makes
        // the loop's own contract not depend on that staying true.
        await _reapUnparseable(entity, now, session);
        continue;
      }
    }
    if (abandoned()) return;

    _dedupeByIdentity(found);

    // Emit add events for new peers.
    for (final entry in found.entries) {
      if (!_known.containsKey(entry.key)) {
        if (!_events.isClosed) {
          _events.add(
            CxpDiscoveryEvent(added: true, manifest: entry.value),
          );
        }
      }
    }
    // Emit remove events for peers that vanished.
    for (final entry in _known.entries.toList(growable: false)) {
      if (!found.containsKey(entry.key)) {
        if (!_events.isClosed) {
          _events.add(
            CxpDiscoveryEvent(added: false, manifest: entry.value),
          );
        }
      }
    }
    _known
      ..clear()
      ..addAll(found);
  }

  /// Deletes a stale manifest from disk, conservatively.
  ///
  /// [_scan] has already dropped this manifest from the in-memory view;
  /// removing the *file* is a separate, tighter decision:
  ///
  ///  * Our own manifest ([selfPeerId]) goes as soon as it is stale — the
  ///    heartbeat should keep it fresh, so a stale self-manifest is a
  ///    leftover from a prior run.
  ///  * Any other peer's manifest is deleted only once it is older than
  ///    [reapThreshold] — far beyond any ordinary sleep, so a merely-asleep
  ///    peer's file (which its heartbeat re-freshens within seconds of
  ///    wake) is never reaped, yet dead sessions' files stop accumulating
  ///    (resilience R9). See [selfPeerId] for why the wider net is unsafe.
  ///
  /// Best-effort: another process may be writing or deleting the same path
  /// concurrently, so any failure is swallowed and never escapes the scan.
  Future<void> _reapStaleManifest(
    File entity,
    CxpPeerManifest manifest,
    DateTime now,
  ) async {
    final isSelf = manifest.identity.peerId == selfPeerId;
    if (!isSelf && !manifest.startedAt.isBefore(now.subtract(reapThreshold))) {
      return;
    }
    try {
      await entity.delete();
    } on FileSystemException {
      // Best effort — raced with the owning process's write/delete.
    }
  }

  /// Deletes a `.json` file that does not decode as a manifest, once it has
  /// sat unchanged for longer than [reapThreshold].
  ///
  /// An undecodable file has no `peer_id` to probe and no `started_at` to
  /// age, so neither of the two reaping paths above can ever retire it: left
  /// alone it is re-read and re-rejected on every tick by every product for
  /// the life of the directory. The mtime stands in for the heartbeat. The
  /// wait is the full [reapThreshold] (a day by default), far beyond any
  /// write a conforming peer could have in flight — the spec requires
  /// tmp-then-rename, so a half-written `.json` is already a violation —
  /// and long enough that a file a user is deliberately editing in place is
  /// not snatched away. Best-effort, as every reap here is.
  Future<void> _reapUnparseable(File entity, DateTime now, int session) async {
    try {
      final modified = await entity.lastModified();
      if (session != _session) return;
      if (modified.toUtc().isBefore(now.subtract(reapThreshold))) {
        await entity.delete();
      }
    } on FileSystemException {
      // Raced with a concurrent write or delete.
    }
  }

  /// Reaps a manifest whose owning process is provably dead.
  ///
  /// Called only when [pidLiveness] returned [PidLiveness.dead], which is a
  /// definitive answer (the local pid names no running process) rather than
  /// the merely-suggestive staleness of an old timestamp. That certainty is
  /// what makes it safe to delete a *foreign* peer's file here — the
  /// sleep/wake regression that [_reapStaleManifest] guards against cannot
  /// occur, because an asleep-but-alive peer's process still exists and so
  /// never reads as dead. Best-effort: a concurrent write/delete race is
  /// swallowed.
  Future<void> _reapDeadManifest(File entity) async {
    try {
      await entity.delete();
    } on FileSystemException {
      // Best effort — raced with the owning process's write/delete.
    }
  }

  /// Collapses manifests that name the same running endpoint down to one.
  ///
  /// Two live manifests advertising the same product on the same `host:port`
  /// cannot both be a distinct running peer — only one process can hold a
  /// listening socket — so a momentarily-doubled manifest (an old file that
  /// lingers while a restarted peer rebinds the same port, say) must not
  /// surface as two discovery rows. The newest `started_at` wins; the loser
  /// is dropped from the view (never deleted from disk here — reaping is the
  /// job of the liveness/TTL paths above).
  void _dedupeByIdentity(Map<String, CxpPeerManifest> found) {
    if (found.length < 2) return;
    final byEndpoint = <String, CxpPeerManifest>{};
    for (final manifest in found.values) {
      final key =
          '${manifest.identity.productName}|${manifest.host}|${manifest.port}';
      final existing = byEndpoint[key];
      if (existing == null || manifest.startedAt.isAfter(existing.startedAt)) {
        byEndpoint[key] = manifest;
      }
    }
    if (byEndpoint.length == found.length) return; // no duplicates
    final winners = byEndpoint.values.map((m) => m.identity.peerId).toSet();
    found.removeWhere((peerId, _) => !winners.contains(peerId));
  }

  /// Deletes a `<peer>.json.<micros>-<counter>.tmp` scratch file left behind
  /// when a manifest write succeeded but its rename did not.
  ///
  /// The rename that follows the temp write is effectively instantaneous,
  /// so a temp file older than [staleThreshold] cannot be a write in
  /// progress — it is an orphan, and nothing else ever swept them. Unlike
  /// manifests these are safe to delete regardless of owner: a live
  /// writer's temp file is always younger than the cutoff.
  Future<void> _sweepOrphanedTemp(
    File entity,
    DateTime cutoff,
    int session,
  ) async {
    try {
      final modified = await entity.lastModified();
      if (session != _session) return;
      if (modified.toUtc().isBefore(cutoff)) {
        await entity.delete();
      }
    } on FileSystemException {
      // Best effort — raced with the owning process's rename.
    }
  }
}

/// Writes a manifest file describing a running CxpServer.
///
/// Conventional location: `sharedCxpManifestDirectory()` (the suite-shared
/// `<user-app-data>/crux/cxp/peers/<peer_id>.json`), but the actual
/// directory is configurable so tests and embedded deployments can
/// sandbox their manifests.
///
/// ### Heartbeat
///
/// [CxpDiscovery] prunes (and deletes) any manifest whose `started_at` is
/// older than its `staleThreshold` (default 5 minutes) — so a live server
/// MUST refresh its manifest or every peer will drop it a few minutes
/// after launch. Historically this refresh was documented as the
/// product's responsibility and no product implemented it (the "peer
/// vanishes after 5 minutes" half of the suite cross-discovery defect).
/// The writer now owns it: after [write], the manifest is atomically
/// rewritten with a fresh `started_at` every [heartbeatInterval]
/// (default 30 s). Pass `heartbeatInterval: null` to disable (tests that
/// assert on a single write).
///
/// ### Permissions
///
/// The manifest carries this peer's token (§10.2), so on POSIX every write
/// keeps the manifest directory owner-only (`0700`, see
/// `ensureCxpPrivateDirectory`) and writes the manifest owner-only
/// (`0600`) — the scratch file is made `0600` before the token is written
/// into it. On Windows the user profile's access-control list does that
/// job and nothing is changed.
class CxpManifestWriter {
  /// Creates a writer that places manifests under [manifestDirectory].
  ///
  /// [authToken] is published in the manifest as the token diallers must
  /// present; it defaults to [cxpProcessAuthToken], which is also what
  /// `LocalCxpServer` requires by default, so a product that constructs
  /// both with defaults needs no wiring between them. Pass the server's
  /// `authToken` explicitly when it was given one.
  CxpManifestWriter({
    required this.manifestDirectory,
    this.heartbeatInterval = cxpDefaultManifestHeartbeat,
    String? authToken,
  }) : authToken = authToken ?? cxpProcessAuthToken;

  /// Directory holding the manifest file.
  final String manifestDirectory;

  /// Period between automatic `started_at` refreshes of the written
  /// manifest. Null disables the heartbeat.
  final Duration? heartbeatInterval;

  /// The token published in every manifest this writer writes.
  final String authToken;

  String? _filePath;
  Timer? _heartbeat;
  PeerIdentity? _identity;
  String? _host;
  int? _port;
  final Set<Future<void>> _writes = {};

  /// Write a manifest for the running [identity] on [host]:[port] and
  /// start the heartbeat (when enabled).
  ///
  /// Overwrites any existing manifest for the same peer.
  Future<void> write({
    required PeerIdentity identity,
    required String host,
    required int port,
  }) async {
    _identity = identity;
    _host = host;
    _port = port;
    await _writeOnce(identity: identity, host: host, port: port);
    _heartbeat?.cancel();
    final interval = heartbeatInterval;
    if (interval != null) {
      _heartbeat = Timer.periodic(interval, (_) => _refresh());
    }
  }

  Future<void> _writeOnce({
    required PeerIdentity identity,
    required String host,
    required int port,
  }) {
    final write = _writeManifest(identity: identity, host: host, port: port);
    _writes.add(write);
    return write.whenComplete(() => _writes.remove(write));
  }

  Future<void> _writeManifest({
    required PeerIdentity identity,
    required String host,
    required int port,
  }) async {
    // The directory is made (or kept) owner-only on every write, not only
    // when this writer creates it: an older build, or a product that made
    // it with default permissions, leaves it readable by other users, and
    // the token below is what they would read (§10.1–10.2).
    await ensureCxpPrivateDirectory(manifestDirectory);
    final path = p.join(manifestDirectory, '${identity.peerId}.json');
    final manifest = CxpPeerManifest(
      identity: identity,
      host: host,
      port: port,
      startedAt: DateTime.now().toUtc(),
      manifestPath: path,
      token: authToken,
    );
    // Owner-only from the moment the scratch file exists, before the token
    // is written into it, and renamed into place atomically (§10.2). No
    // `fsync`: a manifest is republished every [heartbeatInterval] and one
    // lost to a crash is regenerated by a process that had to restart
    // anyway — the reasoning `crux_io` names `WriteDurability.ephemeral`.
    await writeCxpPrivateFileAtomic(
      File(path),
      _manifestEncoder.convert(manifest.toJson()),
    );
    _filePath = path;
  }

  void _refresh() {
    final identity = _identity;
    final host = _host;
    final port = _port;
    // Removed (or never written) — nothing to refresh.
    if (identity == null || host == null || port == null) return;
    unawaited(
      _writeOnce(identity: identity, host: host, port: port).catchError((
        Object _,
      ) {
        // Best effort — a failed refresh is retried on the next tick, and
        // a persistently unwritable directory degrades to the pre-heartbeat
        // behavior (peers prune us at their staleThreshold).
      }),
    );
  }

  /// Remove the manifest file written by the most recent [write] and stop
  /// the heartbeat.
  ///
  /// This is the **clean-shutdown hook**: a product MUST call it (or
  /// [dispose]) as it exits so its own manifest never lingers for peers to
  /// re-dial. A crash that skips it is still handled — peers reap the
  /// orphaned manifest by pid-liveness (immediately, once they scan) or by
  /// the TTL — but a clean exit should not lean on that.
  ///
  /// Writes already in flight are waited out before the delete: otherwise a
  /// heartbeat's rename lands after it and republishes the manifest of a
  /// peer that has gone.
  Future<void> remove() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _identity = null;
    _host = null;
    _port = null;
    await Future.wait([
      for (final write in _writes) write.catchError((Object _) {}),
    ]);
    final path = _filePath;
    if (path == null) return;
    final file = File(path);
    if (file.existsSync()) {
      try {
        await file.delete();
      } on FileSystemException {
        // Best effort.
      }
    }
    _filePath = null;
  }

  /// Alias for [remove], named to match the dispose/close convention used
  /// across the suite's lifecycle-owning objects. Idempotent.
  Future<void> dispose() => remove();
}
