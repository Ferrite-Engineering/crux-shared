// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:meta/meta.dart';

/// Machine-readable error codes the v1 protocol defines.
///
/// Receivers SHOULD use these codes; new codes added in later protocol
/// versions MUST not collide with existing values.
abstract final class CxpErrorCode {
  /// The message could not be decoded as a CXP envelope.
  static const String malformedEnvelope = 'malformed_envelope';

  /// The envelope's [CxpEnvelope.kind] is not recognised by the receiver.
  static const String unknownKind = 'unknown_kind';

  /// The envelope decoded, but the payload was missing required fields.
  static const String malformedPayload = 'malformed_payload';

  /// The receiver received a non-Hello message before any handshake.
  static const String handshakeRequired = 'handshake_required';

  /// The receiver's protocol version is incompatible with the sender's.
  static const String unsupportedVersion = 'unsupported_version';

  /// The `hello` did not carry the token the receiver published in its
  /// manifest, and the receiver requires one. Sent in reply to the Hello,
  /// after which the receiver closes the connection. A dialler that reads
  /// the manifest afresh will find the current token. Additive in wire
  /// minor 1.2; a 1.0/1.1 dialler treats it as `internal_error` (§6.1),
  /// which is the right outcome — its handshake fails.
  static const String unauthorized = 'unauthorized';

  /// The receiver could not resolve the requested `ElementId` to a local
  /// object.
  static const String elementNotFound = 'element_not_found';

  /// The receiver does not implement the requested operation.
  static const String unsupported = 'unsupported';

  /// Generic catch-all for receiver-side failures that don't fit a more
  /// specific code.
  static const String internalError = 'internal_error';
}

/// Error envelope returned in response to a malformed or unprocessable
/// message.
///
/// Carries a machine-readable [code], a human-readable [message], and the
/// [inReplyTo] field correlating the error to the request that triggered
/// it. When the offending message could not be decoded far enough to
/// recover its message ID, [inReplyTo] MAY be the empty string.
@immutable
class ErrorResponse extends CxpMessage {
  /// Creates an ErrorResponse.
  const ErrorResponse({
    required this.code,
    required this.message,
    this.inReplyTo = '',
  });

  /// Decodes an [ErrorResponse] from its JSON payload.
  factory ErrorResponse.fromJson(Map<String, Object?> json) {
    final code = json['code'];
    final message = json['message'];
    if (code is! String) {
      throw const FormatException('ErrorResponse.fromJson: missing "code"');
    }
    if (message is! String) {
      throw const FormatException(
        'ErrorResponse.fromJson: missing "message"',
      );
    }
    final inReplyTo = json['in_reply_to'];
    return ErrorResponse(
      code: code,
      message: message,
      inReplyTo: inReplyTo is String ? inReplyTo : '',
    );
  }

  /// Machine-readable error code (one of [CxpErrorCode]).
  final String code;

  /// Human-readable error message.
  final String message;

  /// The [CxpEnvelope.messageId] of the message that triggered this error,
  /// or empty when the offending message could not be decoded enough to
  /// recover its ID.
  final String inReplyTo;

  @override
  String get kind => CxpMessageKind.errorResponse;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    'in_reply_to': inReplyTo,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ErrorResponse &&
          other.code == code &&
          other.message == message &&
          other.inReplyTo == inReplyTo);

  @override
  int get hashCode => Object.hash(code, message, inReplyTo);

  @override
  String toString() =>
      'ErrorResponse(code=$code, message="$message", replyTo=$inReplyTo)';
}
