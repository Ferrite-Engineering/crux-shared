# cxp

A pure-Dart client for **CXP 1.3 (specification revision 9)**, the
Cross-Tool eXchange Protocol. From any Dart program, with no Flutter, you can
cross-probe the EDACrux desktop apps: show a signal at a time in WaveCrux,
highlight a net or a cell or open a scope in NetCrux, open a source location,
and hear what the user selects in them.

## What CXP is

CXP is a small protocol that lets independent EDA tools running on one
workstation share a user's focus. Select a signal in a waveform viewer and a
schematic browser highlights the net; a tool reports a violation and an editor
opens the line. Peers are symmetric, discover each other through a per-user
directory of manifest files, and talk newline-delimited JSON over loopback
TCP. It carries references (a kind and a path), never designs or waveforms.
The specification is published at <https://edacrux.app/cxp>.

The apps that speak it today are **WaveCrux**, **NetCrux**, **LintCrux** and
**SimCrux**. Any other program can join: this package is the Dart way in.

## Example

```dart
import 'package:cxp/cxp.dart';

Future<void> main() async {
  final probe = await CxpProbe.start(name: 'my-tool');

  // What the apps select, as the user clicks.
  probe.events.listen((event) {
    if (event is CxpSelectionReceived) {
      print('${event.peer.productName} selected ${event.elements}');
    }
  });

  await probe.waitForPeer(product: 'wavecrux');
  final replies = await probe.showSignal('top.cpu.alu.result', timePs: 41250);
  for (final reply in replies) {
    print('${reply.peer.productName}: ${reply.outcome.name}');
  }
  await probe.highlightNet('top.cpu.alu.carry', product: 'netcrux');
  await probe.openSource('/work/rtl/alu.sv', 214, column: 9);
  await probe.close();
}
```

[`example/cxp_example.dart`](example/cxp_example.dart) is this program.
[`example/rohd/`](example/rohd) is a ROHD simulation that, the first time a
signal rises, asks WaveCrux to show it and NetCrux to highlight the net. It is
a package of its own so that ROHD is a dependency of the example and not of
this package; run it with `dart pub get` and
`dart run bin/counter_probe.dart` in that directory.

## The API

`CxpProbe` is the whole client. It is a *dial-only* peer: it publishes no
manifest and opens no port, so there is nothing for a stranger to dial. It
scans the manifest directory, connects to every running peer on loopback with
the 1.3 mutual authentication, and keeps those links up.

| Member | What it does |
|---|---|
| `CxpProbe.start(name:, ...)` | Starts scanning and dialling. `name` is the product name the apps show in their peer lists. |
| `peers`, `events`, `waitForPeer(product:)` | Who is connected; peers joining and leaving, selections and requests as `CxpProbeEvent`s; wait for an app to appear. |
| `showSignal`, `highlightNet`, `highlightCell`, `openScope`, `highlight(kind, path)` | `request_highlight`, one per element kind (`signal`, `net`, `cell`, `scope`, or any kind). |
| `openSource(file, line, column:)` | `request_open_source`. |
| `select(elements)`, `clearSelection()` | `notify_selection` and its retraction. |
| `dialFailures` | Why a discovered peer could not be dialled. |
| `close()` | Says goodbye to every peer. |

Every send method returns one `CxpProbeReply` per peer asked:
`honored`, `declined` (the peer understood and did not act, with its reason),
`unacknowledged` (no answer in time) or `failed` (the link was gone). A peer
declining is a normal outcome, not an exception.

**Who a request goes to.** Without `to:` or `product:` a request goes to every
connected peer that accepts the element kind, by the specification's
`cxp.accepts:<kind>` capability convention (a peer that advertises none is
sent whatever you send). `product:` narrows it to one app; `to:` names a peer
and sends regardless.

**Time.** `timePs` rides in the request's `metadata` as `time_ps`. CXP does
not yet register a key for simulation time, so no app acts on it yet; apps
ignore metadata keys they do not know, so sending it is safe.

**Receiving.** A probe subscribes to every selection by default and reports
them as `CxpSelectionReceived`. A peer can also send the probe a request; pass
a `CxpProbeRequestHandler` to answer, or every such request is declined with a
reason.

The pieces `CxpProbe` is built from are exported as well: `ElementId` and
`ElementKind`, `PeerIdentity`, the message classes, `LocalCxpClient`,
`CxpDiscovery`, `CxpPeerConnector`, `sharedCxpManifestDirectory`.

## Scope and limits

- Same machine only. The probe dials loopback addresses and refuses a manifest
  that names anything else.
- Dial-only. Because it listens for nothing, peers do not discover it; they
  see it as a connected peer once it has dialled them. A program that must be
  discovered, or must serve `request_open_artifact`, needs a listener, which
  this package does not include.
- The directory the probe scans is writable by any process running as the
  user, which is the trust boundary CXP assumes (specification section 11).
  CXP has no encryption and no authorisation model.
- Not for the web: a browser has no filesystem to discover peers through, and
  `CxpProbe.start` throws a `StateError` there.

## Versions

| | |
|---|---|
| CXP protocol version on the wire | 1.3 (`cxpProtocolVersion`) |
| Specification revision implemented | 9 (`cxpSpecificationRevision`) |

The package version follows semver over the Dart API and is independent of the
wire version. See the [changelog](CHANGELOG.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
