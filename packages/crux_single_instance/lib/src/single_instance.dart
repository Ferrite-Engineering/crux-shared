// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_single_instance/src/file_mode.dart';
import 'package:crux_single_instance/src/link_policy.dart';
import 'package:crux_single_instance/src/protocol.dart';
import 'package:crux_single_instance/src/rendezvous.dart';

/// The outcome of [SingleInstance.claim].
sealed class SingleInstanceClaim {
  const SingleInstanceClaim();
}

/// This process is the running instance: links other launches receive arrive
/// on [links]. A link this process was itself launched with is not among
/// them; the caller opens that one.
final class SingleInstancePrimary extends SingleInstanceClaim {
  SingleInstancePrimary._(this._host);

  final _PrimaryHost _host;

  /// Links handed over by later launches, each one accepted by the policy.
  /// Single-subscription, and buffered until listened to, so a link that
  /// arrives during startup waits rather than being lost.
  Stream<String> get links => _host.links.stream;

  /// The address the running instance listens on: a Unix domain socket path
  /// or `127.0.0.1`, never anything wider.
  InternetAddress get address => _host.server.address;

  /// Stops listening, removes the socket and the advert, and releases the
  /// lock, so the next launch becomes the running instance. The process
  /// ending does the same, less tidily; calling this is optional.
  Future<void> close() => _host.close();
}

/// The link was handed to the running instance. The caller exits.
final class SingleInstanceDelivered extends SingleInstanceClaim {
  const SingleInstanceDelivered._();
}

/// Why a launch runs on its own.
enum SingleInstanceStandaloneReason {
  /// Another instance is running and this launch carried no link, so there
  /// was nothing to hand over: an ordinary second window.
  anotherInstanceRuns,

  /// This launch's link failed the policy. The caller opens it, so the
  /// application's own parser reports it to the user.
  linkRejected,

  /// Another instance holds the lock but did not take the link in time: it
  /// is busy, still starting, or not one this version can talk to.
  timedOut,

  /// No directory private to this user could be found or made, an
  /// application id that cannot name a file was given, or the socket path is
  /// too long for the platform.
  unavailable,

  /// Something failed unexpectedly while claiming.
  failed,
}

/// This launch runs on its own, as it would without this package. If it was
/// launched with a link, the caller opens it.
final class SingleInstanceStandalone extends SingleInstanceClaim {
  const SingleInstanceStandalone._(this.reason, [this.detail]);

  /// Why.
  final SingleInstanceStandaloneReason reason;

  /// The error behind [SingleInstanceStandaloneReason.failed], for a log.
  final String? detail;

  @override
  String toString() =>
      'SingleInstanceStandalone(${reason.name}'
      '${detail == null ? '' : ': $detail'})';
}

final RegExp _appIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._\-]{0,127}$');

/// Unix domain socket paths are limited to the `sun_path` field: 104 bytes on
/// Darwin and the BSDs, 108 on Linux, each including the terminating NUL.
const int _maxSocketPathBytes = 103;

/// Lock files this process holds. POSIX record locks do not conflict within
/// one process, and closing any descriptor for a file drops every lock the
/// process holds on it, so a second claim in the same process must be
/// answered from here and must never open the file.
final Set<String> _locksHeldHere = <String>{};

/// One link per desktop session: a launch that carries a link hands it to the
/// instance already running and exits, instead of opening a second window.
///
/// Call [claim] early in startup, before any window is shown:
///
/// ```dart
/// final claim = await SingleInstance(
///   appId: 'com.example.viewer',
///   policy: SingleInstanceLinkPolicy(schemes: const ['example']),
/// ).claim(link: linkFromCommandLine);
/// switch (claim) {
///   case SingleInstanceDelivered():
///     exit(0);
///   case SingleInstancePrimary(:final links):
///     links.listen(openLink);
///   case SingleInstanceStandalone():
///     break;
/// }
/// ```
///
/// The design, and what it trusts, is in this package's README.
class SingleInstance {
  /// Coordinates the instances of [appId], accepting links under [policy].
  ///
  /// [timeout] bounds how long a launch waits for a running instance to take
  /// its link. [directory], [transport] and [environment] replace what is
  /// otherwise read from the platform; they exist for tests.
  SingleInstance({
    required this.appId,
    required this.policy,
    this.timeout = const Duration(seconds: 3),
    this.directory,
    this.transport,
    this.environment,
  });

  /// The application id the rendezvous files are named for: letters, digits,
  /// `.`, `_` and `-`, as a reverse-DNS id is.
  final String appId;

  /// What a running instance accepts.
  final SingleInstanceLinkPolicy policy;

  /// How long a launch waits for a running instance to take its link.
  final Duration timeout;

  /// The rendezvous directory, in place of the platform's. Still made and
  /// checked private.
  final String? directory;

  /// The transport, in place of the platform's.
  final SingleInstanceTransport? transport;

  /// The environment the directory is resolved from, in place of the
  /// process's.
  final Map<String, String>? environment;

  /// The overhead a link line carries beyond the link: a proof and a space.
  static const int _linkLineOverhead = 65;

  /// Becomes the running instance, hands [link] to the one already running,
  /// or says why this launch runs on its own. Never throws.
  ///
  /// Without a [link], a launch never waits: it becomes the running instance
  /// when there is none, and runs on its own when there is.
  Future<SingleInstanceClaim> claim({String? link}) async {
    try {
      if (link != null && !policy.accepts(link)) {
        return const SingleInstanceStandalone._(
          SingleInstanceStandaloneReason.linkRejected,
        );
      }
      final rendezvous = _resolve();
      if (rendezvous == null) {
        return const SingleInstanceStandalone._(
          SingleInstanceStandaloneReason.unavailable,
        );
      }
      final deadline = DateTime.now().add(timeout);
      var pause = const Duration(milliseconds: 10);
      while (true) {
        final lock = await _tryLock(rendezvous.lockPath);
        if (lock != null) return await _becomePrimary(rendezvous, lock);
        if (link == null) {
          return const SingleInstanceStandalone._(
            SingleInstanceStandaloneReason.anotherInstanceRuns,
          );
        }
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        if (await _deliver(rendezvous, link, remaining)) {
          return const SingleInstanceDelivered._();
        }
        if (!DateTime.now().isBefore(deadline)) break;
        await Future<void>.delayed(pause);
        if (pause < const Duration(milliseconds: 100)) pause *= 2;
      }
      return const SingleInstanceStandalone._(
        SingleInstanceStandaloneReason.timedOut,
      );
    } on Object catch (e) {
      return SingleInstanceStandalone._(
        SingleInstanceStandaloneReason.failed,
        '$e',
      );
    }
  }

  SingleInstanceRendezvous? _resolve() {
    if (!_appIdPattern.hasMatch(appId)) return null;
    final isWindows = Platform.isWindows;
    final chosen =
        transport ??
        (isWindows
            ? SingleInstanceTransport.loopbackTcp
            : SingleInstanceTransport.unixSocket);
    if (chosen == SingleInstanceTransport.unixSocket && isWindows) {
      return null;
    }
    final resolved = resolveSingleInstanceDirectory(
      environment: environment ?? Platform.environment,
      isWindows: isWindows,
      override: directory,
    );
    if (resolved == null) return null;
    final rendezvous = SingleInstanceRendezvous(
      directory: resolved,
      appId: appId,
      transport: chosen,
    );
    if (chosen == SingleInstanceTransport.unixSocket &&
        utf8.encode(rendezvous.socketPath).length > _maxSocketPathBytes) {
      return null;
    }
    return rendezvous;
  }

  Future<RandomAccessFile?> _tryLock(String path) async {
    // Claimed before the first await, so two claims in one process cannot
    // both reach the file: the second would be granted the same lock.
    if (!_locksHeldHere.add(path)) return null;
    RandomAccessFile? file;
    try {
      file = await File(path).open(mode: FileMode.append);
      // Exclusive and non-blocking: a lock another process holds throws.
      await file.lock();
    } on Object {
      await file?.close();
      _locksHeldHere.remove(path);
      return null;
    }
    setPosixFileMode(path, 0x180); // 0o600
    return file;
  }

  Future<SingleInstanceClaim> _becomePrimary(
    SingleInstanceRendezvous rendezvous,
    RandomAccessFile lock,
  ) async {
    ServerSocket? server;
    try {
      // The lock was free, so whatever socket and advert are here belong to
      // an instance that has ended. Remove them before anything can read them.
      _deleteQuietly(rendezvous.advertPath);
      final InternetAddress address;
      if (rendezvous.transport == SingleInstanceTransport.unixSocket) {
        _deleteQuietly(rendezvous.socketPath);
        address = InternetAddress(
          rendezvous.socketPath,
          type: InternetAddressType.unix,
        );
      } else {
        address = InternetAddress.loopbackIPv4;
      }
      server = await ServerSocket.bind(address, 0);
      if (rendezvous.transport == SingleInstanceTransport.unixSocket) {
        setPosixFileMode(rendezvous.socketPath, 0x180); // 0o600
      }
      final token = generateSingleInstanceSecret();
      SingleInstanceAdvert(
        token: token,
        port: rendezvous.transport == SingleInstanceTransport.loopbackTcp
            ? server.port
            : null,
      ).write(rendezvous.advertPath);
      final host = _PrimaryHost(
        rendezvous: rendezvous,
        lock: lock,
        server: server,
        token: token,
        policy: policy,
      )..start();
      return SingleInstancePrimary._(host);
    } on Object catch (e) {
      await server?.close();
      await _releaseLock(rendezvous.lockPath, lock);
      return SingleInstanceStandalone._(
        SingleInstanceStandaloneReason.failed,
        '$e',
      );
    }
  }

  /// Hands [link] to the running instance. True only when it said it took
  /// it; any other outcome, including a running instance that cannot prove
  /// it holds the token, is false and the link is not sent.
  Future<bool> _deliver(
    SingleInstanceRendezvous rendezvous,
    String link,
    Duration remaining,
  ) async {
    final advert = SingleInstanceAdvert.read(rendezvous.advertPath);
    if (advert == null) return false;
    final InternetAddress address;
    final int port;
    if (rendezvous.transport == SingleInstanceTransport.unixSocket) {
      address = InternetAddress(
        rendezvous.socketPath,
        type: InternetAddressType.unix,
      );
      port = 0;
    } else {
      final advertised = advert.port;
      if (advertised == null) return false;
      address = InternetAddress.loopbackIPv4;
      port = advertised;
    }
    Socket? socket;
    BoundedLineReader? reader;
    try {
      socket = await Socket.connect(address, port, timeout: remaining);
      reader = BoundedLineReader(
        socket,
        maxBuffered: kSingleInstanceMaxHandshakeLine,
      );
      final clientNonce = generateSingleInstanceSecret();
      socket.write('$kSingleInstanceProtocol $clientNonce\n');
      final challenge = await reader
          .next(kSingleInstanceMaxHandshakeLine)
          .timeout(remaining);
      final parts = challenge.split(' ');
      if (parts.length != 2) return false;
      final [serverNonce, serverProof] = parts;
      if (!isSingleInstanceSecret(serverNonce)) return false;
      final expected = singleInstanceServerProof(
        token: advert.token,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
      );
      if (!singleInstanceConstantTimeEquals(serverProof, expected)) {
        // Whatever answered does not hold the token: not ours, so the link
        // is not sent to it.
        return false;
      }
      final clientProof = singleInstanceClientProof(
        token: advert.token,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        link: link,
      );
      socket.write('$clientProof $link\n');
      final answer = await reader
          .next(kSingleInstanceMaxHandshakeLine)
          .timeout(remaining);
      return answer == kSingleInstanceAccepted;
    } on Object {
      return false;
    } finally {
      await reader?.cancel();
      socket?.destroy();
    }
  }

  static int _maxLinkLine(SingleInstanceLinkPolicy policy) =>
      policy.maxLinkBytes + _linkLineOverhead;
}

Future<void> _releaseLock(String path, RandomAccessFile lock) async {
  try {
    await lock.unlock();
  } on Object {
    // Closing releases it as well.
  }
  try {
    await lock.close();
  } on Object {
    // Nothing more to release.
  }
  _locksHeldHere.remove(path);
}

void _deleteQuietly(String path) {
  try {
    final file = File(path);
    if (file.existsSync() ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      file.deleteSync();
    }
  } on FileSystemException {
    // Absent already, or not ours to remove; binding reports the latter.
  }
}

/// The running instance's listener.
class _PrimaryHost {
  _PrimaryHost({
    required this.rendezvous,
    required this.lock,
    required this.server,
    required this.token,
    required this.policy,
  });

  /// Connections served at once; more are closed on arrival.
  static const int maxConnections = 8;

  /// How long one connection may take from accept to answer.
  static const Duration connectionTimeout = Duration(seconds: 5);

  final SingleInstanceRendezvous rendezvous;
  final RandomAccessFile lock;
  final ServerSocket server;
  final String token;
  final SingleInstanceLinkPolicy policy;
  final StreamController<String> links = StreamController<String>();
  final Set<Socket> _open = <Socket>{};
  StreamSubscription<Socket>? _accepting;
  bool _closed = false;

  void start() {
    _accepting = server.listen(
      (socket) {
        if (_closed || _open.length >= maxConnections) {
          socket.destroy();
          return;
        }
        _open.add(socket);
        unawaited(_serve(socket));
      },
      onError: (Object _) {
        // An accept that failed delivers nothing; keep listening.
      },
    );
  }

  Future<void> _serve(Socket socket) async {
    final reader = BoundedLineReader(
      socket,
      maxBuffered: SingleInstance._maxLinkLine(policy) + 1,
    );
    var accepted = false;
    try {
      await () async {
        final hello = await reader.next(kSingleInstanceMaxHandshakeLine);
        final greeting = hello.split(' ');
        if (greeting.length != 2 ||
            greeting[0] != kSingleInstanceProtocol ||
            !isSingleInstanceSecret(greeting[1])) {
          return;
        }
        final clientNonce = greeting[1];
        final serverNonce = generateSingleInstanceSecret();
        final reply = reader.next(SingleInstance._maxLinkLine(policy));
        socket.write(
          '$serverNonce ${singleInstanceServerProof(
            token: token,
            clientNonce: clientNonce,
            serverNonce: serverNonce,
          )}\n',
        );
        final line = await reply;
        final space = line.indexOf(' ');
        if (space < 0) return;
        final proof = line.substring(0, space);
        final link = line.substring(space + 1);
        if (!isSingleInstanceProof(proof)) return;
        final expected = singleInstanceClientProof(
          token: token,
          clientNonce: clientNonce,
          serverNonce: serverNonce,
          link: link,
        );
        if (!singleInstanceConstantTimeEquals(proof, expected)) return;
        if (!policy.accepts(link)) return;
        accepted = true;
        if (!_closed) links.add(link);
      }().timeout(connectionTimeout);
    } on Object {
      // A malformed, oversized, slow or unauthenticated peer is refused.
    }
    try {
      socket.write(
        '${accepted ? kSingleInstanceAccepted : kSingleInstanceRefused}\n',
      );
      await socket.flush().timeout(const Duration(seconds: 1));
    } on Object {
      // The peer may already be gone.
    }
    await reader.cancel();
    socket.destroy();
    _open.remove(socket);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _accepting?.cancel();
    await server.close();
    for (final socket in _open.toList()) {
      socket.destroy();
    }
    _open.clear();
    if (rendezvous.transport == SingleInstanceTransport.unixSocket) {
      _deleteQuietly(rendezvous.socketPath);
    }
    _deleteQuietly(rendezvous.advertPath);
    await _releaseLock(rendezvous.lockPath, lock);
    // Not awaited: the returned future completes only once a listener has
    // seen the stream end, and nobody may be listening.
    unawaited(links.close());
  }
}
