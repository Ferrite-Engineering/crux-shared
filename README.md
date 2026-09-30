# crux-shared

Shared infrastructure for the EDACrux suite: the cross-product Dart packages that WaveCrux, NetCrux, LintCrux and SimCrux all build on.

This is a Melos workspace. Nothing in it is specific to one product's domain — the rule is that a package earns its place here by being *consumed* by more than one product, not by sounding generic.

## Visibility & license

**License:** **Apache License 2.0**, already in the tree — [`LICENSE`](LICENSE), [`NOTICES`](NOTICES), and an SPDX header on every source file. CI checks the headers (`tool/spdx-headers.py`) and the third-party attributions (`tool/gen-notices.py`) on every run.

**Visibility:** private during the public beta, like every product repo in the suite; public at the post-beta open-core flip, in lockstep with the four open-core product repos. Each open-core product consumes `crux_shared` from its `pubspec.yaml`, so once those repos go public this one has to as well, or the dependency chain breaks. Apache 2.0, with its explicit patent grant, also gives third-party tools a clean path to build CXP-compatible products against `crux_cxp`.

Everything here is intended to be public at the flip — there is no private subset. What must stay secret is kept out of this repository entirely:

- The licence-key signing **private** key. Keygen generates and holds it; it is in no repository and no CI secret store. What `crux_license` compiles in — the Keygen account id and the Ed25519 verify key — is public by design, and `open_core_purity_test.dart` fails if any code a product build can reach gains the ability to sign. The one signer in the tree, the `crux-policy sign` subcommand's, signs an organization's own policy file with the organization's own key and ships in no product; the guard exempts it by name and holds it to still being a signer.
- Keygen admin tokens and every other service credential.
- Pro and Enterprise feature implementations, which live in each product's private Pro overlay — or, when more than one overlay shares one, in a private Pro-tier shared repository that depends on this one and never the reverse ([ADR 0005](docs/adr/0005-pro-implementations-leave-crux-shared.md)).

The telemetry ingest URLs and the concrete `LiveTelemetryService` **do** live here, in `crux_telemetry`: the whole collection pipeline is public so it can be read and stripped, and abuse is handled by the ingest Worker's validation, not by hiding the URL.

## Packages

Every package has its own README with the full surface and the canonical wiring pattern, and its own CHANGELOG — a static guard in `crux_workspace` fails when either is missing. The table is a directory, not a specification.

**Foundations** (pure Dart, no Flutter dependency):

| Package | Purpose |
|---|---|
| [`crux_async`](packages/crux_async) | Async/timing primitives, starting with `Debouncer` — coalesces a burst of calls into one trailing invocation, with `run` / `cancel` / `flush` / `dispose`. Lifted from LintCrux's own debouncer after an audit found the cancel/dispose-discipline bugs a shared implementation is meant to make hard to repeat. |
| [`crux_io`](packages/crux_io) | Crash-safe atomic file replacement (`writeStringAtomic` / `writeJsonAtomic`, `WriteDurability`), path identity (`canonicalizePath` / `canonicalPathKey` / `isSamePath`), engine `PATH` augmentation, and spawn resolution (`requireSpawnExecutableForHost` / `requireSpawnExecutable` / `SpawnHost` / `isAbsoluteSpawnPath`), which turns a bare executable name into an absolute path — or refuses to start anything when the tool is not installed — so Windows never runs a same-named binary from the directory a product was launched in. A deliberately tiny leaf every persistence layer and spawn site in the suite goes through, so each of these is decided once instead of once per product. |
| [`crux_sqlite`](packages/crux_sqlite) | The one SQLite open path in the suite. A store supplies a migration list, a data-value declaration and a path; the package supplies the rest — `CruxMigration` / `CruxMigrationRunner` (append-only, additive-only, latest version derived from the list), `CruxSqliteOpenPolicy` (the only place an `OpenDatabaseOptions` is built: one upgrade loop for fresh and upgraded installs alike, an `onDowngrade` that always refuses, a mandatory 5 s `busy_timeout`), `CruxDbRecovery` (`renameAside` / `refuse` / `recreate` — precious data is never deleted), and three distinguishable typed failures for corruption, migration failure and version skew. Pure Dart permanently: both products' headless CLIs write these databases. |
| [`crux_linux_integration`](packages/crux_linux_integration) | Linux AppImage first-run desktop self-integration: writes each app's `.desktop` entry, the `shared-mime-info` package that makes its `MimeType` list resolve (a file manager types the file first, so without it a project file is typed as JSON and the app is never offered), and hicolor icons, so the running window matches a host-side desktop entry (Wayland/GNOME dock icons) and a double-clicked file opens in the right application. Idempotent, guarded to Linux+AppImage, best-effort cache refresh. |
| [`crux_shortcut_action`](packages/crux_shortcut_action) | The `CruxAction` interface each product's action enum implements, plus the `ActionCategory` grouping enum. Zero dependencies; the vocabulary the keybinding and command-palette packages are generic over. |
| [`crux_app_info`](packages/crux_app_info) | About-box extension-point models: `ApplicationBuildInfo` and `ApplicationBranding`. The edition chip is `EditionBadge`, in `crux_license`. |
| [`crux_yosys`](packages/crux_yosys) | Yosys subprocess infrastructure — `YosysRunner`, `YosysAvailabilityService`, `YosysDiagnosticParser`, and the tool-neutral `ProcessRunner` / `ProcessRegistry` seam. Consumed by NetCrux and LintCrux. |
| [`crux_netlist`](packages/crux_netlist) | The suite's shared elaborated-design model — a pure mirror of Yosys `write_json`, plus its parser. The output half of what `crux_yosys` runs, consumed by NetCrux's schematic and LintCrux's CDC engine, so two products read one model instead of two. |
| [`crux_cxp`](packages/crux_cxp) | Cross-Tool eXchange Protocol bindings — the same-machine cross-probe gossip layer that lets Crux apps (and third-party tools) reconcile element identity across products. Wire format, framing, client, server, discovery, peer manifest, conformance suite. Slated for publication to pub.dev at the open-core flip. |
| [`crux_cxp_ui`](packages/crux_cxp_ui) | The Flutter companion to `crux_cxp`: the one shared **docked cross-probe side-panel** all four products adopt (Connected Peers with per-peer direct send, Unreachable peers, Recent Events incl. selection-received + open-artifact), plus the app-agnostic `CrossProbePanelController` contract the widget renders against. |

**Application infrastructure** (Flutter):

| Package | Purpose |
|---|---|
| [`crux_license`](packages/crux_license) | Tier vocabulary (`LicenseTier`, Open Core / EDU / Pro / Enterprise, with EDU feature-equivalent to Pro), `FeatureGate`, `licenseTierProvider`, the `kBetaPeriod` / `kBetaExpiry` beta-gating and build-shelf-life machinery, the `kAiExperimental` AI-assistant gate, and the `FeatureTierBadge` / `EditionBadge` chips. `CruxLicenseValidator` verifies Keygen-signed licence keys and licence files here, in the open: a key grants a tier and names the products it covers — one product, or all four on a Suite SKU. A second, Flutter-free entry point `crux_license_core.dart` carries the headless subset for `dart build cli` binaries. |
| [`crux_signing`](packages/crux_signing) | Ed25519 signature **verification**, and nothing else — the one Ed25519 implementation in the suite. Hand-written from RFC 8032 §5.1.7 and checked against the RFC's own vectors including the malleability and small-order cases, specifically so that no cipher enters `crux-shared`: `package:cryptography` ships AES-GCM and ChaCha20, and pulling it in would put a cipher in every product and make the store builds' `ITSAppUsesNonExemptEncryption=false` untrue. **No signing, no key generation, no key agreement.** Three consumers verify through it: `crux_license` (licence keys and files), `crux_policy` (the organization's signed `.crux-policy.json`) and plugin governance. Pure Dart permanently — the `crux-policy` CLI and both products' headless CLIs need it. |
| [`crux_audit`](packages/crux_audit) | The shared `AuditEvent` envelope, the `AuditSink` seam, and an append-only JSONL sink. **The envelope is shared; the event kinds are not** — a kind is a plain string the product registers, because a shared enum would need editing here every time any of four products learned a new event. The sink opens, appends one line and closes per event, which is what makes every rotation scheme work with no detection logic: this package does not rotate, because the organization already does. Write failures **degrade and report** rather than throwing or failing silently — a product that crashed because it could not audit is worse than one that was never audited, and a log that quietly stopped is worse than both. No syslog transport, no webhook, no SIEM connector. `CruxSharedAuditKinds` carries the three kinds that describe the shared machinery itself (`policy.loaded`, `policy.rejected`, `plugin.load.refused`) rather than a product's own business. Pure Dart permanently. |
| [`crux_policy`](packages/crux_policy) | Reader, verifier and precedence resolver for the signed `.crux-policy.json`, plus the `crux-policy` CLI (init / lint / sign / inspect) that is **the entire replacement for an admin console**. Total by construction — no input reaches a `throw`, because the file arrives from a network share and may be anything. Unknown keys are ignored, proven by a test that loads a file from a future schema version. A missing file is *absent* (failing closed bricks a deployment over a typo); a **bad signature refuses the whole file** (failing open is self-granting). Precedence is locked > user > default > built-in — a policy *default* deliberately does not outrank a user's own choice, or it would be a lock with the grey control missing. No Flutter and **no dependency on `crux_license`**, both guarded: three keys must resolve before a licence exists. |
| [`crux_settings`](packages/crux_settings) | The shared `CoreSettings` model and its enums, the `SettingsCodec<T>` interface, and the generic `SharedPreferences`-backed `SettingsService<T>`. |
| [`crux_settings_ui`](packages/crux_settings_ui) | Master-detail Settings shell (`CruxSettingsMasterDetail` — category rail + detail pane, responsive collapse to list→detail) plus grouped-row widgets (`CruxSettingsCard`, `CruxSettingsControlTile`, `CruxSettingsSliderTile`). The host supplies the category list and its own dialog/route wrapper. |
| [`crux_keybindings`](packages/crux_keybindings) | Customizable, shareable keyboard shortcuts generic over `CruxAction`: platform-neutral `KeyBinding`/`KeyModifier` (mod→Cmd/Ctrl, Option↔Alt, literal Ctrl), versioned `KeymapCodec` (diffs-from-default, `.crux-keymap` share files), `KeyBindingResolver`, `findShortcutConflicts`, `formatShortcutLabel`, `KeyBindingsStore`, and the `KeyBindingsEditor` settings UI. Each product keeps its own action enum, defaults, `Intent` subclass, localized labels and Riverpod notifier. |
| [`crux_command_palette`](packages/crux_command_palette) | The VS Code-style `CommandPalette<T extends CruxAction>` widget with fuzzy filtering. |
| [`crux_about_dialog`](packages/crux_about_dialog) | One `CruxAboutDialog` for the whole suite — modal on desktop, full-screen route on mobile. The host supplies branding, build info, strings, icon, attributions and buttons; tier and beta chips come from `crux_license`. |
| [`crux_ide_layout`](packages/crux_ide_layout) | Dockable four-region IDE shell (`CruxIdeLayout`) over `package:panes`. Each app projects its panel state onto the `IdePanelLayout` / `IdePanelLayoutSink` adapters. Also the shared IDE-chrome affordances: `PlatformContextMenu` (long-press = right-click), the `showCruxInfoSnack` / `showCruxErrorSnack` feedback helpers (which also speak through the screen reader, via `announceCrux`), `confirmCruxDestructiveAction`, and keyboard regions — `CruxFocusRegion` / `CruxFocusRegionScope` keep Tab inside a region and move between regions on F6 / Shift+F6. |
| [`crux_dock`](packages/crux_dock) | Cross-suite VSCode-style tabbed dock (`CruxDock`) mounted inside a `CruxIdeLayout` region: tab strip with badges and per-tab close, auto-hiding single-tab header, collapse / maximize / pop-out action cluster, and auto-reveal of newly activated on-demand tabs. Hosts assemble `CruxDockEntry` lists from their own providers. |
| [`crux_theme`](packages/crux_theme) | Named-token color theming: `CruxColorTheme`, the token-category schema, `ThemePack` + codec + install/export service, built-in presets, and the whole Settings → Appearance UI (color picker, token editor, preset picker, pack browser). |
| [`crux_workspace`](packages/crux_workspace) | Workspace, multi-tab and split-pane infrastructure: the generic `Workspace<P>` model, `WorkspaceService<P>` persistence with quarantine, per-tab and per-pane `ProviderContainer` managers, multi-window detachment, and the `PaneHost<P>` / `ViewerTabBar<P>` / `EmptyCanvasState` widgets — including `CruxSuiteFooter` and `CruxSuitePeers`, the suite-membership line and the "More from EDACrux" section every product carries at the foot of its welcome screen. |
| [`crux_updates`](packages/crux_updates) | Update-check mechanism: the fail-soft `UpdateManifest` / `UpdateInfo` model, semver comparison, `UpdateCheckService` seam with `Http` + `Noop` implementations, the `updateStatusProvider` launch/periodic/manual check engine, and the `UpdateBanner` (non-dismissible when `mandatory`). Reports the manifest's `server_time` for `crux_license`'s beta-expiry clock-tampering hardening. |
| [`crux_telemetry`](packages/crux_telemetry) | Anonymous usage-statistics pipeline: the event model, the capped JSON-Lines disk queue, the coalescing batcher that matches the ingestion Worker's payload contract, the never-throwing ingest client and its public ingest URLs, the `kBetaPeriod` × `TELEMETRY_DEV` × Enterprise `TelemetryPolicy` × consent gate, and both consent surfaces. After the beta, collection is default-on with an opt-out; the first-launch toggle arrives off where the locale (or, on web, the time zone) places the machine in the EEA, the UK, Switzerland or South Korea. No event catalog — each product keeps its own. Inert for the whole beta by construction. |
| [`crux_eula`](packages/crux_eula) | First-launch EULA acceptance: the blocking gate, the dialog that scrolls the full agreement and arms Accept behind a checkbox, and a store that records which *version* was accepted so a changed agreement re-prompts. The text is generated from the canonical document rather than retyped. |
| [`crux_issue_reporter`](packages/crux_issue_reporter) | In-app issue reporter: the 500-entry `CruxIssueReporterLogBuffer`, category collection (app & environment, session state, diagnostics, screenshot), markdown report builder, clipboard + pre-filled GitHub-issue launch, and the `CruxIssueReporterDialog`. Session state and Pro-overlay categories arrive through product seams, never product imports. |
| [`crux_window_chrome`](packages/crux_window_chrome) | VS Code-style frameless window chrome for Windows/Linux (macOS keeps its native menu): the `useCustomWindowChrome` predicate, `window_manager` wiring (`initWindowChrome` / `buildWindowFrame` / `buildWindowGeometryPersister`, web-guarded behind a conditional-import facade), the `buildWindowTitleBar` custom title bar (host-supplied `logo`), the `MnemonicMenuBar` left-aligned Alt-access-key menu bar, the `WindowBounds` geometry model, and the portable `requestUserAttention` primitive (dock bounce / taskbar flash / Wayland urgency, no focus-steal). Each host keeps its own `DesktopMenuBar` and feeds it in. |
| [`crux_menu_bar`](packages/crux_menu_bar) | Cross-suite desktop **menu bar** — one declarative `CruxMenuLayout` rendered as the native macOS `PlatformMenuBar` or the in-window VS Code-style Material menu bar on Windows/Linux. Owns separator grouping, platform-idiomatic About/Settings/Quit placement, the macOS application-menu tail and Window menu, and the guard that keeps typing-hostile accelerators out of native key equivalents. |
| [`crux_toolbar`](packages/crux_toolbar) | Cross-suite application **toolbar** — one geometry token set, one button, one divider, one overflow strategy, rendered as `[common] │ [app-specific]` so the shared commands sit in the same place in every product. Includes the grouped split button, the morphing run/stop control, badge counts, and live-binding tooltips. |
| [`crux_heatmap`](packages/crux_heatmap) | The GitHub-contributions-style **calendar heatmap** (`CruxCalendarHeatmap<T>`) LintCrux Pro and SimCrux Pro both render over their trend stores. Layout and interaction only — the host resolves each day's colour and localized tooltip, so the metric being visualised (violation density vs pass rate) stays entirely product-side. |
| [`crux_stats_strip`](packages/crux_stats_strip) | Cross-suite live **statistics strip** — a collapsed-by-default disclosure row above the status bar carrying ambient telemetry (process RSS, frame rate, frames over budget) with sparklines. Ships the rolling frame- and memory-stat providers and a paint-timing probe; hosts add their own product segments. |
| [`crux_a11y`](packages/crux_a11y) | Accessibility workarounds and guards: `CruxSlider` (a `Slider` hosted in its own `Overlay`, so it no longer serializes a semantics node the desktop accessibility bridge rejects when it sits in a dialog or pushed route); `CruxModalGate` and `CruxModalSurface`, which make a surface mounted above the `Navigator` (the licence agreement, the consent disclosure) modal to the keyboard and a screen reader as well as the pointer; `CruxScrollRegion`, a keyboard-scrollable Tab stop for a block of text; and, in `crux_a11y_testing.dart`, two widget-test harnesses: the **focus walk** (`walkFocus`, `expectCleanFocusWalk`, `expectFocusAnnounced`, `expectFocusWalkGolden`, `AnnouncementRecorder`), which presses Tab through a surface and records each stop the way the desktop bridge hands it to NVDA or VoiceOver — failing on silent or nameless stops, one control under two names, unspeakable glyphs and focus that lands nowhere, with a plain-text transcript golden per surface — and `SemanticsOrphanGuard`, which re-implements the bridge's "every node must be claimed" invariant so an orphaned node fails `flutter test` instead of freezing a screen reader or crashing the process. |
| [`crux_status_bar`](packages/crux_status_bar) | Cross-suite bottom **status bar** — a single left-aligned, fixed-height, theme-aware bar mounted at the window bottom by every product so the suite's bottom-of-window chrome is consistent (WaveCrux is the canonical look). Hosts feed it their own segments. |
| [`crux_project`](packages/crux_project) | The `<design>.crux-project` suite design manifest (a named file, so pickers show it — [ADR 0004](docs/adr/0004-crux-project-manifest-is-a-named-file.md)): one checked-in pointer file naming a design's RTL, dump, lint project and regression config, its parser, and the per-product open planner. Exists to enforce one rule in one place — the CXP `design_id` comes from the manifest's *directory*, not from whichever artifact a product opened. Artifact kinds are opaque strings; each product owns its own key. Singular, and distinct from `crux_projects` below. |
| [`crux_projects`](packages/crux_projects) | Multi-project workspace layer: `ProjectDescriptor` identity, the `ProjectWorkspace` snapshot, the `ProjectRegistry` extension point with its `NoopProjectRegistry` open-core default, and the `perProjectScope` helper that stops per-project state bleeding across the project switcher. The persistent registry the Pro overlays install is the paid capability and lives with their private shared code ([ADR 0005](docs/adr/0005-pro-implementations-leave-crux-shared.md)); this package is the seam. |
| [`crux_projects_ui`](packages/crux_projects_ui) | The Flutter chrome over `crux_projects`: the project switcher dialog, the recent-projects panel, and the empty-workspace state. Parameterized by product strings and a tier badge, so SimCrux and LintCrux share one implementation. |
| [`crux_secrets`](packages/crux_secrets) | A narrow read/write/delete seam over the OS keychain (Keychain on macOS, DPAPI-backed credential storage on Windows, libsecret on Linux), plus an in-memory fake for tests. The place credentials go when `shared_preferences` plain text would be wrong — SimCrux PR-annotation auth tokens and the Enterprise shared-team database password. |
| [`crux_file_watcher`](packages/crux_file_watcher) | File-system watcher with debounced events. |

## Layout

```
crux-shared/
├── analysis_options.yaml      # very_good_analysis at workspace root
├── pubspec.yaml               # Workspace-root pubspec (workspace members + melos config)
├── packages/                  # One directory per package — see the tables above
├── api/                       # Committed public-API goldens, one per package (see api/README.md)
├── tool/                      # Repo checks: api-snapshot.sh, check-consumers.sh, check-cxp-version.sh,
│                              #   coverage.sh, spdx-headers.py, gen-notices.py, supply-chain.py,
│                              #   no-bundled-engines.py; the unused-exports.py report; plus
│                              #   country-names.sh (a data map, not a check)
├── docs/adr/                  # Architecture decision records for cross-suite conventions
├── .github/workflows/ci.yml   # Analyze + test + API goldens, supply chain (licences, SBOM,
│                              #   advisories), per-package coverage floors
├── .github/workflows/consumers.yml
│                              # Analyze all four products against every commit here
└── .github/workflows/release-crux-policy.yml
                               # The one artifact in this repo a customer runs: builds, signs,
                               #   notarizes and publishes the `crux-policy` administrator CLI
```

## Repo docs

- [`docs/adr/`](docs/adr/) — architecture decision records for conventions that span the suite (filename shapes, persistence formats, protocol choices). [`docs/adr/README.md`](docs/adr/README.md) is the index.
- [`api/README.md`](api/README.md) — what the public-API goldens are and how to regenerate them.
- [`CLAUDE.md`](CLAUDE.md) — the contributor-facing charter: scope rules, versioning contract, deprecation policy, coding conventions.

## Local development

```bash
# Install Melos once
dart pub global activate melos

# From the repo root
melos bootstrap        # pub get for every package
melos run analyze      # dart analyze --fatal-infos --fatal-warnings everywhere
melos run test         # tests for every package (dart test or flutter test as appropriate)
melos run format-check # verify formatting

# Outside Melos
tool/api-snapshot.sh --check   # are the public-API goldens current? (CI runs this)
tool/api-snapshot.sh --write   # regenerate after an intentional API change
tool/check-consumers.sh        # analyze all four products against this working tree
python3 tool/unused-exports.py # which exported symbols no consumer checkout references (a report)
```

CI runs on every push to `main`, every pull request, nightly, and on manual dispatch. Beyond the workspace's own format/analyze/test, it checks SPDX headers and third-party attributions, runs the browser-only tests of `crux_policy`, `crux_cxp`, `crux_io` and `crux_telemetry` in Chrome, verifies the API goldens, and enforces `crux_cxp`'s semver discipline; a `consumers` job checks out each of the four products and analyzes it against the commit under test — the job that actually catches a breaking change — a `supply-chain` job gates licences and advisories and writes an SBOM, and a `coverage` job holds every package to its own floor.

## Relationship to the suite

The suite's repositories, and which way the dependencies point:

```
crux-shared/   (this repo — private during beta, public Apache 2.0 post-beta)
wavecrux/      (open core — private during beta, public Apache 2.0 post-beta)
netcrux/       (same)
lintcrux/      (same)
simcrux/       (same)
```

Each open-core product repo holds `crux-shared` as a Git submodule of itself (e.g. `wavecrux/crux-shared/`), so each open core is buildable standalone — its consumers don't need to know about the suite structure. Each product's closed Pro overlay consumes its open core as a submodule and inherits `crux-shared` transitively through it.

Because there is no version solver between this repo and its consumers — every dependency is a bare `path:` into the submodule — **the submodule SHA is the compatibility contract**, and package `version:` fields are informational. `crux_cxp` is the exception: it goes to pub.dev at the flip and carries real semver discipline today. See [`CLAUDE.md`](CLAUDE.md) § "Versioning contract" and § "Deprecation policy".

## License

`crux-shared` is licensed under the Apache License 2.0 — see
[`LICENSE`](LICENSE) for the full text and [`NOTICES`](NOTICES) for
third-party attributions. Contributions require a signed Contributor
License Agreement ([`CLA.md`](CLA.md)) — see
[`CONTRIBUTING.md`](CONTRIBUTING.md).

Apache-2.0 §6 grants no trademark rights, so the names and logos are
covered separately — see [`TRADEMARK.md`](TRADEMARK.md).
