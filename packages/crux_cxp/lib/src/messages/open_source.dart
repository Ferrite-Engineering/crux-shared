// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:meta/meta.dart';

/// Peer asks another to open a source-code location in the configured
/// editor.
///
/// The recipient SHOULD shell out to its configured editor command
/// (`code -g`, `subl`, `nvr`, `emacsclient`, …) and reply with
/// [RequestOpenSourceAck]. Receivers without an editor configured
/// SHOULD ack with `honored: false` and a reason rather than ignoring
/// the request.
@immutable
class RequestOpenSource extends CxpMessage {
  /// Creates a RequestOpenSource.
  const RequestOpenSource({
    required this.filePath,
    required this.line,
    this.column,
  });

  /// Decodes a [RequestOpenSource] from its JSON payload.
  factory RequestOpenSource.fromJson(Map<String, Object?> json) {
    final filePath = json['file_path'];
    final line = json['line'];
    if (filePath is! String) {
      throw const FormatException(
        'RequestOpenSource.fromJson: missing "file_path"',
      );
    }
    if (line is! int) {
      throw const FormatException(
        'RequestOpenSource.fromJson: missing "line"',
      );
    }
    final column = json['column'];
    return RequestOpenSource(
      filePath: filePath,
      line: line,
      column: column is int ? column : null,
    );
  }

  /// Absolute or workspace-relative file path the recipient should open.
  final String filePath;

  /// 1-based line number.
  final int line;

  /// Optional 1-based column number.
  final int? column;

  @override
  String get kind => CxpMessageKind.requestOpenSource;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'file_path': filePath,
    'line': line,
    'column': ?column,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestOpenSource &&
          other.filePath == filePath &&
          other.line == line &&
          other.column == column);

  @override
  int get hashCode => Object.hash(filePath, line, column);

  @override
  String toString() =>
      'RequestOpenSource($filePath:$line${column == null ? '' : ':$column'})';
}

/// Acknowledgment of a [RequestOpenSource].
@immutable
class RequestOpenSourceAck extends CxpMessage {
  /// Creates a RequestOpenSourceAck.
  const RequestOpenSourceAck({
    required this.inReplyTo,
    required this.honored,
    this.reason,
  });

  /// Decodes a [RequestOpenSourceAck] from its JSON payload.
  factory RequestOpenSourceAck.fromJson(Map<String, Object?> json) {
    final inReplyTo = json['in_reply_to'];
    final honored = json['honored'];
    if (inReplyTo is! String) {
      throw const FormatException(
        'RequestOpenSourceAck.fromJson: missing "in_reply_to"',
      );
    }
    if (honored is! bool) {
      throw const FormatException(
        'RequestOpenSourceAck.fromJson: missing "honored"',
      );
    }
    final reason = json['reason'];
    return RequestOpenSourceAck(
      inReplyTo: inReplyTo,
      honored: honored,
      reason: reason is String ? reason : null,
    );
  }

  /// The [CxpEnvelope.messageId] of the request this acknowledges.
  final String inReplyTo;

  /// Whether the request was honoured.
  final bool honored;

  /// Optional human-readable reason.
  final String? reason;

  @override
  String get kind => CxpMessageKind.requestOpenSourceAck;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'in_reply_to': inReplyTo,
    'honored': honored,
    'reason': ?reason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestOpenSourceAck &&
          other.inReplyTo == inReplyTo &&
          other.honored == honored &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(inReplyTo, honored, reason);

  @override
  String toString() =>
      'RequestOpenSourceAck(replyTo=$inReplyTo, honored=$honored, '
      'reason=$reason)';
}
