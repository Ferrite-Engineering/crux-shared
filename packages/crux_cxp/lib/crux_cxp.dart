// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-Tool eXchange Protocol bindings for the EDACrux suite.
///
/// CXP is the peer cross-probe protocol that lets Crux apps gossip
/// selection events, request highlights, and reconcile element identity
/// across products. Distinct from WaveCrux's WCP: WCP is an *external
/// driver* protocol, by which a script or another tool commands WaveCrux;
/// CXP is *peer gossip* between running Crux apps on the same machine,
/// where no participant is in charge.
///
/// This library exports the v1 protocol bindings:
///
/// - `ElementId` / `ElementKind` — cross-tool element identity.
/// - `NameResolver` / `NoopNameResolver` / `IdentityNameResolver` —
///   product-local ↔ canonical name conversion seam.
/// - `PeerIdentity` — peer self-description.
/// - `CxpEnvelope` + concrete `CxpMessage` subtypes (`Hello`, `HelloAck`,
///   `Goodbye`, `Subscribe`, `Unsubscribe`, `NotifySelection`,
///   `RequestHighlight`, `RequestHighlightAck`, `RequestOpenSource`,
///   `RequestOpenSourceAck`, `RequestOpenArtifact`,
///   `RequestOpenArtifactAck`, `ErrorResponse`).
/// - `CxpServer` / `LocalCxpServer` / `NoopCxpServer` — peer server.
/// - `CxpClient` / `LocalCxpClient` — peer client.
/// - `CxpDiscovery` / `CxpManifestWriter` / `CxpPeerManifest` — discovery
///   over a shared manifest directory.
/// - `cxpProcessAuthToken` / `generateCxpAuthToken` / `cxpAuthTokensMatch`
///   — the per-process token a manifest publishes and a server requires of
///   every dialler (wire 1.2), which restricts a fixed loopback port to
///   processes that can read the user's files.
/// - `sharedCxpManifestDirectory` — the suite-shared (bundle-independent)
///   manifest directory every product must publish into and scan.
/// - `CxpPeerConnector` — dials every discovered peer (loopback only —
///   `isCxpLoopbackHost` / `cxpLoopbackDialAddress`, CXP §10.5's closed set
///   of spellings, and the connector dials the literal it checked), routes
///   each link's inbound frames into the local server's dispatch stream,
///   registers the link as a reply route, and auto-subscribes to broadcast
///   gossip.
/// - `CxpPathContainment` — the receiver-side rule (§11) for a path a peer
///   asked this process to open, applied by `LocalCxpServer` before a
///   request reaches the product and by `CxpWorkspaceStore` to what it
///   resolves.
/// - `CxpWorkspaceStore` / `WorkspaceArtifact` /
///   `sharedCxpWorkspaceDirectory` — the shared design→artifact link store
///   a receiver uses to open the right file when it has none matching.
/// - `RequestOpenArtifact` / `RequestOpenArtifactAck` and the reserved
///   `cxpDesignIdMetadataKey` (`crux.design_id`) metadata convention.
/// - `cxpDesignIdForPath` — the one shared helper every app uses to derive a
///   design's workspace-manifest key from its open primary input
///   (<https://edacrux.app/cxp#sec-9-10-1>).
/// - `CxpStreamCoordinate` — the optional `coordinate` payload field on
///   `NotifySelection` and `RequestHighlight` (CXP §9.9), naming one
///   element of a *decoded stream* rather than a design object.
///
/// ### Deliberately not exported
///
/// The newline-JSON framing layer (`CappedLineSplitter`,
/// `defaultCxpMaxLineLength`, `defaultCxpMaxPendingWriteBytes`) and the
/// payload-decoding helper `elementIdListFromJson` are implementation
/// detail of `LocalCxpServer` / `LocalCxpClient`, referenced by no
/// consumer, and are held out of the public surface so they do not become
/// a compatibility commitment. The knobs they parameterise are still
/// reachable — as the `maxLineLength` and `maxPendingWriteBytes`
/// constructor arguments on both transports. Tests reach the framing
/// directly via `package:crux_cxp/src/line_framing.dart`.
library;

export 'src/cxp_auth_token.dart';
export 'src/cxp_client.dart';
export 'src/cxp_design_id.dart';
export 'src/cxp_discovery.dart';
export 'src/cxp_manifest_directory.dart';
export 'src/cxp_path_containment.dart';
export 'src/cxp_peer_connector.dart';
export 'src/cxp_server.dart';
export 'src/cxp_workspace.dart';
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
export 'src/stream_coordinate.dart';
