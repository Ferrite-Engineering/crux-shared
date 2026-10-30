# Changelog

## Versioning policy

Two version numbers travel together and are deliberately independent:

- The **package version** (`pubspec.yaml`) follows semver over the Dart API.
- The **wire protocol version** (`cxpProtocolVersion`, currently `1.3`)
  follows the rule the transport enforces (`isCompatibleCxpVersion`): a major
  mismatch is refused, a minor difference is accepted.

The specification is a Working Draft with numbered revisions. A revision that
only registers vocabulary (element kinds, stream ids, metadata keys) changes
neither version on the wire; `cxpSpecificationRevision` says which revision
this release implements.

## 0.1.0

First release. Implements CXP 1.3, specification revision 10.

- `showSignal(path, timePs:)` and the other highlight methods send the time
  under the registered `crux.time_ps` metadata key (`cxpTimePsMetadataKey`),
  which revision 10 of the specification registers: a non-negative integer
  number of picoseconds from the start of the simulation, which a waveform
  viewer answers by putting its cursor there and scrolling it into view. A
  negative `timePs` throws an `ArgumentError` before anything is sent.

- `CxpProbe`: a dial-only client. Finds the running apps through the manifest
  directory, connects with the 1.3 mutual authentication, and sends typed
  requests (`showSignal`, `highlightNet`, `highlightCell`, `openScope`,
  `highlight`, `openSource`, `select`, `clearSelection`), each answered with
  one `CxpProbeReply` per peer. Reports peers joining and leaving, selections
  and requests as `CxpProbeEvent`s. Honours the `cxp.accepts:<kind>`
  capability convention when choosing who to send to.
- The protocol layer it is built on, exported: element identity
  (`ElementId`, `ElementKind`), `PeerIdentity`, the envelope and every message
  kind, `LocalCxpClient`, `CxpDiscovery`, `CxpManifestWriter`,
  `CxpPeerConnector`, the authentication helpers, `CxpStreamCoordinate` and
  `cxpDesignIdForPath`.
- `CxpLinkSink`: the seam a listening peer plugs into the connector through.
- `cxpSpecificationRevision`, `LocalCxpClient.sendTracked` (sends and returns
  the message id an acknowledgement will name).
- A second entry point, `package:edacrux_cxp/edacrux_cxp_listener.dart`, with the framing and
  network-path helpers a program that listens for peers shares with the client.
- Examples: a plain Dart program and a ROHD simulation.

The protocol layer was extracted unchanged from the EDACrux suite's own
`crux_cxp` package, which now depends on this one, so the apps and this
package run the same code.
