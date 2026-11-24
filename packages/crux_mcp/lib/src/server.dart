// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/src/confinement.dart';
import 'package:crux_mcp/src/document.dart';
import 'package:crux_mcp/src/json_writer.dart';
import 'package:crux_mcp/src/line_reader.dart';
import 'package:crux_mcp/src/protocol.dart';
import 'package:crux_mcp/src/result.dart';
import 'package:crux_mcp/src/telemetry.dart';
import 'package:crux_mcp/src/tool.dart';

/// One call of a tool, as the product's runner receives it.
class McpCall {
  McpCall._(this.tool, this.arguments, this._progress);

  /// The tool called.
  final McpTool tool;

  /// Its checked arguments: [McpArguments.argv] is the command line to run.
  final McpArguments arguments;

  final void Function(num progress, num? total, String? message)? _progress;

  final Completer<void> _cancelled = Completer<void>();

  /// Whether the client cancelled the call. Its result is dropped, so a
  /// runner may stop early.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when the client cancels the call.
  Future<void> get whenCancelled => _cancelled.future;

  /// Reports progress, when the client asked for it with a progress token;
  /// otherwise does nothing.
  void progress(num progress, {num? total, String? message}) =>
      _progress?.call(progress, total, message);

  void _cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Runs a tool's command in process, from the same code the command line
/// runs, and returns what `--json` writes.
typedef McpCommandRunner = Future<McpCommandOutput> Function(McpCall call);

/// A Model Context Protocol server on stdio: newline-delimited JSON-RPC 2.0,
/// one message per line, the methods `initialize`, `ping`, `tools/list` and
/// `tools/call`, and the notification `notifications/cancelled`.
///
/// - A line past [kMcpMaxLineBytes] is answered [kJsonRpcInvalidRequest]
///   with an `id` of null; a line that is not JSON [kJsonRpcParseError]; a
///   line that is not one object, or names no method,
///   [kJsonRpcInvalidRequest]; an unknown method [kJsonRpcMethodNotFound];
///   an unknown tool, or a `tools/call` with no name,
///   [kJsonRpcInvalidParams]. Other notifications are accepted and not
///   answered.
/// - A tool result's `content[0]` is the command's `--json` document
///   unchanged, and `isError` follows its outcome. A bad argument (an
///   unknown field, a wrong type, a missing required field, a path outside
///   the root) is a `usage_error` document, and nothing is run.
/// - Requests are answered in the order they arrive. A cancelled call that
///   has not started is never run, and one that has is not answered.
/// - The output carries nothing but the protocol: a `print` from a runner
///   goes to the `log` the constructor takes (stderr unless given).
class McpServer {
  /// A server for [program] holding [tools], whose paths stay inside
  /// [confinement], running each call through [runner].
  ///
  /// Throws an [ArgumentError] when [instructions] is empty or longer than
  /// [kMcpMaxInstructionsLength], or two tools share a name.
  McpServer({
    required this.program,
    required this.instructions,
    required List<McpTool> tools,
    required this.confinement,
    required this.runner,
    this.telemetry,
    void Function(String line)? log,
  }) : tools = List<McpTool>.unmodifiable(tools),
       _log = log ?? stderr.writeln {
    if (instructions.isEmpty ||
        instructions.length > kMcpMaxInstructionsLength) {
      throw ArgumentError.value(
        instructions.length,
        'instructions',
        'between 1 and $kMcpMaxInstructionsLength characters',
      );
    }
    final names = <String>{};
    for (final tool in tools) {
      if (!names.add(tool.name)) {
        throw ArgumentError.value(tool.name, 'tools', 'listed twice');
      }
    }
  }

  /// The program serving: `serverInfo`, and every document's `tool`.
  final McpProgram program;

  /// The paragraph `initialize` returns: when to call this server and to
  /// cite with links. Counts against the definition budget.
  final String instructions;

  /// The tools served, in listing order.
  final List<McpTool> tools;

  /// Where every path argument must stay.
  final Confinement confinement;

  /// Runs a call.
  final McpCommandRunner runner;

  /// Counts calls, when the product counts them.
  final McpTelemetry? telemetry;

  final void Function(String line) _log;

  /// The definitions `tools/list` returns.
  List<Map<String, Object?>> definitions() => <Map<String, Object?>>[
    for (final tool in tools) tool.definition(),
  ];

  /// Reads requests from [input] until it ends and writes each answer to
  /// [output] as one line. Completes when the input has ended, every request
  /// read has been answered, and the [telemetry]'s `close` has finished.
  Future<void> serve(Stream<List<int>> input, StreamSink<List<int>> output) {
    final done = Completer<void>();
    var queue = Future<void>.value();
    // Requests read and not yet started, and calls running, by their id.
    final queued = <String>{};
    final calls = <String, McpCall>{};
    final cancelledEarly = <String>{};

    void write(String line) => output.add(utf8.encode('$line\n'));

    mcpReadLines(input).listen(
      (line) {
        final Object? request;
        switch (line) {
          case McpRefusedLine(:final tooLong):
            final reply = tooLong
                ? _error(null, kJsonRpcInvalidRequest, 'request line too long')
                : _error(null, kJsonRpcParseError, 'parse error');
            queue = queue.then((_) => write(reply));
            return;
          case McpTextLine(:final text):
            final trimmed = text.trim();
            if (trimmed.isEmpty) return;
            try {
              request = jsonDecode(trimmed);
            } on FormatException {
              final reply = _error(null, kJsonRpcParseError, 'parse error');
              queue = queue.then((_) => write(reply));
              return;
            }
        }
        if (request is Map<String, Object?> &&
            !request.containsKey('id') &&
            request['method'] == 'notifications/cancelled') {
          final params = request['params'];
          if (params is Map<String, Object?> &&
              params.containsKey('requestId')) {
            final key = jsonEncode(params['requestId']);
            final call = calls[key];
            if (call != null) {
              call._cancel();
            } else if (queued.contains(key)) {
              cancelledEarly.add(key);
            }
          }
          return;
        }
        final key = request is Map<String, Object?> && request.containsKey('id')
            ? jsonEncode(request['id'])
            : null;
        if (key != null) queued.add(key);
        queue = queue.then((_) async {
          String? reply;
          try {
            reply = await _handle(
              request,
              write: write,
              register: (key, call) {
                calls[key] = call;
                queued.remove(key);
                if (cancelledEarly.remove(key)) call._cancel();
              },
              unregister: calls.remove,
            );
          } on Object catch (error, stack) {
            _log('${program.name} mcp: $error\n$stack');
            final id = request is Map<String, Object?> ? request['id'] : null;
            reply = _error(id, kJsonRpcInternalError, 'internal error');
          }
          if (key != null) {
            queued.remove(key);
            cancelledEarly.remove(key);
          }
          if (reply != null) write(reply);
        });
      },
      onError: (Object error) {
        _log('mcp: the input failed: $error');
      },
      onDone: () {
        unawaited(
          queue.whenComplete(() async {
            try {
              await telemetry?.close?.call();
            } on Object catch (error) {
              _log('${program.name} mcp: telemetry: $error');
            }
            done.complete();
          }),
        );
      },
      cancelOnError: true,
    );
    return done.future;
  }

  /// The answer to one request line, or null for a notification. For tests
  /// and for a host that frames messages itself.
  Future<String?> handleLine(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final Object? request;
    try {
      request = jsonDecode(trimmed);
    } on FormatException {
      return _error(null, kJsonRpcParseError, 'parse error');
    }
    return await _handle(request);
  }

  Future<String?> _handle(
    Object? request, {
    void Function(String line)? write,
    void Function(String key, McpCall call)? register,
    void Function(String key)? unregister,
  }) async {
    if (request is! Map<String, Object?>) {
      return _error(null, kJsonRpcInvalidRequest, 'a request is one object');
    }
    if (!request.containsKey('id')) return null;
    final id = request['id'];
    final method = request['method'];
    if (method is! String) {
      return _error(id, kJsonRpcInvalidRequest, 'no method');
    }
    final params = request['params'];
    switch (method) {
      case 'initialize':
        return _result(id, _initialize(params));
      case 'ping':
        return _result(id, const <String, Object?>{});
      case 'tools/list':
        return _result(id, <String, Object?>{'tools': definitions()});
      case 'tools/call':
        return await _call(id, params, write, register, unregister);
      default:
        return _error(id, kJsonRpcMethodNotFound, 'method not found: $method');
    }
  }

  Map<String, Object?> _initialize(Object? params) {
    final asked = params is Map<String, Object?>
        ? params['protocolVersion']
        : null;
    final version = kMcpProtocolVersions.contains(asked)
        ? asked! as String
        : kMcpProtocolVersions.first;
    return <String, Object?>{
      'protocolVersion': version,
      'capabilities': <String, Object?>{'tools': <String, Object?>{}},
      'serverInfo': program.toJson(),
      'instructions': instructions,
    };
  }

  Future<String?> _call(
    Object? id,
    Object? params,
    void Function(String line)? write,
    void Function(String key, McpCall call)? register,
    void Function(String key)? unregister,
  ) async {
    final name = params is Map<String, Object?> ? params['name'] : null;
    if (name is! String) {
      return _error(id, kJsonRpcInvalidParams, 'tools/call needs a tool name');
    }
    McpTool? tool;
    for (final t in tools) {
      if (t.name == name) tool = t;
    }
    if (tool == null) {
      return _error(id, kJsonRpcInvalidParams, 'unknown tool `$name`');
    }
    final watch = Stopwatch()..start();
    final asked = params! as Map<String, Object?>;
    final output = await _run(tool, asked['arguments'], asked, write, (call) {
      register?.call(jsonEncode(id), call);
    });
    unregister?.call(jsonEncode(id));
    if (output is _Cancelled) return null;
    telemetry?.toolCalled(
      tool: tool.name,
      outcome: switch (output) {
        null => 'crashed',
        McpCommandOutput(outcome: final o?) => o.wireName,
        McpCommandOutput() => 'unreadable',
      },
      elapsed: watch.elapsed,
    );
    if (output == null) {
      return _error(id, kJsonRpcInternalError, 'internal error in $name');
    }
    return _result(id, output.toToolResult());
  }

  /// The command's output for one call; null when the runner threw.
  Future<McpCommandOutput?> _run(
    McpTool tool,
    Object? arguments,
    Map<String, Object?> params,
    void Function(String line)? write,
    void Function(McpCall call) register,
  ) async {
    McpCommandOutput usage(String message) => McpCommandOutput.document(
      McpDocument.usage(tool: program, command: tool.name, message: message),
    );
    final checked = tool.check(arguments, confinement);
    final McpArguments args;
    switch (checked) {
      case McpArgumentError(:final message):
        return usage(message);
      case final McpArguments a:
        args = a;
    }
    final namedCheck = tool.checkNamedFiles;
    if (namedCheck != null) {
      final refused = await namedCheck(args, confinement);
      if (refused != null) return usage(refused.message);
    }
    final meta = params['_meta'];
    final token = meta is Map<String, Object?> ? meta['progressToken'] : null;
    final call = McpCall._(
      tool,
      args,
      token == null || write == null
          ? null
          : (progress, total, message) => write(
              mcpRenderJsonLine(<String, Object?>{
                'jsonrpc': '2.0',
                'method': 'notifications/progress',
                'params': <String, Object?>{
                  'progressToken': token,
                  'progress': progress,
                  'total': ?total,
                  'message': ?message,
                },
              }),
            ),
    );
    register(call);
    if (call.isCancelled) return _Cancelled();
    try {
      final output = await runZoned(
        () => runner(call),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => _log(line),
        ),
      );
      return call.isCancelled ? _Cancelled() : output;
    } on Object catch (error, stack) {
      _log('${program.name} mcp: ${tool.name} failed: $error\n$stack');
      return call.isCancelled ? _Cancelled() : null;
    }
  }

  static String _result(Object? id, Object? result) =>
      mcpRenderJsonLine(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });

  static String _error(Object? id, int code, String message) =>
      mcpRenderJsonLine(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      });
}

/// The output of a call the client cancelled: never answered.
class _Cancelled extends McpCommandOutput {
  _Cancelled() : super.text('');
}
