## 0.8.1

No behaviour change. Package **patch**: the very_good_analysis 11 bump
turned two `return _queuedFor(...)` sites in `CxpWorkspaceStore`
(`upsertArtifact` and `pruneDesign`) into `return await _queuedFor(...)`, as
`async_return_with_no_await` requires. Inside an `async` body the two
spellings complete the returned future with the same value or error, so no
caller can observe the difference. No wire change.

## 0.8.0

Conformance with wire 1.2 as the spec was revised to state it (CXP §11.3,
§10.5, §10.1–10.2, §9.8, §6.1); discovery that no longer freezes the isolate
it runs on; and a workspace store that keeps every concurrent upsert. No
wire change. Package **minor**, which under 0.x is the breaking position:
paths, hosts and frames that were accepted are now refused, and the Dart API
gains `cxpLoopbackDialAddress`.

### Containment reads a path the way the filesystem does

`CxpPathContainment` normalised a path as text before it resolved links,
so `..` collapsed against the segment before it whether or not that
segment was a link. With a directory link inside an open root pointing
elsewhere, `<root>/dirlink/../secret.v` was **allowed**, and the open then
followed `dirlink` and read the file beside its target, outside the root.
§11.3 requires each `..` to be read the way the filesystem reads it.

- The deepest prefix of the path *as spelled* that exists is resolved by
  the filesystem (`realpath` on POSIX), with no normalisation first, and
  the rest is appended as written. A `..` in that remainder is refused —
  the filesystem cannot walk a directory that does not exist, and one
  created later could be a link. A prefix that exists but cannot be
  resolved (a dangling link, a loop) is refused: a write through a
  dangling link creates its target wherever it points. New refusal
  reason: `file_path cannot be resolved`.
- Roots go through the same resolution, so a root and a path spelled on
  either side of a link (macOS `/var` → `/private/var`) still agree.
- Windows is unchanged in kind: its filesystem API collapses `..` as text
  before resolving, and so does the check.
- What a check cannot promise is now stated on the class: a process that
  can write inside a root can swap a directory for a link between the
  check and the open. Checking the final string immediately before opening
  narrows that window; `dart:io` has no open that closes it.

### The floor checks the string it dispatches

The floor rule trimmed a path before checking it, so `" /etc/hosts"`
passed as absolute, and `LocalCxpServer` then dispatched the untrimmed
string — relative as spelled. §11.3 requires the receiver to open the
value it checked. A path that begins or ends with white space is now
refused (`file_path begins or ends with white space`) rather than repaired:
trimming would open a different file on POSIX, where trailing white space
is part of a name, and keeping it would name one file two ways on Windows,
which strips it. Nothing is respelled, so the checked and dispatched
strings are the same object.

- Conformance: `test/conformance/path_containment_test.dart` — a `..`
  after a directory link, with the target existing and not; a `..` in a
  remainder that does not exist; roots spelled through links; either side
  of a linked system directory; chains of links, relative link targets;
  dangling and looping links; white space on either end, at the rule and
  at the server.

### Loopback is a fixed set of spellings, not the platform's parser

`isCxpLoopbackHost` asked `InternetAddress.tryParse` — the platform C
library — whether a manifest's `host` was loopback, so which spellings it
dialled depended on the machine: on macOS it accepted `0127.0.0.1`,
`127.000.000.001`, `::00001` and `::1%lo0`, none of which the TypeScript
implementation accepts. §10.5 now fixes the set, and so does this package.

- New `cxpLoopbackDialAddress(String)` (public API): the address to dial
  for a manifest `host`, or null to refuse. The set, after white space
  around the value is ignored: `localhost` in any ASCII case; an IPv4
  address in `127.0.0.0/8` written as four decimal octets with no leading
  zeros; `::1` in any RFC 3986 `IPv6address` form (`0:0:0:0:0:0:0:1`,
  `::0.0.0.1`, …), optionally bracketed, with no zone identifier. Nothing
  asks a platform parser. `isCxpLoopbackHost` is now that function
  `!= null`.
- `CxpPeerConnector` dials the literal it checked — trimmed and
  unbracketed — instead of the manifest's spelling, so `[::1]` and
  `" 127.0.0.1 "` reach the address that was checked rather than a resolver
  lookup of the raw string. `CxpDialFailure.host` still reports the
  manifest's spelling.
- A bracketed IPv4 literal (`[127.0.0.1]`) is refused: §10.5 brackets the
  IPv6 literal only, as RFC 3986's IP-literal does. The TypeScript
  implementation still unbrackets it; it is the one host on which the two
  differ, and no Crux product writes it.
- Conformance: `test/conformance/dial_containment_test.dart` holds the rule
  to the 62 hosts of the corpus the TypeScript implementation is
  cross-checked with, answer for answer and dial address for dial address
  (bar the one above), plus RFC 3986 forms of `::1` and near misses; and
  the connector to dialling the checked literal and refusing a
  parser-only spelling without a socket. Measured against the TypeScript
  rule over a further 35,000 generated IPv6 spellings: no difference.

### The manifest and its directory are private to the user

Since wire 1.2 the manifest carries the token a listener requires, and
presenting it proves file access only if other users cannot read it. The
writer created the manifest directory and wrote the manifest with the
process umask — `0755` and `0644` under the usual `022` — relying on a
private directory above them. That holds on macOS (`~/Library`) and
Windows (the profile ACL), not on a Linux system whose home directories
are `0755`, where every local user could read every peer's token.
§10.1–10.2 now ask for `0700` directories and `0600` files.

- `CxpManifestWriter` and `CxpDiscovery` create each directory they create
  on the manifest path `0700`, one level at a time; directories that
  already existed above it are left alone. The manifest directory itself
  is tightened to `0700` on every write when it grants group or other
  access — an older build, or a product that created it with default
  permissions, leaves it `0755`.
- The manifest's scratch file is created exclusively, made `0600` while
  still empty, and only then given the token; the rename keeps the mode.
  No file others can read ever holds the token. The file name, JSON
  layout and no-`fsync` durability are as before.
- The mode is set through the C library's `chmod` (`dart:ffi`, since
  `dart:io` cannot set one), behind a conditional import so web builds
  never see `dart:ffi`. Best effort: a filesystem without modes keeps
  what it has, and the manifest is still written.
- Windows: nothing changes. `%APPDATA%` is inside the user's profile,
  whose access-control list admits only the user (and SYSTEM and the
  administrators), and what is created there inherits it.
- The residual: a manifest directory owned by another user cannot be
  tightened, and that user could read it regardless.
- Conformance: `test/conformance/manifest_permissions_test.dart` — the
  modes of created, pre-existing and loose directories, the manifest
  after the first write and after a heartbeat, the scratch file before
  and after the token is written, and a failed write.

### An error is never answered with an error; an unknown kind always is

§9.8 forbids answering an `error_response` with one — two peers that did
could trade errors forever — and both read loops could: `malformed_payload`
for an `error_response` whose payload did not decode, `handshake_required`
for one that arrived before the handshake, and `unsupported_version` for
one of another major version. §6.1 requires an unknown kind to be answered
`unknown_kind` in either role, and the dialling side dropped it silently.

- `LocalCxpServer` and `LocalCxpClient` never answer an `error_response`.
  One that does not decode is dropped; one before the handshake is
  dropped; one of another major version closes the connection unanswered.
  A client still waiting for its `hello_ack` treats an undecodable
  `error_response` as the refusal it is (§7.4), failing the handshake at
  once with the `code` it carried (`internal_error` when none) instead of
  waiting out the timeout.
- `LocalCxpServer.sendTo` drops an `ErrorResponse` whose `in_reply_to` is
  an `error_response` that peer sent, on the accept loop and on connector
  links alike. A product that answers every message it does not handle
  otherwise turns one stray error into a loop between two instances of
  itself. The server remembers the last 64 error ids per peer and forgets
  them when the peer goes.
- `LocalCxpClient` answers an unknown kind `unknown_kind` and keeps the
  connection, as the server always has.
- Conformance: `test/conformance/robustness_test.dart`, groups "an error is
  never answered with an error" and "an unknown kind is always answered".

### A redial reads the manifest again

`CxpPeerConnector` kept the first manifest it discovered for a `peer_id`
and dialled its host, port and token on every retry, and discovery reports
only additions and removals — so a manifest rewritten under the same peer
id (a server restarted on another port, or with another token) was never
seen. §7.4: a token belongs to one manifest, and a dialler finds the
current one by reading the manifest again. Each dial now takes the peer's
manifest from discovery's most recent scan. Every Crux product mints a new
peer id whenever it starts its server, so nothing changes for them; a host
that keeps its id across a restart is no longer dialled at its old port
with its old token.

- Conformance: `test/conformance/peer_connectivity_test.dart`, "a redial
  reads the manifest again".

### Discovery no longer freezes the isolate it runs on

`CxpDiscovery` scans every two seconds for the life of the process, on the
isolate that started it — the UI isolate in every Crux product. The scan
listed the directory, read each manifest and reaped with synchronous
`dart:io`, and checked each peer's pid by running the `kill -0` command
through `Process.runSync`: a process launch per peer per scan, all of it on
the event loop. Measured on macOS (arm64, Dart 3.13, AOT) with four live
peers and three stale ones: each scan was a single 22–27 ms stall at the
median and 47–53 ms at p95, in every default install whatever the user was
doing. After the change, the same binary pair run back to back: 0.4–0.5 ms of
work per scan spread across its I/O callbacks, and a median stall of about
50 µs. The benchmark is `benchmark/discovery_scan_benchmark.dart`.

- Every file operation in a scan is asynchronous: the listing, each read,
  and every reap. The event loop is held only between one and the next.
- A pid is probed with the C library's `kill(pid, 0)` through `dart:ffi`
  (behind a conditional import, as `chmod` is, so web builds never see
  `dart:ffi`). It answers as the command did: alive on success, dead on
  `ESRCH`, indeterminate on anything else, including `EPERM` and a pid a
  `pid_t` cannot hold. `Process.run` was not enough: `dart:io` forks on the
  calling isolate even when it does not wait for the child, about 3 ms per
  launch measured.
- A tick that falls due while a scan is still running is skipped, not
  queued, so a slow disk cannot stack scans up.
- `stop()` during a scan: the scan gives up at its next step, so nothing is
  emitted, reaped or recorded after `stop()`, as before. A `stop()` while
  `start()` was still making the directory no longer leaves the timer
  running.
- Only regular files are read. A FIFO named `*.json` in the peers directory
  froze the isolate for good (opening one for reading waits for a writer),
  and read asynchronously it would have stalled every scan after it; it is
  now passed over.
- `start()` still completes only once the first scan has finished, so
  `peers` is current when it returns. `ensureCxpPrivateDirectory` uses the
  asynchronous API as well.
- Conformance: `test/conformance/discovery_nonblocking_test.dart` — a scan
  on a disk where every operation takes 150 ms holds the event loop for
  less than half that and still reaches every answer; ticks during a scan
  are skipped; a scan in flight at `stop()` changes nothing; a FIFO is
  passed over; the pid probe agrees with `kill -0` and is a system call.
  Each synchronous call restored, the skip removed, the give-up removed and
  the FIFO check removed each turn a test red.

### Concurrent upserts for one design all survive

`CxpWorkspaceStore.upsertArtifact` read a design's document, added its
entry and wrote the document back, with nothing ordering one call after
another. Concurrent upserts for one design — a producer publishing a
waveform per finished test — each read the document before any had written
it, and the last rename kept only its own entry: of 24 concurrent upserts,
one survived. A peer's `request_open_artifact` then resolved to the wrong
file or to none.

- `upsertArtifact` and `pruneDesign` are queued per design document, across
  every store in the isolate: products rebuild their store when the
  containment rule changes, so a queue per instance would not be enough. A
  call that fails fails alone; the calls queued behind it still run.
- Across processes nothing is queued, and this is documented on the class.
  The atomic rename guarantees a reader a whole document, never a torn one;
  it does not make read-change-write atomic, so two products upserting the
  same design at the same moment can still drop one entry until that
  producer's next upsert of it.
- Conformance: `test/conformance/workspace_store_test.dart`, "concurrent
  writers in one isolate" — 24 concurrent upserts, the same across two
  stores, a prune queued among upserts, and a failing write. Without the
  queue, three of them fail.

## 0.7.0

The rest of the 2026-09 audit's CXP hardening, on top of 0.6.0: the connector
dials loopback only, a `design_id` cannot escape the workspace directory,
peers authenticate with the manifest token (wire **1.1 → 1.2**), and the
spec's containment rule is enforced here rather than described to four
products. Package **minor**: the Dart API gains surface
(`isCxpLoopbackHost`, `CxpDialRefusedException`,
`CxpWorkspaceStore.isValidDesignId`, the auth-token trio,
`CxpPathContainment`, and optional parameters on `LocalCxpServer`,
`CxpManifestWriter`, `CxpPeerManifest`, `Hello`, `CxpWorkspaceStore` and
`CxpClient.connect`); nothing is removed. 0.6.0 and 0.7.0 are one body of
work split across two pushes; the sections below are grouped by release
only because the semver guard is per push.

### The connector dials loopback and nothing else

`CxpPeerConnector` dialled whatever `host` a discovered manifest carried.
The manifest directory is user-writable, so one small JSON file could make
every product on the machine stream its selection gossip — and hand a
full-duplex link into its own dispatch stream — to any address on the
internet.

- New `isCxpLoopbackHost(String)`: a loopback literal (`127.0.0.0/8`,
  `::1`, bracketed or not) or the name `localhost`.
- The connector refuses any other host **before opening a socket**, as a
  `CxpDialRefusedException` (new) delivered through `dialFailures` and
  `lastDialFailures` like any other failure, with the usual backoff. The
  manifest stays visible to discovery so the products' unreachable-peer row
  can say why; `dialAttempts` does not count a refusal.

### `design_id` cannot escape the workspace directory

`CxpWorkspaceStore` keyed its record file with
`p.join(workspaceDirectory, '$designId.json')`. A `design_id` is opaque on
the wire and arrives from a peer on every `request_open_artifact`; a `..`
segment walked out of the directory, and an absolute id made `p.join`
discard the directory altogether (measured: `/tmp/evil` became
`/tmp/evil.json`).

- New `CxpWorkspaceStore.isValidDesignId(String)`: non-empty, no NUL, and
  the record file it would name stays inside `workspaceDirectory`. An id
  with a separator (`designs/cdc_capture`) still keys a file one level
  down, as it always has — this is containment, not a parse.
- An invalid id is a design with no records: `readArtifacts` and
  `pruneDesign` return empty, `resolveArtifact` returns null, and
  `upsertArtifact` writes nothing and returns empty. Nothing throws — the
  id came off a socket.

### Peer authentication: the manifest token (wire **1.1 → 1.2**)

`cxpProtocolVersion` is `1.2`. Additive on the wire — an optional `token`
on the peer manifest and on the `hello` payload, and one new error code,
`unauthorized` — with one deliberate behavioural consequence: the reference
server **requires** the token by default, so a pre-1.2 dialler, which
sends none, is refused. That is the one place the minor-compatibility rule
bends, and why.

**What it closes.** CXP is loopback-only and unauthenticated, and its
security model (spec §11) assumes "every process running as the user is
equally trusted". But every product binds a *fixed* default port
(54322–54325), and loopback is reachable by processes that model never
included: another user on a shared workstation, a sandboxed app holding a
network-client entitlement and no file access, a container with host
networking. The token restores the model's boundary: a dialler learns it
from the target's manifest in the user's private application-data
directory, so presenting it proves exactly the file access the spec already
assumes — and every legitimate peer reads that file anyway to learn the
port. What it does **not** do is authenticate a process running as the
user, which reads the manifest like any peer; that is the trust model, not
a gap, and it is why this is not called a password. (The audit's own note
that a token "closes the whole class" of issue #4 overstates it for that
reason.)

- `cxpProcessAuthToken` (new): one 128-bit token per process, minted from
  `Random.secure()` on first use. `generateCxpAuthToken()` and the
  constant-time `cxpAuthTokensMatch()` alongside.
- `CxpPeerManifest.token` (optional; null for a pre-1.2 manifest);
  `CxpManifestWriter(authToken:)` publishes it — default: the process
  token.
- `Hello.token` (optional); `CxpClient.connect(token:)` presents it —
  `LocalCxpClient` puts it in the Hello, and `CxpPeerConnector` passes
  `manifest.token` automatically.
- `LocalCxpServer(authToken:, requireAuthToken: true)`: a Hello whose token
  does not match is answered `unauthorized` and closed before it becomes a
  peer (no identity, no presence, no dispatch). The refusal names the
  requirement, never the token; neither `Hello.toString()` nor
  `CxpPeerManifest.toString()` prints it. `requireAuthToken: false` is the
  pre-1.2 behaviour for a receiver that must accept older diallers.
- **No product wiring is needed for the default case**: the server requires
  and the writer publishes the same process token. A product that gives its
  server an explicit token must give the writer the same one.
- `CxpErrorCode.unauthorized` (new). A 1.0/1.1 dialler treats it as
  `internal_error` (§6.1) and fails its handshake, which is the right
  outcome.
- Compatibility, stated plainly: a 1.2 build dials an older build as
  before (the older server ignores `token`). An older build dialling a 1.2
  build is refused; with the symmetric topology the 1.2 side's own dial
  still succeeds and carries traffic both ways over that link, so the pair
  keeps working with one route instead of two, and the older product's
  cross-probe panel shows the 1.2 peer as unreachable until it is updated.
  `crux-vscode`'s TypeScript implementation must forward the manifest
  `token` into its Hello before it can dial a 1.2 product.
- Conformance: `test/conformance/auth_token_test.dart`.

### The spec's containment rule, enforced in the shared layer

CXP §11 says a receiver **SHOULD** resolve a peer-supplied path against the
directories the user has already opened and refuse the rest, and **MUST**
apply the same rule to an artifact it resolved through its own records as
to a `file_path` on the wire, on the value it is about to open. Verified
against the four products: two enforce "absolute path" on
`request_open_source` and nothing on the artifact path (the MUST is
violated), two enforce nothing on either; none implements the SHOULD.

- New `CxpPathContainment`: the one rule. Without `roots` it is the floor
  every product was meant to have — absolute and well-formed (no relative
  form, no root-relative Windows form, no NUL). With `roots` (a callback,
  consulted on every check) it is the spec's: the path, canonicalised
  through `crux_io` (absolute, normalised, symlinks resolved, case-folded
  where the filesystem is), must lie inside one of the open directories. A
  callback that returns nothing refuses everything. Reasons are fixed
  strings that never repeat the path (§9.11).
- `LocalCxpServer(containment:)` applies it **before dispatch**, on the
  accept loop and on connector links alike: a `request_open_source` whose
  `file_path` is refused is acknowledged `honored: false` with the reason
  and never reaches the product; a `request_open_artifact` whose `path`
  hint is refused is dispatched with the hint removed (the `design_id`
  still resolves). Default: the floor rule, so no product loses a path it
  accepted before; pass `roots` to get the SHOULD.
- `CxpWorkspaceStore(containment:)` applies it to what `readArtifacts` and
  `resolveArtifact` return, never to what is persisted — a producer records
  what it produced; which of it a consumer may open is the consumer's rule.
- What the shared layer cannot do is check the value *about to be opened*
  — that moment is in the product, after any symlink or record could have
  changed. A product calls `containment.refuse(path)` once more immediately
  before opening, with the same instance its server holds.
- Conformance: `test/conformance/path_containment_test.dart` — the floor,
  roots, `..` walks, a symlink inside a root pointing outside, prefix
  siblings, live roots, non-echoing reasons; the server gate on the accept
  loop and on a link; the store filter.

## 0.6.0

The first part of the 2026-09 audit's CXP hardening: the two unauthenticated
loopback surfaces. Package **minor**: the Dart API gains
`CxpPeerManifest.maxEpochMillis`; nothing is removed.

### Discovery survives a malformed manifest

The manifest directory is writable by any process running as the user, and
one undecodable `.json` there used to freeze discovery for every product.
`CxpPeerManifest.fromJson` reached `DateTime.fromMillisecondsSinceEpoch` on a
peer-supplied `started_at`; past ±8640000000000000 that raises `RangeError`,
an `Error` that walked through the scan loop's `on FormatException`. Because
the add/remove emission and the `_known` update sit after the loop, the abort
did not lose one peer — nothing new was ever added and nothing gone was ever
removed while the file existed, and the periodic timer re-threw the same
error every two seconds.

- `CxpPeerManifest.fromJson` is now total over `FormatException`: a
  `started_at` outside `CxpPeerManifest.maxEpochMillis` (new constant) or a
  `port` outside 1–65535 is a `FormatException`, not an `Error`.
- The per-manifest handler in the scan loop catches `on Object`, so a
  decoder failure of any type costs exactly that file. A read race
  (`FileSystemException`) is still just skipped, never reaped.
- The scan tick itself is guarded, so a bug in the sweep skips a tick rather
  than surfacing on every tick with discovery frozen underneath.
- An undecodable `.json` older than `reapThreshold` (by mtime — it has no
  `started_at` to age and no `peer_id` to probe) is deleted, so a stray file
  stops being re-parsed by every product on every tick forever.
- Conformance: `test/conformance/discovery_robustness_test.dart` runs eight
  poison shapes through one scan and asserts the good peer beside them is
  discovered, the timer keeps running, and young poison is never deleted.

### The first unparseable frame closes the connection

`LocalCxpServer` used to answer a frame that was not an envelope with
`malformed_envelope` and keep reading. Every product listens on a fixed
default port (54322–54325), and a web page can `fetch()` a loopback port
with a `text/plain` POST that needs no CORS preflight: the request line and
headers arrive as frames the decoder rejects, and the body — whatever the
page chose, newline-delimited JSON included — was then dispatched as a
handshake and a stream of requests, blind, from any site the user had open.
Chrome's Local Network Access gate mitigates this; Firefox and Safari do not.

- The server now sends `malformed_envelope` and **closes** on the first frame
  that is not a JSON object or lacks a required envelope field. An HTTP
  request cannot begin with a JSON object, so the body is never reached.
- `LocalCxpClient` does the same for what comes back over an outbound link:
  a dialled port that answers with something other than envelopes fails the
  handshake (or drops an established link) with a `FormatException`. It used
  to drop the frame silently and read on.
- Frames that *are* envelopes but carry an undecodable payload or an unknown
  kind still leave the connection open, as §6.1 requires; the existing
  `malformed_payload` conformance cases pin that.
- Conformance: `robustness_test.dart` gains an "unparseable frames close the
  connection" group, including a literal browser POST whose body is a
  complete Hello + `request_open_source` session and which must never
  register a peer or reach the product handler.

## 0.5.4

Text only. Doc comments that named internal work items now say what they mean
or cite the published specification — for example §9.1.1 and §9.1.2 at
<https://edacrux.app/cxp#sec-9-1-1> and
<https://edacrux.app/cxp#sec-9-1-2>, and the `design_id` rules at
<https://edacrux.app/cxp#sec-9-10-1>. The pubspec description names the
Cross-Tool eXchange Protocol. No API change and no wire change —
`cxpProtocolVersion` is untouched.

## 0.5.3

`sharedCxpManifestDirectory()` — and `sharedCxpWorkspaceDirectory()`, which
derives from it — no longer throw `UnsupportedError` in a web build.

Both read `Platform.environment` and `Platform.operatingSystem` directly, and
in a browser each of those throws from inside `dart:io`. All four products
resolve the manifest directory on the path that starts their CXP server, and
all four ship web builds. The lookup now goes through a conditional export, so
`dart:io` stays out of it on the web, and a host with no environment or
operating system to ask gets the resolver's existing **`StateError`** — the
same "discovery unavailable" signal as a missing `$HOME`. A browser cannot take
part in CXP discovery, a same-machine filesystem mechanism, so that is the
honest answer, and it is one callers can already catch.

Supplying both `environment` and `operatingSystem` makes resolution pure path
arithmetic, and that works on any host, the web included.

No signature change and no wire-format change — `cxpProtocolVersion` is
untouched. On the VM and on desktop, resolution is unchanged. Proven in Chrome
by `test/web/cxp_manifest_directory_web_test.dart`, which CI runs.

## 0.5.2

Text only. The doc comment on `cxpDesignIdMetadataKey` cited a "§11.1
minor-version policy"; the published specification's §11 is Security
considerations and has no §11.1. The rule it means — a receiver ignores what it
does not understand — is §6.1, the forward-compatibility rule, and the comment
now links it at <https://edacrux.app/cxp#sec-6-1>.

No API change, no behaviour change, no wire-format change —
`cxpProtocolVersion` is untouched.

## 0.5.1

Text only. The suite brand is written **EDACrux**, one word; this package's
`description` and its library doc comment carried the two-word form. The
description is customer-visible on pub.dev once this package publishes at the
open-core flip, which is why a wording fix earns a version rather than riding
along silently.

No API change, no behaviour change, no wire-format change —
`cxpProtocolVersion` is untouched.

## 0.5.0

Subscription routing conforms to CXP 1.0 Working Draft **rev. 4** — the two
rulings in §9.1.1 (the delivery predicate) and §9.1.2 (selection retraction),
reasoned out in suite ADRs 0001 (*a CXP selection cleared to empty is a
retraction*) and 0002 (*CXP subscription filters are existential over all
referenced elements*). Both were raised by a second, independently written
implementation reading the published text alone. `CxpSubscription.matches` is the only changed predicate;
`_PeerConnection.accepts` and `_LinkedPeer.accepts` fold it unchanged, so the
socket path inherits both rulings without edit.

**This supersedes 0.4.4's "Subscription routing is unchanged, deliberately"
paragraph below.** That paragraph argued — correctly at the time — that
widening the predicate before the spec said so would put the reference
implementation ahead of its own published contract. The spec has now said so,
and the deferral is discharged. The history stays as written; this entry is the
correction.

- **`pathPrefix` is now existential over *all* referenced elements**, matching
  its sibling `elementKinds`, which was already `.any(...)`. It previously
  prefix-tested only the primary (first) element. §9.1.1 rules that a
  conformance failure rather than a permitted narrowing: `elements` is defined
  as being in the sender's own, presentational order (§9.3 — usually the order
  the user clicked), so a positional predicate makes routing depend on click
  order, and drops a multi-select spanning two scopes whenever the user
  happened to click the other scope first.
- **The two element filters are independent**, and always were here — the old
  code was positional, never conjunctive-per-element, so no coupling had to be
  unpicked. §9.1.1 now states the rule outright and it is pinned by a test: a
  subscription for `elementKinds: {signal}` with `pathPrefix: 'top.mem.'` is
  satisfied by a selection holding a `signal` outside `top.mem.` alongside a
  `net` inside it. One element need not satisfy both.
- **A retraction bypasses element filters.** A `notify_selection` whose
  `elements` array is empty is delivered to every peer subscribed to
  `notify_selection`, whatever filters that subscription carries (§9.1.2). The
  hole it closes was silent and permanent: a subscriber narrowed to
  `["signal"]` was told about a selection and could then never be told it had
  been withdrawn, holding a stale highlight for as long as both peers ran. The
  exemption is deliberately narrow — the predicate tests `notify_selection`
  *and* an empty element set, so a message of any other kind that references no
  element still falls through to the filters and still fails them.
- **The wire version stays `1.0`** (`cxpProtocolVersion` is untouched). Both
  rulings govern routing and acceptance, not the frame: no field, kind or code
  was added, removed or repurposed, and no frame any existing sender can emit is
  interpreted differently by its receiver — only the set of peers a copy is
  forwarded to changed. Per the versioning policy below, the protocol version
  tracks the bytes on the socket, and routing is not bytes. A minor bump would
  also be useless: minors are additive and unnegotiated (§6), so a `1.0` peer
  would never act on a rule gated behind `1.1` — precisely the mixed-version
  case that motivates the rulings.
- **Package version: minor, not patch,** although no signature, export or type
  moved. The versioning policy below scopes the package version to the Dart
  API, and a public method's documented contract is part of that API.
  `CxpSubscription.matches` is public, its old contract was stated in the
  dartdoc, argued for in the 0.4.4 changelog and *pinned by a named test*, so a
  consumer could legitimately have built on it — this is not the class of fix
  no caller could have depended on, which is what patch is for. Contrast 0.4.4,
  a patch: it turned a decoder throw into an accept, and no correct consumer
  can depend on a `FormatException`. The observable blast radius here is
  multi-select cross-probe and retraction delivery; for the single-element
  selection every shipping peer sends today, the old and new predicates
  coincide.
- Filtered subscribers now receive strictly more messages, which is legal and
  intended: §9.1.1 states the predicate is a **floor, not a ceiling** —
  delivering a message a subscription does not satisfy is not an error, filters
  exist to spare a receiver traffic, and they are never access control (§11). A
  receiver wanting the narrower set can recompute it on arrival with full
  knowledge of its own state; a receiver never sent the message cannot.
- The pinning test `'pathPrefix is evaluated against the primary (first)
  element'` was **inverted, not deleted** — it is now `'pathPrefix is evaluated
  against every element, not the first'` and asserts the rev. 4 rule, with a
  comment citing §9.1.1. Deleting it would lose the record that the old
  behaviour was deliberate. New coverage: filter independence, retraction
  delivery to a subscription filtered by kind *and* path (unit and end-to-end
  over the socket in `test/conformance/`), and the narrowness of the exemption.

## 0.4.4

- **`NotifySelection` now accepts an empty `elements` array**, as CXP §9.3
  has always said it must: "the selection, in the sender's own order; **MAY**
  be empty to signal cleared selection". `NotifySelection.fromJson` threw a
  `FormatException` on the empty case, so the server answered a conforming
  peer `malformed_payload` and "the user cleared their selection" had no
  legal wire representation at all. Found while writing a second
  (TypeScript) implementation, which matched this code rather than the spec
  and inherited the divergence — two implementations rejecting what the
  published protocol permits.
- `elements` remains **required to be present and to be an array** (§9.3,
  "Required: yes"). A missing key or a non-array value is still
  `malformed_payload`; only emptiness became legal. The distinction matters:
  a payload of `{}` is a bug, `{"elements": []}` is a statement.
- **The wire version stays `1.0`.** Per the versioning policy below, the
  protocol version tracks the bytes on the socket, and nothing about them
  changed: no field was added, removed, or made required, and no message any
  existing sender can emit is interpreted differently. This is strictly more
  permissive — a decoder that previously rejected a frame now accepts it —
  so no peer of any vintage sees a behaviour change on traffic it already
  sends. It is a conformance fix *to* the published 1.0 contract, not a
  revision *of* it.
- **Subscription routing is unchanged, deliberately.** A cleared selection
  carries no element references, so it matches every subscription without
  element filters — including the `cxpSubscribeToAll` default every peer
  sends after the handshake — and no `element_kinds`/`path_prefix`-filtered
  one, both of which §9.1 defines as "deliver only if **at least one**
  referenced element matches". A subscriber narrowed to `["signal"]`
  therefore is not told the selection was cleared. That is a genuine gap in
  §9.1, but widening it here would put the reference implementation ahead of
  its own spec — the exact failure this release fixes. Fix the spec first.
  `CxpSubscription.matches` evaluates the empty case without throwing, and
  tests pin both halves.
- No public API change: no signature, export, or type moved. Receiver
  *behaviour* on a cleared selection is a per-product UX decision and is not
  changed here.

## 0.4.3

- **`CxpStreamCoordinate` — the semantic stream coordinate (CXP §9.9).**
  An optional `coordinate` object on `NotifySelection` and `RequestHighlight`
  carrying `(stream_id, sequence_index, sub_id?)` plus an advisory
  `attributes` bag, naming one element of a *decoded stream* rather than a
  design object. Additive and ignorable, so **the wire version stays `1.0`**:
  §6.1 already obliges a receiver to ignore payload fields it does not
  recognise, and that rule is the entire compatibility story here.
- `CxpStreamCoordinate.tryFromJson` **returns null rather than throwing** for
  every malformed shape. Rejecting a whole `request_highlight` because its
  optional coordinate was garbled would fail worse than honouring the element
  and landing at the top of the file.
- Two registered stream ids, both constants so a typo cannot become a silent
  no-op at the far end: `riscv.rvfi.retire` (`sequence_index` = `rvfi_order`,
  `sub_id` = hart) and `riscv.formal.trace_step` (`sequence_index` = the
  bounded-proof step, `sub_id` = the RVFI channel). They address the same
  retirement on two index spaces, and the receiver — which holds the decoded
  trace — owns the conversion between them.

## 0.4.2

- Discovery hygiene: never liveness-reap the current self manifest (self is alive by construction; a dead-pid reading can only be an OS-recycled or synthetic pid). Fixes live-manifest deletion mid-run under synthetic-pid test fixtures.

# Changelog

All notable changes to `crux_cxp` are recorded here.

### Versioning policy

Two version numbers travel together in this package and they are
**deliberately independent**:

- **The package version** (`pubspec.yaml`) follows semver over the Dart
  API. `0.3.0` is a breaking API revision; consumers pin by submodule SHA
  today, so a bump is a *signal*, not an enforcement mechanism.
- **The wire protocol version** (`cxpProtocolVersion`, currently `1.0`)
  follows the compatibility rule the transport actually enforces
  (`isCompatibleCxpVersion`): a **major** mismatch is fatal — the peer is
  answered `unsupported_version` and the connection is closed — while a
  **minor** difference is accepted, because minor revisions may only add
  optional fields, message kinds, or element kinds.

They are independent because they answer different questions. A
Dart-source-breaking refactor that leaves every byte on the socket
unchanged bumps the package major and nothing else — a peer running an
older build must keep interoperating. Conversely a new required envelope
field would bump the protocol major even if the Dart API were untouched.
Tying them would force a wire-format break on every API cleanup, which is
precisely what a protocol meant for third-party implementations must not
do. The `0.3.0` release below is exactly that case: several breaking Dart
API changes, zero wire-format changes.

### Publishing to pub.dev

`publish_to: 'none'` is still set. `homepage`, `repository`,
`issue_tracker`, a real changelog and semver discipline are now in place;
what remains for the open-core flip is:

1. A `LICENSE` file (Apache-2.0) in this package — `pub publish` refuses
   without one. The repo root already carries it.
2. A `license:` field in this pubspec.
3. Replace `resolution: workspace` handling as needed for a standalone
   publish, and remove `publish_to: 'none'`.
4. Run `dart pub publish --dry-run` (impossible today: `publish_to: none`
   blocks it outright) and clear whatever it reports.

## 0.4.1

The `design_id` derivation contract (CXP §9.10.1). Additive (package **patch**; no wire
change — the workspace `design_id` remains an opaque, producer-supplied token,
this only standardises how the four apps compute it).

### Added

- **`cxpDesignIdForPath(String fileOrDirPath)`.** The one shared helper every
  Crux app uses to derive a design's workspace-manifest key from its open
  primary input. Canonicalises the **containing directory** (resolving
  symlinks, normalising, stripping a trailing separator) and returns the first
  16 hex of its `sha256` — a filesystem-safe `[0-9a-f]{16}` token, legal as the
  `workspace/<design_id>.json` filename `CxpWorkspaceStore` writes, and
  byte-identical across apps for the same folder. Four re-implementations that
  diverge on one normalisation detail would silently fail to join, so all apps
  MUST route through this helper (producer, sender, and consumer alike).

## 0.4.0

Cross-probe foundation: discovery hygiene and the shared-workspace link. Additive: the Dart API
gains surface (package **minor**) and the wire protocol goes **1.0 → 1.1** —
a minor, additive wire revision (new message kinds + one reserved metadata
key), so 1.0 and 1.1 peers still interoperate under `isCompatibleCxpVersion`.

### Added — shared-workspace artifact link

- **`CxpWorkspaceStore` / `WorkspaceArtifact` / `sharedCxpWorkspaceDirectory`.**
  A file-based store linking a shared **design** (opaque, producer-supplied
  `design_id`) to the concrete artifacts produced for it, so a receiver that
  cannot satisfy a cross-probe locally can open the right file. Documents live
  at `<user-app-data>/crux/cxp/workspace/<design_id>.json` — the `workspace/`
  sibling of the peers directory. API: `upsertArtifact(...)` (idempotent on
  `(path, kind)`, refreshes `ts`), `readArtifacts(designId)` (pure, prunes the
  returned view), `resolveArtifact(designId, kind, {topModule, basename})`
  (exact `design_id`+`kind`, falling back to the descriptive hints then newest
  `ts`), and `pruneDesign(designId)` (persists the stale-prune). Stale entries
  — missing file `path` or `ts` beyond the TTL — are dropped; writes reuse the
  crash-safe atomic rename the peer manifests use.
- **`RequestOpenArtifact` / `RequestOpenArtifactAck`** message kinds
  (`request_open_artifact` / `_ack`): a sender explicitly asks a peer to open a
  design artifact by `kind`, with an optional concrete-path hint. Wired through
  the decoder, `cxpSubscribeToAll`, and the conformance round-trip.
- **`cxpDesignIdMetadataKey`** (`crux.design_id`): a reserved namespaced
  `metadata` key senders SHOULD attach to `notify_selection` /
  `request_highlight` carrying the opaque design id. `RequestHighlight` gains an
  additive optional `metadata` map (it previously had none) to carry it.

### Fixed — peer-discovery hygiene

- **Pid-liveness pruning (the real root fix).** Pruning was TTL-only, so a peer
  that had just exited still showed in discovery until its timestamp aged out,
  and dead-session manifests piled up (one per rebuild — a fresh `peer_id` each
  time never overwrites the last). `CxpDiscovery` now parses the pid from a
  `peer_id`'s middle segment and, where the platform allows a definitive
  non-signalling liveness probe (Linux `/proc/<pid>`, macOS/POSIX `kill -0`),
  reaps a manifest whose owning process is provably **dead** at once — from view
  *and* disk, regardless of owner or age. This is safe precisely because a dead
  pid is unambiguous: it does not re-arm the sleep/wake mass-delete regression,
  since an asleep-but-alive peer's process still exists and reads as alive.
  Indeterminate liveness (Windows, `EPERM`, an unparseable pid) falls back to
  the existing TTL, so a live-but-quiet peer is never wrongly pruned.
- **Orphaned atomic-write temp files are actually swept now.** The sweep matched
  `*.json.tmp`, but `writeStringAtomic` names its scratch file
  `<peer>.json.<micros>-<counter>.tmp` — which does **not** end in `.json.tmp`,
  so every real orphan slipped through (the `*.json.<n>-0.tmp` leftovers that
  accumulated in the peers directory). The sweep now matches any `.tmp`, still protecting a
  live write by its fresh mtime.
- **Discovery dedupes by endpoint identity.** Two manifests advertising the same
  `product` on the same `host:port` (a momentary double — an old file lingering
  while a restarted peer rebinds the port) collapse to the newest `started_at`,
  so one running peer never surfaces as two rows.
- **`CxpManifestWriter.dispose()`** aliases `remove()`, documenting the
  clean-shutdown hook a product MUST call so its own manifest never lingers.
  `cxpDefaultManifestHeartbeat` is now a named constant.

### Adopter notes (per-app follow-ups)

- Producers call `upsertArtifact(...)` on open/produce of a design artifact
  (e.g. SimCrux on VCD save, NetCrux on netlist/source).
- A receiver that misses a highlight locally calls
  `resolveArtifact(designId, '<kind>')` (WaveCrux → `'waveform'`), opens the
  resolved file, then applies the highlight — reading `crux.design_id` from the
  inbound message's `metadata`.
- Products call `CxpManifestWriter.dispose()`/`remove()` on clean shutdown.

## 0.3.1

### Documentation

- The broadcast delivery contract is now normative and written down, in
  `CxpServer.broadcast`'s API docs and the README's "Broadcast delivery"
  section: server-accepted subscribed peers are the primary gossip path and
  the symmetric dial is the normative topology; connector-dialed links carry
  directed `sendTo` traffic, with subscription-filtered broadcast over the
  link as the de-duplicated fallback for asymmetric topologies; no
  subscription means no broadcast on either route.

### Fixed

- `LocalCxpServer.broadcast` now fans out over connector links, not only over
  inbound sockets. A peer this server merely dialed (attached via
  `attachLinkedPeer`, no inbound connection) previously received no broadcast,
  so `notify_selection` gossip reached it only under symmetric dial-back.
  Linked peers now carry their own subscription filter — populated from the
  `Subscribe` / `Unsubscribe` frames they send over the link and consumed via
  `injectInbound` — and `broadcast` delivers to each matching linked peer,
  de-duplicated against any peer already served over an inbound socket. Wire
  format and `cxpProtocolVersion` are unchanged.

## 0.3.0

### Breaking

- **`ElementKind` is now an open wire type.** It was a
  closed enum contributing one value per product, while its neighbour
  `CxpMessageKind` deliberately used open string constants — two adjacent
  wire types with opposite extensibility policies. `ElementKind` is now a
  value class wrapping the kind string, with the known set mirrored by a
  new `KnownElementKind` enum so internal code keeps exhaustive
  switching. **Wire format is unchanged**: every pre-existing value
  encodes to the identical string, and `ElementId.fromJson` now *accepts*
  an unrecognised kind (round-tripping it unchanged) instead of throwing
  `FormatException`.

  Source-level migration for consumers: `switch (kind) { case
  ElementKind.signal: … }` becomes `switch (kind.known) { case
  KnownElementKind.signal: … case null: … }`. Const **sets** of
  `ElementKind` are no longer possible (`const_set_element_not_primitive_equality`);
  drop the `const`. `ElementKind.values`, `ElementKind.signal` and friends,
  `==`, `hashCode` and Set/Map membership all behave as before.
- **`NoopCxpClient` deleted** — verified dead across all eight consumer
  repos.
- **`CappedLineSplitter`, `defaultCxpMaxLineLength`,
  `defaultCxpMaxPendingWriteBytes` and `elementIdListFromJson` are no
  longer exported** from `package:crux_cxp/crux_cxp.dart`. All four are
  transport implementation detail referenced by no consumer; holding them
  out keeps them from becoming a public compatibility commitment. The
  knobs remain reachable as the `maxLineLength` / `maxPendingWriteBytes`
  constructor arguments on `LocalCxpServer` and `LocalCxpClient`.
- **`CxpDiscovery` deletes only manifests it owns.** The new optional
  `selfPeerId` argument names the manifest this process wrote; without it
  a discovery deletes nothing. Previously every process deleted every
  *other* process's stale manifest.

### Fixed — transport robustness

- **Write errors are no longer invisible.** `socket.write` is an `IOSink`
  write and never throws synchronously, so the `try`/`catch` around every
  send was dead code: a write to a SIGKILLed peer returned normally, the
  `SocketException` landed in `Zone.handleUncaughtError`, and the peer
  stayed in the peer list until the read side happened to notice. Both
  transports now listen on `socket.done` and treat writes as
  fire-and-forget.
- **Outbound backpressure.** The inbound direction was capped
  (`CappedLineSplitter`); the outbound direction buffered without limit,
  so a peer that handshook and then stopped reading — a modal dialog, a
  wedged isolate — grew the sender's heap without bound. Bytes are now
  counted from queue to flush per connection and a peer past
  `maxPendingWriteBytes` (default 8 MiB) is dropped. Writes are serialized
  through a chain, because `IOSink.flush` marks the sink bound for its
  duration and an overlapping `write` or `close` throws `StateError`.
- **`CappedLineSplitter` no longer adds to a closed controller.** `fail()`
  closed the controller immediately but could only `unawaited(cancel())`
  upstream, so a chunk already queued behind an over-long frame still
  reached `handleChunk` and threw `StateError` from inside a stream data
  handler — triggered by a >1 MiB frame followed by more bytes in the same
  TCP segment. A `failed` flag makes the tear-down synchronous.
- **A failed bind no longer bricks the server.** `start()` set
  `_running = true` before `await ServerSocket.bind`, so binding an
  occupied port left a server that reported success from every subsequent
  `start()` while being permanently dead.
- **`stop()` then `start()` works.** `stop()` closed the inbound and
  presence broadcast controllers forever, so a restart re-bound and
  re-accepted but silently dropped every message on the `isClosed` guards
  — a user toggling CXP off and on in settings saw presence but never
  received a message. Both controllers are recreated on `start()`.
  `CxpDiscovery` had the same defect and the same fix. Note that
  subscriptions taken before a `stop()` must be re-established after the
  matching `start()`.
- **No more spurious cross-product disconnects on sleep/wake.** Each
  process deleted other processes' manifests past the 5-minute stale
  threshold, so a laptop suspended for 10 minutes woke with every
  product's scan running before any product's 30 s heartbeat: all four
  apps deleted each other's manifests and every connector tore down every
  link. Foreign stale manifests are now treated as absent, never deleted.
- **Orphaned `.json.tmp` files are swept.** A manifest write whose rename
  failed left a temp file nothing ever cleaned up.
- **Connect failures are observable and backed off.** `CxpPeerConnector`
  caught every dial error with a bare comment, retrying a permanently
  unreachable peer every 5 s forever with no diagnostic. It now exposes
  `dialFailures` (a stream of `CxpDialFailure`) and `lastDialFailures`,
  and backs off exponentially — 0, 1, 3, 7, … skipped ticks, capped by
  `maxRetryBackoffTicks` — resetting on a successful handshake. New
  `dispose()` releases the diagnostics stream.
- **Unknown element kinds in a `Subscribe` filter are preserved**, not
  silently dropped. Dropping them widened the subscription rather than
  narrowing it, and in the all-unknown case turned a filtered subscription
  into an unfiltered one.

### Added

- `test/no_riverpod_dependency_test.dart` — a guard failing the build if this package ever gains a Riverpod or
  Flutter dependency, in the pubspec or in any `lib/` import. crux-shared
  accepts its Riverpod coupling generally; `crux_cxp` is the exception,
  because it is the package third parties build against.

## 0.2.0

- **Link traffic routing** — `CxpServer` gains `injectInbound`,
  `attachLinkedPeer`, and `detachLinkedPeer`; `CxpPeerConnector` routes
  every link's frames into the local server's single `inbound` dispatch
  stream and registers the link as a reply route for `sendTo`, so
  directed messages between two products (and their acks) flow over
  the channel the connector opened. `connectedPeers` / `presence`
  become per-peer reachability (inbound handshakes ∪ attached links,
  de-duplicated).
- **Auto-subscribe** — connector links announce `cxpSubscribeToAll`
  (explicit enumeration; no wire wildcard) right after the handshake so
  `notify_selection` gossip flows between products; narrow via the
  `subscriptions:` constructor parameter or
  `updateSubscriptions`.
- **Subscription filters honored** — `CxpSubscription.elementKinds` /
  `pathPrefix` are evaluated by delivery via `CxpSubscription.matches`
  against the new `CxpMessage.referencedElements`.
- **Version policy enforced** — major mismatch answers
  `unsupported_version` and closes the connection (both sides; the
  client fails its pending handshake); minor differences are accepted.
  `isCompatibleCxpVersion` implements the policy.
- **Transport robustness** — malformed payloads of known kinds answer
  `malformed_payload` instead of crashing the read loop; the client
  gains connect/handshake timeouts and `CxpHandshakeException`, and a
  failed handshake tears the socket down so the connector can retry
  (`dialAttempts` exposes retry progress); `broadcast` survives
  mid-iteration disconnects; `CappedLineSplitter` bounds newline-JSON
  framing (default 1 MiB).
- Conformance suite: link routing, auto-subscribe, fault-path matrix,
  and an end-to-end product round trip between two connector-linked
  servers; all waits are bounded condition polls (zero fixed sleeps).

## 0.1.0

- v1.0 protocol bindings: `ElementId`/`ElementKind`, `NameResolver`
  (`Noop` / `Identity`), `PeerIdentity`.
- Wire envelope `CxpEnvelope` with newline-delimited JSON framing and
  forward-compatible field handling.
- Message bodies: `Hello`, `HelloAck`, `Goodbye`, `Subscribe`,
  `Unsubscribe`, `NotifySelection`, `RequestHighlight`,
  `RequestHighlightAck`, `RequestOpenSource`, `RequestOpenSourceAck`,
  `ErrorResponse` with `CxpErrorCode` constants.
- `CxpServer` + `LocalCxpServer` (TCP/JSON-line on localhost) +
  `NoopCxpServer`. Subscription-filtered broadcast, targeted `sendTo`,
  handshake-required gating, `ErrorResponse` for unknown kinds.
- `CxpClient` + `LocalCxpClient` + `NoopCxpClient`. Hello handshake
  with completion future; connection / inbound streams.
- `CxpDiscovery` + `CxpManifestWriter` + `CxpPeerManifest` for
  manifest-file-based peer discovery with stale-pruning and atomic
  rename-on-write.
- Conformance test suite under `test/conformance/`: handshake,
  subscribe + broadcast, targeted send, unknown-kind error, clean
  shutdown, 100-peer concurrent connect, discovery add/remove/stale.

## 0.0.1

- Initial skeleton: `CxpMessage` base type; `CxpServer` / `CxpClient`
  abstract interfaces with noop defaults.
