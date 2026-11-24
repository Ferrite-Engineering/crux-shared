# crux_telemetry_core

The Flutter-free half of the suite's telemetry. Pure Dart, permanently: no
Flutter anywhere in the dependency closure
(`test/no_flutter_dependency_test.dart`), so each product's headless binary
(`dart build cli`) and `crux_mcp` can link it.

## What it holds

| Part | What |
|---|---|
| Payload | `TelemetryEvent`, `TelemetryEnvelope`, the coalescing batcher, the endpoints, and the closed vocabularies the ingestion Worker checks (`kTelemetryOperatingSystems`, `kTelemetryFormFactors`, `kTelemetryLicenseTiers`). Moved here from `crux_telemetry`, which re-exports them unchanged. |
| Consent vocabulary | `TelemetryConsentState`, `TelemetryPolicy`, the storage keys and `kTelemetryInstallationIdPattern`, the `TelemetryStorage` seam. |
| Services | `TelemetryService`, `NoopTelemetryService`, `telemetryEnumToken`. |
| Desktop consent | `desktopTelemetryStores` names where a product's desktop app records its answer on this machine: the `com.ferriteengineering.<product>` and `com.ferriteengineering.<product>Pro` preference domains on macOS (read through `defaults`), `shared_preferences.json` under the XDG data directory on Linux and under `%APPDATA%\com.ferriteengineering\<Product>[ Pro]` on Windows, and LintCrux's own `crux/telemetry/lintcrux.json`. `DesktopTelemetryConsent.read` takes the first `enabled` or `disabled`, this binary's edition first. Nothing here ever writes, mints or deletes. |
| Headless counting | `HeadlessTelemetry`: records only when `CI` is not set, the beta is not running (except under `TELEMETRY_DEV`), no Enterprise policy says `deny`, and the desktop app recorded `enabled` with an installation id. `unset` is never consent here. Events are held in memory, coalesced, and sent to the same Worker as the app's, under the app's installation id, a minute after the first and on `close`. An event whose name, keys or string values are not `[a-z0-9_]` tokens is dropped whole, so no path or argument can be sent. |

## Wiring a server

```dart
McpServer(
  // ...
  telemetry: McpTelemetry.desktop(HeadlessTelemetry(
    product: CruxTelemetryProduct.wavecrux, pro: false, appVersion: version)),
);
```

A Pro binary passes `pro: true`, its resolved tier as `licenseTier`, and its
policy file's telemetry decision as `policy`.
