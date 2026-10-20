// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_settings.dart';
import 'package:meta/meta.dart';

/// The capability prefix a peer uses to say which element kinds it can
/// show when asked to highlight one: `cxp.accepts:net`, `cxp.accepts:signal`.
///
/// A sender that finds any such capability on a peer offers that peer only
/// the kinds listed; a peer that lists none is offered the suite's
/// element-kind table for its product.
const String kCxpAcceptsCapabilityPrefix = 'cxp.accepts:';

/// What is genuinely one product's own in the CXP lifecycle: who it is, what
/// it can show, where its settings live and how received paths are screened.
///
/// Everything else (starting and stopping the server, discovery, the peer
/// list, unreachable peers, settings persistence, acknowledgements) is the
/// shared runtime's, and behaves the same in every product.
@immutable
class CruxCxpProductBinding {
  /// Creates a binding.
  const CruxCxpProductBinding({
    required this.productName,
    required this.defaultPort,
    required this.prefsPrefix,
    this.capabilities = const <String>{},
    this.acceptedKinds = const <ElementKind>[],
    this.containment = const CxpPathContainment(),
    this.nameResolver = const IdentityNameResolver(),
  });

  /// The wire product name, lower case: `wavecrux`, `netcrux`, `lintcrux`,
  /// `simcrux`. Also the peer-id prefix.
  final String productName;

  /// The product's default CXP port.
  final int defaultPort;

  /// The product's preference-key prefix (see [CruxCxpSettingsCodec]).
  final String prefsPrefix;

  /// Product capabilities advertised in the peer identity.
  final Set<String> capabilities;

  /// The element kinds this product can highlight when a peer asks,
  /// advertised as [kCxpAcceptsCapabilityPrefix] capabilities so senders
  /// offer only what will land.
  final List<ElementKind> acceptedKinds;

  /// The receiver-side rule every peer-supplied path is checked against
  /// before a request reaches the product.
  final CxpPathContainment containment;

  /// Converts between product-local and canonical element names.
  final NameResolver nameResolver;

  /// The settings codec for this product's keys and default port.
  CruxCxpSettingsCodec get settingsCodec =>
      CruxCxpSettingsCodec(prefix: prefsPrefix, defaultPort: defaultPort);

  /// Every capability the peer identity carries.
  Set<String> get advertisedCapabilities => <String>{
    ...capabilities,
    for (final kind in acceptedKinds)
      '$kCxpAcceptsCapabilityPrefix${kind.name}',
  };
}

/// What a product did with a request a peer sent. Maps onto the `honored` /
/// `reason` fields of the acknowledgement the runtime sends back.
@immutable
class CruxCxpHandlerResult {
  /// Creates a result.
  const CruxCxpHandlerResult({required this.honored, this.reason});

  /// An honoured request.
  static const CruxCxpHandlerResult ok = CruxCxpHandlerResult(honored: true);

  /// A request this product does not handle.
  static const CruxCxpHandlerResult unsupported = CruxCxpHandlerResult(
    honored: false,
    reason: 'unsupported',
  );

  /// Whether the request was carried out.
  final bool honored;

  /// Why not, when [honored] is false. Shown to the sender's user.
  final String? reason;
}

/// The product's handlers for what peers send.
///
/// The runtime calls these and sends the acknowledgement itself: a handler
/// returns a [CruxCxpHandlerResult] and never replies on the wire. A handler
/// that throws is acknowledged as not honoured, with the error as the reason.
/// Every method defaults to "not handled", so a product overrides only what
/// it supports.
class CruxCxpRequestHandler {
  /// Creates a handler that handles nothing.
  const CruxCxpRequestHandler();

  /// A peer asked this product to show [request]'s element.
  Future<CruxCxpHandlerResult> highlight(
    RequestHighlight request,
    PeerIdentity from,
  ) async => CruxCxpHandlerResult.unsupported;

  /// A peer asked this product to open a source location.
  Future<CruxCxpHandlerResult> openSource(
    RequestOpenSource request,
    PeerIdentity from,
  ) async => CruxCxpHandlerResult.unsupported;

  /// A peer asked this product to open a design artifact.
  Future<CruxCxpHandlerResult> openArtifact(
    RequestOpenArtifact request,
    PeerIdentity from,
  ) async => CruxCxpHandlerResult.unsupported;

  /// A peer announced its selection. No acknowledgement exists for this.
  void selection(NotifySelection message, PeerIdentity from) {}
}
