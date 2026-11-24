// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/src/server.dart';

/// A client that speaks to one server, line by line, the way an agent host
/// does: to an [McpServer] in this process, or to a server binary over its
/// standard input and output.
class McpScriptedClient {
  McpScriptedClient._(
    this._input,
    Stream<List<int>> output,
    this._process, [
    this._onClose,
  ]) {
    _subscription = output
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _arrived,
          onDone: () {
            _ended = true;
            _flushWaiters();
          },
        );
  }

  /// A client of [server], served in this process.
  factory McpScriptedClient.inProcess(McpServer server) {
    final toServer = StreamController<List<int>>();
    final fromServer = StreamController<List<int>>();
    final served = server.serve(toServer.stream, fromServer.sink);
    return McpScriptedClient._(
      toServer.sink,
      fromServer.stream,
      null,
      () async {
        await toServer.close();
        await served;
        await fromServer.close();
      },
    );
  }

  /// A client of the server binary [executable] run with [arguments].
  /// What it writes on stderr is kept in [stderrLines].
  static Future<McpScriptedClient> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final client = McpScriptedClient._(process.stdin, process.stdout, process);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(client.stderrLines.add);
    return client;
  }

  final StreamSink<List<int>> _input;
  final Future<void> Function()? _onClose;
  final Process? _process;
  late final StreamSubscription<String> _subscription;
  final Queue<String> _lines = Queue<String>();
  final Queue<Completer<String?>> _waiters = Queue<Completer<String?>>();
  bool _ended = false;
  int _nextId = 1;

  /// What a server binary wrote on stderr, line by line.
  final List<String> stderrLines = <String>[];

  void _arrived(String line) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(line);
    } else {
      _lines.add(line);
    }
  }

  void _flushWaiters() {
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(null);
    }
  }

  /// Sends [line] and its newline.
  void send(String line) => _input.add(utf8.encode('$line\n'));

  /// Sends raw [bytes], as they are.
  void sendBytes(List<int> bytes) => _input.add(bytes);

  /// The next line the server writes, or null when its output ended first.
  /// Throws a [TimeoutException] after [timeout].
  Future<String?> next({Duration timeout = const Duration(seconds: 30)}) {
    if (_lines.isNotEmpty) return Future<String?>.value(_lines.removeFirst());
    if (_ended) return Future<String?>.value();
    final waiter = Completer<String?>();
    _waiters.add(waiter);
    return waiter.future.timeout(timeout);
  }

  /// Sends a request for [method] with [params] and returns the decoded
  /// answer, which must carry the request's id.
  Future<Map<String, Object?>> request(
    String method, [
    Object? params,
  ]) async {
    final id = _nextId++;
    send(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    final line = await next();
    if (line == null) throw StateError('the server ended without answering');
    final answer = jsonDecode(line);
    if (answer is! Map<String, Object?> || answer['id'] != id) {
      throw StateError('not the answer to request $id: $line');
    }
    return answer;
  }

  /// Ends the server's input and waits for it to finish. For a server
  /// binary, returns its exit code.
  Future<int?> close() async {
    await _input.close();
    final process = _process;
    int? code;
    if (process != null) {
      code = await process.exitCode;
    } else {
      await _onClose?.call();
    }
    await _subscription.cancel();
    return code;
  }
}
