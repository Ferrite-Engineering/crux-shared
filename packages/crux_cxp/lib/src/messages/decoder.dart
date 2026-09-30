// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:crux_cxp/src/messages/error_response.dart';
import 'package:crux_cxp/src/messages/hello.dart';
import 'package:crux_cxp/src/messages/highlight.dart';
import 'package:crux_cxp/src/messages/open_artifact.dart';
import 'package:crux_cxp/src/messages/open_source.dart';
import 'package:crux_cxp/src/messages/selection.dart';
import 'package:crux_cxp/src/messages/subscribe.dart';

/// Decode a CXP message body of the given [kind] from its [payload].
///
/// Returns a concrete [CxpMessage] subtype, or throws [FormatException]
/// for malformed payloads. Returns `null` when [kind] is not recognised —
/// callers respond with an [ErrorResponse] using
/// [CxpErrorCode.unknownKind].
CxpMessage? decodeCxpMessage(String kind, Map<String, Object?> payload) {
  switch (kind) {
    case CxpMessageKind.hello:
      return Hello.fromJson(payload);
    case CxpMessageKind.helloAck:
      return HelloAck.fromJson(payload);
    case CxpMessageKind.goodbye:
      return Goodbye.fromJson(payload);
    case CxpMessageKind.subscribe:
      return Subscribe.fromJson(payload);
    case CxpMessageKind.unsubscribe:
      return Unsubscribe.fromJson(payload);
    case CxpMessageKind.notifySelection:
      return NotifySelection.fromJson(payload);
    case CxpMessageKind.requestHighlight:
      return RequestHighlight.fromJson(payload);
    case CxpMessageKind.requestHighlightAck:
      return RequestHighlightAck.fromJson(payload);
    case CxpMessageKind.requestOpenSource:
      return RequestOpenSource.fromJson(payload);
    case CxpMessageKind.requestOpenSourceAck:
      return RequestOpenSourceAck.fromJson(payload);
    case CxpMessageKind.requestOpenArtifact:
      return RequestOpenArtifact.fromJson(payload);
    case CxpMessageKind.requestOpenArtifactAck:
      return RequestOpenArtifactAck.fromJson(payload);
    case CxpMessageKind.errorResponse:
      return ErrorResponse.fromJson(payload);
    default:
      return null;
  }
}
