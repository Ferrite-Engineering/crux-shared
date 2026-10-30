// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A pure-Dart client for CXP, the Cross-Tool eXchange Protocol: the
/// same-machine protocol the EDACrux desktop apps (WaveCrux, NetCrux,
/// LintCrux and SimCrux) use to share a user's focus.
///
/// This package implements CXP 1.3, specification revision 9
/// (`cxpProtocolVersion`, `cxpSpecificationRevision`); the specification is
/// published at <https://edacrux.app/cxp>.
///
/// ### Start here
///
/// `CxpProbe` is the whole client in one class. It finds the running apps,
/// connects, sends typed cross-probe requests and reports what the apps
/// select:
///
/// ```dart
/// final probe = await CxpProbe.start(name: 'my-tool');
/// await probe.waitForPeer(product: 'wavecrux');
/// await probe.showSignal('top.cpu.alu.result', timePs: 41250);
/// await probe.close();
/// ```
///
/// It uses no Flutter and no `dart:ui`; it runs in a command-line program, a
/// test, a simulation, or a server.
///
/// ### The protocol underneath
///
/// Everything `CxpProbe` is built from is exported too, for a tool that
/// needs more than the client:
///
/// - `ElementId` / `ElementKind` / `KnownElementKind` and `NameResolver`:
///   element identity, the open vocabulary of kinds, and the seam a product
///   uses to translate its own names.
/// - `PeerIdentity`: a peer's self-description and its capability strings,
///   including `cxp.accepts:<kind>`.
/// - `CxpEnvelope` and the `CxpMessage` subtypes (`Hello`, `HelloAck`,
///   `Goodbye`, `Subscribe`, `Unsubscribe`, `NotifySelection`,
///   `RequestHighlight`, `RequestHighlightAck`, `RequestOpenSource`,
///   `RequestOpenSourceAck`, `RequestOpenArtifact`,
///   `RequestOpenArtifactAck`, `ErrorResponse`) and `decodeCxpMessage`.
/// - `CxpClient` / `LocalCxpClient`: one connection to one peer, with the
///   handshake and the mutual authentication of CXP 1.3.
/// - `CxpDiscovery` / `CxpPeerManifest` / `CxpManifestWriter` and
///   `sharedCxpManifestDirectory`: discovery over the per-user manifest
///   directory.
/// - `CxpPeerConnector`: dials every discovered peer, loopback only.
/// - `CxpStreamCoordinate`, `cxpDesignIdForPath`, the authentication
///   helpers (`cxpAuthProof`, `cxpAuthTokensMatch`, ...) and the
///   registered metadata keys.
///
/// A program that also *listens* for peers (publishes a manifest and accepts
/// connections, as the apps do) needs a server, which this package does not
/// contain; `CxpLinkSink` is the seam one plugs into.
library;

export 'src/cxp_auth_token.dart';
export 'src/cxp_client.dart';
export 'src/cxp_design_id.dart';
export 'src/cxp_discovery.dart';
export 'src/cxp_link_sink.dart';
export 'src/cxp_manifest_directory.dart';
export 'src/cxp_peer_connector.dart';
export 'src/element_id.dart';
export 'src/messages/cxp_message.dart' hide elementIdListFromJson;
export 'src/messages/decoder.dart';
export 'src/messages/error_response.dart';
export 'src/messages/hello.dart';
export 'src/messages/highlight.dart';
export 'src/messages/open_artifact.dart';
export 'src/messages/open_source.dart';
export 'src/messages/selection.dart';
export 'src/messages/subscribe.dart';
export 'src/name_resolver.dart';
export 'src/peer_identity.dart';
export 'src/probe/cxp_probe.dart';
export 'src/probe/cxp_probe_types.dart';
export 'src/stream_coordinate.dart';
