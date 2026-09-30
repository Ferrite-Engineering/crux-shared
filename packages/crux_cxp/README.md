# crux_cxp

Cross-Tool eXchange Protocol bindings for the EDACrux suite.

CXP is the peer cross-probe protocol that lets Crux apps (and third-party
tools) gossip selection events, request highlights, and reconcile element
identity across products.

Distinct from WaveCrux's WCP. WCP is an external **driver** protocol: a
script or another tool connects and commands WaveCrux. CXP is **peer
gossip** between running Crux apps on the same machine, where no
participant is in charge and every peer both publishes and subscribes.
The two do not overlap, and a product can speak both.

## What's in the box

This is the **v1 protocol binding**. It supplies the wire format, the
shared identity model, the localhost TCP transport, and the manifest-based
discovery — everything four Crux products need to talk to each other and
to any third-party tool that links this package.

| Surface | Purpose |
|---|---|
| `ElementId` / `ElementKind` / `KnownElementKind` | Opaque, comparable identifier for a cross-tool referenceable element. `ElementKind` is an **open** wire type: the kinds this build names are `signal`, `scope`, `instance`, `net`, `port`, `marker`, `rule`, `test`, `breakpoint`, `source`, and a kind from a peer that this build does not know decodes with `kind.known == null` and round-trips unchanged rather than failing. Switch on `kind.known` (a `KnownElementKind?`) when you need exhaustiveness. |
| `NameResolver` (+ `NoopNameResolver`, `IdentityNameResolver`) | Seam each product implements to translate its native references into and out of canonical `ElementId` form. |
| `PeerIdentity` | Self-description a peer announces during the Hello handshake. Carries `peerId`, `productName`, `productVersion`, and an open-ended `capabilities` set. |
| `CxpEnvelope` + `CxpMessage` subtypes | Wire format. Concrete bodies: `Hello`, `HelloAck`, `Goodbye`, `Subscribe`, `Unsubscribe`, `NotifySelection`, `RequestHighlight`, `RequestHighlightAck`, `RequestOpenSource`, `RequestOpenSourceAck`, `RequestOpenArtifact`, `RequestOpenArtifactAck`, `ErrorResponse`. |
| `CxpWorkspaceStore` / `WorkspaceArtifact` / `sharedCxpWorkspaceDirectory` | File-based **shared-workspace** link store (CXP §9.10): maps an opaque, producer-supplied `design_id` to the artifacts produced for it, so a receiver with nothing matching open resolves and opens the right file. Documents live in the `workspace/` sibling of the peers directory. Concurrent upserts for one design are queued within an isolate, so all of them survive; across processes the last rename wins. `cxpDesignIdMetadataKey` (`crux.design_id`) is the reserved `metadata` key that carries the id on `notify_selection` / `request_highlight`. |
| `CxpServer` (+ `LocalCxpServer`, `NoopCxpServer`) | Abstract server interface and a TCP/JSON-line implementation bound to localhost. |
| `CxpClient` (+ `LocalCxpClient`) | Symmetric client with connect/handshake timeouts. |
| `CxpDiscovery`, `CxpManifestWriter`, `CxpPeerManifest` | Discovery via a shared directory of `<peer_id>.json` manifest files. Hygiene: pid-liveness reaping of dead peers, TTL fallback where liveness is indeterminate, orphaned atomic-write `.tmp` sweeping, endpoint dedupe, heartbeat refresh, and a `dispose()`/`remove()` clean-shutdown hook. A manifest that does not decode costs only itself, never the scan. |
| `cxpProcessAuthToken`, `generateCxpAuthToken`, `cxpAuthTokensMatch` | Peer authentication (wire 1.2). The manifest publishes a per-process token and `LocalCxpServer` requires it in every Hello, so a fixed loopback port is reachable only by processes that can read the user's private manifest directory — the boundary the spec's trust model already assumes. See "Authentication" below. |
| `sharedCxpManifestDirectory` | The suite-shared, bundle-independent per-user manifest directory every product publishes into and scans. Throws `StateError` — "discovery unavailable" — when it cannot be resolved: a missing `$HOME` / `%APPDATA%`, or a web build, which has no environment or filesystem to take part in discovery with. |
| `CxpPeerConnector` | Dials every discovered peer — loopback only (`isCxpLoopbackHost`); any other host is refused before a socket exists, as a `CxpDialRefusedException` dial failure — and routes each link's traffic into the local server's dispatch stream (see below). |
| `cxpLoopbackDialAddress`, `isCxpLoopbackHost` | CXP §10.5's closed loopback set — `localhost`, `127.0.0.0/8` as four decimal octets with no leading zeros, `::1` in any RFC 3986 form, bracketed or not, with no zone — decided without any platform address parser. `cxpLoopbackDialAddress` returns the literal to connect to (trimmed, unbracketed), so a dialler connects to exactly what it checked. |
| `CxpPathContainment` | The receiver-side rule (CXP §11) for a path a peer asks this process to open: absolute and well-formed, and — given the session's open `roots` — inside one of them, on the canonical (symlink-resolved) path. `LocalCxpServer` applies it before a request reaches the product; `CxpWorkspaceStore` applies it to what it resolves; the product applies it once more to the value it is about to open. |
| `CxpDialFailure` | Diagnostic emitted by `CxpPeerConnector.dialFailures` for every failed outbound dial, with the peer, the error, the consecutive-failure count and the current backoff. |

The newline-JSON framing layer (`CappedLineSplitter` and its size constants) is **not** exported: it is transport implementation detail, and the knobs it parameterises are reachable as the `maxLineLength` and `maxPendingWriteBytes` arguments on `LocalCxpServer` / `LocalCxpClient`.

## Wire format

- Transport: TCP on localhost (default 127.0.0.1).
- Framing: newline-delimited JSON. One JSON envelope per line; the receiver
  parses lines independently. A line longer than the receiver's
  `maxLineLength` (default 1 MiB) is a fatal framing error — the
  connection is dropped, so an unterminated line can never buffer
  unboundedly. A line that is not a JSON object, or is one that lacks a
  required envelope field, is answered `malformed_envelope` **and the
  connection is closed**: the products listen on fixed default ports, and
  a browser `fetch()` to one of them arrives as an HTTP request line
  followed by a body the page chose, so the first non-envelope frame ends
  the session before the body can be dispatched. `LocalCxpClient` applies
  the same rule to what a dialled peer sends back. Null-byte framing is
  reserved for a future binary mode.
- Envelope: `{cxp_version, message_id, from, kind, payload}`. Payloads
  with unknown extra keys are silently accepted (forward compatibility);
  envelopes with unknown `kind` values are rejected with an
  `ErrorResponse` (code `unknown_kind`) by the server and the client
  alike; envelopes of a known kind whose payload fails to decode are
  rejected with `malformed_payload`. Both of those leave the connection
  open — only a frame that is not an envelope at all closes it. An
  `error_response` is never answered with one (CXP §9.8), by either read
  loop or by a product reply sent through `LocalCxpServer.sendTo`.
- Versioning: every peer announces `cxp_version` in the Hello and in
  every envelope. A **major**-version mismatch (or an unparseable
  version) is rejected with `ErrorResponse` (code `unsupported_version`)
  **and the connection is closed**; a client fails its pending
  handshake. **Minor** differences are accepted — minor revisions are
  additive and unknown payload fields are ignored, so a 1.x peer can
  always talk to a 1.y peer. `isCompatibleCxpVersion` implements the
  policy.
- Subscriptions: `broadcast` delivers only to peers whose registered
  `Subscribe` filters match. `CxpSubscription.elementKinds` and
  `pathPrefix` are honored, and both are **existential and independent**
  (CXP §9.1.1): each requires *at least one* referenced element to
  satisfy it, evaluated over all of them, and the same element need not
  satisfy both. Position is not part of the predicate. A message without
  element references fails either filter, except that an empty-`elements`
  `notify_selection` — a retraction (§9.1.2) — bypasses both.
  `CxpSubscription.matches` is the single evaluation point.
- Discovery: each running CxpServer writes a manifest to
  `${manifestDirectory}/<peer_id>.json` describing the peer, the port,
  and the start timestamp — conventionally `sharedCxpManifestDirectory()`
  (macOS `~/Library/Application Support/crux/cxp/peers`, Windows
  `%APPDATA%\crux\cxp\peers`, Linux
  `${XDG_DATA_HOME:-~/.local/share}/crux/cxp/peers`), which is per-user
  and bundle-independent so every product resolves the same directory.
  Other peers watch the directory and emit presence events. The writer
  refreshes `started_at` every 30 s. A manifest is pruned when its owning
  process is provably dead (pid parsed from the `peer_id`, probed
  non-signallingly where the platform allows) or, where liveness is
  indeterminate, when `started_at` ages past `staleThreshold` (default 5
  minutes). Orphaned atomic-write `.tmp` scratch files are swept, and two
  manifests for the same `product`+`host:port` dedupe to the newest.
  A scan holds the isolate that runs it only between one file operation
  and the next — its I/O is asynchronous and a pid is probed with a system
  call, not a process launch — reads regular files only, and never
  overlaps the next: a tick that falls due mid-scan is skipped.

## Peer links: routing, replies, auto-subscribe

Discovery names peers; the `CxpPeerConnector` turns them into live
channels. Each product runs one connector next to its server, and the
connector maintains one outbound client link per discovered peer
(retrying while the manifest stays known). Links are symmetric by
design — when both peers run a connector, each side's server also sees
an inbound Hello.

An outbound link is a full-duplex CXP channel, and the remote peer uses
it as its reply and delivery path back to us: frames the remote sends
arrive on the connector's client socket, not on our server's accept
loop. A connector constructed with `server:` therefore wires every link
into the server when the handshake completes:

1. **Inbound merge** — every frame the link receives is fed into
   `CxpServer.injectInbound` tagged with the remote peer's identity, so
   a product's single `server.inbound` subscription sees link traffic
   and server-accepted traffic identically.
2. **Reply route** — the link is registered via
   `CxpServer.attachLinkedPeer`, so `server.sendTo(peerId, …)` can
   answer over the link (acks return on the channel the request arrived
   on) even when the peer never dials back. `connectedPeers` and
   `presence` report per-peer reachability: the union of inbound
   handshakes and attached links, de-duplicated.

### Broadcast delivery (normative)

`CxpServer.broadcast` delivers to every reachable peer whose
subscription filter matches, under this contract:

- **Server-accepted subscribed peers are the primary path.** A peer
  receives gossip by dialing this node's server and sending a
  `Subscribe`. The **symmetric dial is the normative topology**: every
  CXP node runs a server plus a connector, each side dials the other,
  and each therefore receives the other's broadcasts as a
  server-accepted subscriber. A third-party tool that wants gossip must
  dial in and subscribe — accepting this node's outbound connection is
  not enough by itself.
- **Connector-dialed links carry directed traffic** — `sendTo` replies
  and acks return over the link. As a fallback for asymmetric
  topologies (a peer this node dialed that never dialed back), a linked
  peer that has sent a `Subscribe` over the link also receives matching
  broadcasts, de-duplicated against inbound delivery so a symmetrically
  connected peer gets each frame exactly once.
- **No subscription, no broadcast** — on either route, a peer that has
  not subscribed receives nothing from `broadcast`.
3. **Auto-subscribe** — the link announces a `Subscribe` immediately
   after the handshake — `cxpSubscribeToAll` by default, an explicit
   enumeration of the v1 broadcastable kinds (the wire format has no
   wildcard) — so `notify_selection` gossip flows with zero per-product
   wiring. Narrow or widen at runtime with
   `CxpPeerConnector.updateSubscriptions`, or seed a custom set via the
   `subscriptions:` constructor parameter.

## Use from a Crux product

```dart
import 'package:crux_cxp/crux_cxp.dart';

const identity = PeerIdentity(
  peerId: 'wavecrux-123',
  productName: 'wavecrux',
  productVersion: '1.0.0',
);

// Start a server bound to a free port.
final server = LocalCxpServer(
  selfIdentity: identity,
  nameResolver: MyWaveCruxNameResolver(),
);
await server.start();
final port = server.boundPort!;

// Publish a manifest (heartbeat included) so other peers discover us,
// scan for theirs, and dial every peer we see — routing link traffic
// into our server's dispatch stream.
final manifestDir = sharedCxpManifestDirectory();
final writer = CxpManifestWriter(manifestDirectory: manifestDir);
await writer.write(identity: identity, host: '127.0.0.1', port: port);
final discovery = CxpDiscovery(manifestDirectory: manifestDir);
final connector = CxpPeerConnector(
  selfIdentity: identity,
  discovery: discovery,
  server: server,
);
await discovery.start();
connector.start();

// Listen for inbound messages — one subscription sees traffic from
// server-accepted connections AND connector links.
server.inbound.listen((inbound) {
  if (inbound.message is RequestHighlight) {
    // Delegate to the same internal code path the WCP `add_items` handler uses.
    final req = inbound.message as RequestHighlight;
    final local = server.nameResolver.toLocal(req.element);
    if (local != null) jumpToLocalSignal(local);
  }
});

// Broadcast a selection change to subscribers.
server.broadcast(
  NotifySelection(
    elements: [
      ElementId(kind: ElementKind.signal, path: 'top.cpu.pc[31:0]'),
    ],
    displayName: 'pc',
  ),
);

// Announce that the user deselected everything. An empty `elements` is
// the wire form of a cleared selection (CXP §9.3) — legal to send and to
// receive. What a receiver does about it is a per-product UX decision.
server.broadcast(const NotifySelection(elements: []));
```

A cleared selection is a **retraction** (CXP §9.1.2) and is exempt from
element filtering: it reaches *every* peer subscribed to
`notify_selection`, whatever `element_kinds`/`path_prefix` that
subscription carries — otherwise a narrowed subscriber could never learn
that a selection it was told about has been withdrawn. Delivery says
nothing about what was selected before it. See `CxpSubscription`'s class
doc.

## Authentication

CXP is loopback-only and its security model (spec §11) trusts every
process running as the user. Every product binds a **fixed** default port,
though, and loopback is reachable by processes that model never included —
another user on a shared workstation, a sandboxed app with a network-client
entitlement, a container with host networking. Since wire **1.2** the
manifest carries a `token`, and a server refuses a `hello` that does not
present it:

- `LocalCxpServer` requires `authToken` (default: `cxpProcessAuthToken`,
  minted once per process from `Random.secure()`), and
  `CxpManifestWriter` publishes `authToken` (same default). With defaults on
  both, **no wiring is needed**. Give both the same explicit token to run
  several peers in one process with distinct secrets.
- `CxpPeerConnector` presents `manifest.token` on every dial;
  `LocalCxpClient.connect(token:)` does it by hand.
- A refused Hello is answered `unauthorized` and closed before the dialler
  becomes a peer. The refusal never states the token, and neither
  `Hello.toString()` nor `CxpPeerManifest.toString()` prints it.
- `LocalCxpServer(requireAuthToken: false)` is the pre-1.2 behaviour, for a
  receiver that must accept diallers that send no token.

The token is only as private as the manifest file. On macOS and Linux the
writer and discovery create every directory they create on the manifest
path `0700`, tighten the manifest directory itself to `0700` when it is
looser, and write the manifest `0600` — owner-only before the token is
written into it — so a world-readable home directory (a common Linux
default) no longer exposes it. On Windows `%APPDATA%` is inside the user's
profile, whose access-control list is already per-user. It is **not** a
password: a process running as the user reads the manifest like any peer.

## Containment

A `request_open_source` names a file and a `request_open_artifact` names a
design whose file the receiver looks up; either way the receiver is about
to open a path a peer chose. `CxpPathContainment` is the one rule:

```dart
final containment = CxpPathContainment(roots: () => openDesignDirectories);
final server = LocalCxpServer(selfIdentity: me, containment: containment);
final store = CxpWorkspaceStore(containment: containment);
// ...and at the moment of opening, on the final path:
final why = containment.refuse(path);
if (why != null) return ack(honored: false, reason: why);
```

The server refuses a `request_open_source` outside the roots (acked
`honored: false`, never dispatched) and strips a `request_open_artifact`
hint that is; the store returns only artifacts inside them; the product's
own check covers the moment the spec cares about most — the value about to
be opened, after any record or symlink could have changed. Without `roots`
the rule is the floor: absolute and well-formed.

The rule judges the string exactly as spelled, and the product opens that
same string: nothing is trimmed, so a path with white space at either end
is refused rather than repaired. With `roots`, the filesystem does the
reading — the deepest existing prefix is resolved (links followed before
the `..` after them, as `open` does), the rest is appended as written, and
a `..` in that remainder, a dangling link or a loop is refused. A check
describes the filesystem when it ran; a process that can write inside a
root can still swap a directory for a link before the open, which is why
the product checks immediately before opening.

## Conformance suite

`test/conformance/` runs a black-box matrix that any CxpServer/CxpClient
implementation must pass — handshake, subscribe/broadcast, targeted send,
`ErrorResponse` on unknown kind and malformed payloads, version
negotiation, frame-length caps, handshake rejection/timeout recovery,
clean shutdown, 100 concurrent peers, manifest discovery
add/remove/stale-pruning, link routing with reply-over-link, connector
auto-subscribe, and an end-to-end product round trip between two
connector-linked servers.

The **normative reference** for anyone building a non-Dart implementation is
the language-neutral wire specification, not this Dart suite:
<https://edacrux.app/cxp>. This conformance suite is how the reference Dart
implementation checks itself against that document; a Python or Rust client
should be written against the spec and, ideally, have an equivalent black-box
matrix of its own. Where the two disagree, the spec and this code are each
suspect until reconciled — report it.

## Relationship to WaveCrux's WCP

CXP and WCP are **orthogonal**:

| | WCP | CXP |
|---|---|---|
| Role | External driver | Peer cross-probe |
| Caller | Outside tool (CI script, simulator wrapper, IDE extension) | Crux app or third-party peer |
| Direction | Imperative, viewer-bound | Bidirectional, symmetric |
| Primitives | `load`, `add_items`, `set_cursor`, `set_viewport_range` | `notify_selection`, `subscribe`, `request_highlight`, `request_open_source`, `request_open_artifact` |
| Identity | `DisplayedItemRef` (per-viewer ephemeral integer) | Canonical hierarchical path (`ElementId`) |

A CXP-speaking product runs both servers on distinct ports with shared
underlying TCP/JSON infrastructure but disjoint command surfaces. Where a
CXP handler needs to produce a viewer effect WCP also exposes, the two
handlers delegate to one internal implementation — one piece of business
logic, two front doors.

## Status

The v1.0 protocol bindings, transport and discovery are shipped and in use.
Each product wires up its own CXP server and handler set on its own
schedule; this package is the shared half.

This is the one package in `crux-shared` that will be **published to
pub.dev** at the open-core flip, so that third-party tools can speak CXP
without vendoring anything. It therefore carries real semver discipline
today — see the versioning policy at the top of
[`CHANGELOG.md`](CHANGELOG.md), which also explains why the package version
and the `cxpProtocolVersion` wire version move independently.

## License

Apache 2.0 at the post-beta open-core flip, matching the rest of the EDA
Crux suite (each product's open-core repo follows the same
`<vendor>/<product>` pattern).
