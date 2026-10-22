// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_single_instance/src/file_mode.dart';
import 'package:crux_single_instance/src/protocol.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// How the running instance listens.
enum SingleInstanceTransport {
  /// A Unix domain socket in the private rendezvous directory. The default
  /// everywhere but Windows: only a process that can enter the directory can
  /// reach it.
  unixSocket,

  /// A TCP socket on `127.0.0.1` with an ephemeral port, the default on
  /// Windows, where `dart:io` has no Unix domain sockets. Loopback is
  /// reachable by every local account, so the token in the rendezvous
  /// directory is what limits it to this user.
  loopbackTcp,
}

/// The name of the subdirectory the rendezvous files live in.
const String kSingleInstanceDirectoryName = 'crux-single-instance';

/// Permission bits for group and others; none may be set on the directory.
const int _groupOrOther = 0x3F; // 0o077

/// Resolves the private directory the rendezvous files live in, creating it,
/// or returns null when no directory private to this user can be had.
///
/// * **Windows:** `%LOCALAPPDATA%\crux-single-instance`. The user's profile
///   grants access to the user, `SYSTEM` and administrators only, and a
///   directory created inside it inherits that.
/// * **Elsewhere:** `$XDG_RUNTIME_DIR/crux-single-instance` when the session
///   has a runtime directory that is a directory with no group or other
///   permission bits, as the XDG Base Directory Specification requires; else
///   `${XDG_CACHE_HOME:-$HOME/.cache}/crux-single-instance`. Either way the
///   directory is set to `0700` and checked afterwards; one that still grants
///   group or other access is refused.
///
/// [override] replaces the location (for tests) and is held to the same
/// check.
String? resolveSingleInstanceDirectory({
  required Map<String, String> environment,
  required bool isWindows,
  String? override,
}) {
  if (override != null) {
    return _prepare(override, isWindows: isWindows);
  }
  if (isWindows) {
    final local = environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty || !p.windows.isAbsolute(local)) {
      return null;
    }
    return _prepare(
      p.windows.join(local, kSingleInstanceDirectoryName),
      isWindows: true,
    );
  }
  final runtime = environment['XDG_RUNTIME_DIR'];
  if (runtime != null && p.isAbsolute(runtime) && isPrivateDirectory(runtime)) {
    final dir = _prepare(
      p.join(runtime, kSingleInstanceDirectoryName),
      isWindows: false,
    );
    if (dir != null) return dir;
  }
  final cache = environment['XDG_CACHE_HOME'];
  final home = environment['HOME'];
  final String base;
  if (cache != null && p.isAbsolute(cache)) {
    base = cache;
  } else if (home != null && p.isAbsolute(home)) {
    base = p.join(home, '.cache');
  } else {
    return null;
  }
  return _prepare(p.join(base, kSingleInstanceDirectoryName), isWindows: false);
}

/// Whether [path] is a directory with no group or other permission bits.
@visibleForTesting
bool isPrivateDirectory(String path) {
  try {
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.directory &&
        stat.mode & _groupOrOther == 0;
  } on FileSystemException {
    return false;
  }
}

String? _prepare(String path, {required bool isWindows}) {
  try {
    Directory(path).createSync(recursive: true);
    if (isWindows) return path;
    setPosixFileMode(path, 0x1C0); // 0o700
    return isPrivateDirectory(path) ? path : null;
  } on FileSystemException {
    return null;
  }
}

/// The three files one application's instances meet at.
@immutable
class SingleInstanceRendezvous {
  /// The files for [appId] in [directory].
  const SingleInstanceRendezvous({
    required this.directory,
    required this.appId,
    required this.transport,
  });

  /// The private directory.
  final String directory;

  /// The application id the files are named for.
  final String appId;

  /// How the running instance listens.
  final SingleInstanceTransport transport;

  /// Held, with an exclusive lock, by the running instance for its lifetime.
  /// The operating system releases the lock when the process ends, however
  /// it ends, which is what makes a dead instance's files recognisably stale.
  String get lockPath => p.join(directory, '$appId.lock');

  /// The Unix domain socket, for [SingleInstanceTransport.unixSocket].
  String get socketPath => p.join(directory, '$appId.sock');

  /// The running instance's token, and its port for
  /// [SingleInstanceTransport.loopbackTcp].
  String get advertPath => p.join(directory, '$appId.json');
}

/// What the running instance publishes in
/// [SingleInstanceRendezvous.advertPath].
@immutable
class SingleInstanceAdvert {
  /// An advert carrying [token] and, over TCP, [port].
  const SingleInstanceAdvert({required this.token, this.port});

  /// The secret both sides prove they hold. Never sent on the socket.
  final String token;

  /// The loopback port, or null over a Unix domain socket.
  final int? port;

  /// The largest advert file read, in bytes.
  static const int maxBytes = 1024;

  /// The file's JSON text.
  String encode() => jsonEncode({
    'protocol': kSingleInstanceProtocol,
    'token': token,
    'port': ?port,
  });

  /// Reads the advert at [path], or null when it is absent, too large or not
  /// one this version wrote.
  static SingleInstanceAdvert? read(String path) {
    try {
      final file = File(path);
      if (file.lengthSync() > maxBytes) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['protocol'] != kSingleInstanceProtocol) return null;
      final token = decoded['token'];
      final port = decoded['port'];
      if (token is! String || !isSingleInstanceSecret(token)) return null;
      if (port != null && (port is! int || port <= 0 || port > 65535)) {
        return null;
      }
      return SingleInstanceAdvert(token: token, port: port as int?);
    } on Object {
      return null;
    }
  }

  /// Writes the advert to [path] so a reader sees the old file or the new
  /// one, never a part: a sibling is written, restricted to the owner, and
  /// renamed over it. The sibling is restricted before the token is written
  /// into it.
  void write(String path) {
    final temp = File('$path.$pid.tmp')..writeAsStringSync('');
    setPosixFileMode(temp.path, 0x180); // 0o600
    temp
      ..writeAsStringSync(encode(), flush: true)
      ..renameSync(path);
  }
}
