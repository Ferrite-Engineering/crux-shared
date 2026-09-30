# crux-shared

Shared infrastructure for the EDACrux suite: the cross-product Dart packages that WaveCrux, NetCrux, LintCrux and SimCrux all build on.

## What this repo is

Melos workspace containing the cross-product Dart packages every product in the suite depends on.

**Visibility & license:**

- **License:** **Apache License 2.0**, already in the tree — `LICENSE`, `NOTICES`, and an SPDX header on every source file. CI checks the headers (`tool/spdx-headers.py`) and the third-party attributions (`tool/gen-notices.py`) on every run.
- **Visibility:** private during the public beta, matching every product repo in the suite; public at the post-beta open-core flip, in lockstep with the four open-core product repos. Aligning with the open-core products' license is necessary because each product's open-core repo consumes `crux_shared` from `pubspec.yaml`; once those repos go public, this repo has to go public too or the dependency chain breaks. Apache 2.0 also gives third-party tools a clean legal path to build CXP-compatible products against `crux_cxp`, which is an explicit ecosystem goal.

Packages today (the authoritative list is `ls packages/` — keep this table in step with it):

| Package | Flutter? | Purpose |
|---|---|---|
| `crux_async` | pure Dart | Async/timing primitives: `Debouncer`, coalescing a burst of calls into one trailing invocation (`run` cancels-and-reschedules, `cancel` drops a pending call, `flush` runs it immediately, `dispose` cancels and must be called by the owner). Lifted from `lintcrux/lib/core/util/debouncer.dart`, the only debouncer in the suite, once an audit found two products with the cancel/dispose bugs a shared implementation is meant to make hard to repeat: a filter field documented as debounced that fired on every keystroke, and a Clear action that left a pending call free to undo it. `dart:async` only, no dependency on any other Crux package. |
| `crux_io` | pure Dart | Filesystem and process primitives every persistence layer and spawn site goes through: crash-safe atomic file replacement (`writeStringAtomic` / `writeJsonAtomic` + `WriteDurability`), path identity (`canonicalizePath` / `canonicalPathKey` / `isSamePath` / `filesystemIsCaseInsensitive`), engine `PATH` augmentation (`engineSearchDirs` / `appendMissingPathDirs`), spawn resolution (`requireSpawnExecutableForHost` / `requireSpawnExecutable` / `SpawnHost`, their lenient `resolve…` twins, and `isAbsoluteSpawnPath`), and `revealInFileManager`. Pure-Dart **leaf**: depends on no other Crux package, so any package may depend on it without creating a sibling edge. Deliberately tiny — see the atomic-write, path-identity and spawn conventions below. |
| `crux_sqlite` | pure Dart | **The one SQLite open path in the suite.** A store supplies a migration list, a data-value declaration and a path; this package supplies everything else: `CruxMigration` / `CruxMigrationRunner` (append-only, additive-only, latest version **derived** from the list length — there is no constant to forget to bump), `CruxSqliteOpenPolicy` (the only place an `OpenDatabaseOptions` is constructed — `onCreate` and `onUpgrade` routed through one loop so a fresh install and an upgraded one converge, an `onDowngrade` that always refuses, the mandatory 5 s `busy_timeout`), `CruxDbRecovery` (`renameAside` / `refuse` / `recreate` — the PRECIOUS-vs-DERIVABLE policy as an argument a reviewer sees, not a docstring that goes stale), `CruxPreUpgradeBackup` (a size- and free-space-guarded copy taken before any upgrade), and the sealed `CruxSqliteException` family — corruption, migration failure, schema-version skew, backup failure — where four stores used to have one anonymous exception. Also `isSqliteCorruption` — which deliberately excludes `SQLITE_BUSY`/`LOCKED`/`READONLY`/`CANTOPEN`, because reading lock contention as corruption destroys data that was never damaged — and `quarantineDatabaseFile`, which never deletes. **Pure Dart permanently** (both products' headless `dart build cli` binaries write these databases; guarded by `no_flutter_dependency_test.dart`, which walks the whole dependency closure). The rules it implements are written down in `packages/crux_sqlite/README.md` ("The migration rules"), which every guard failure cites through `kCruxMigrationGuideRef`; WAL is deliberately not adopted and foreign-key enforcement deliberately stays off, both reasoned on `CruxSqliteOpenPolicy`. Two test-side entry points never enter the runtime barrel: `crux_sqlite_test_support.dart` (the shared data-preserving migration fixture loop) and `crux_sqlite_guards.dart` (the static scanners each product points at its own stores from `test/static/`). |
| `crux_linux_integration` | pure Dart | Linux AppImage first-run desktop self-integration: `LinuxDesktopApp` config, `LinuxDesktopApp.fileTypes` / `LinuxMimeType` (the host's own declared types, the system types it only names, and the extensions it deliberately leaves alone) with `buildMimePackage` and the `checkLinuxMimeCoverage` guard, `buildDesktopEntry`, and `DesktopIntegrator` / `maybeIntegrateDesktopEntry` — writes the entry's `MimeType=` **and** the `shared-mime-info` package that makes it resolve (without which a file manager types the file as JSON and never offers the app), honours `$XDG_DATA_HOME`, removes a package the app no longer declares, and writes each app's `.desktop` entry + hicolor icons into `~/.local/share` so a Wayland/GNOME dock can match the running window (`StartupWMClass` = app id) to a host-side desktop entry. Idempotent (marker under `~/.local/share/crux/`), guarded to `Platform.isLinux` + `$APPIMAGE`, best-effort `update-desktop-database` / `gtk-update-icon-cache`, never throws. Called from each open-core `bootstrap()`. |
| `crux_shortcut_action` | pure Dart | The two-symbol vocabulary every other action-aware package is generic over: the `CruxAction` interface each product's action enum implements, and the `ActionCategory` grouping enum. Zero dependencies. |
| `crux_app_info` | pure Dart | About-box extension-point models: `ApplicationBuildInfo` and `ApplicationBranding`. The edition chip is `EditionBadge`, in `crux_license`. The providers and widgets that consume them are layered in by each product (or by `crux_about_dialog`). |
| `crux_yosys` | pure Dart | Yosys subprocess infrastructure: `YosysRunner` (spawn `yosys`, capture `write_json`; VHDL sources are first lowered to Verilog by a standalone `ghdl --synth --out=verilog`, never the Yosys GHDL plugin), `YosysAvailabilityService`, `YosysDiagnosticParser`, and the tool-neutral `ProcessRunner` / `ProcessRegistry` subprocess seam. Consumed by NetCrux and LintCrux. |
| `crux_netlist` | pure Dart | The suite's shared elaborated-design model: a pure mirror of the Yosys `write_json` document, plus its parser. The output half of what `crux_yosys` runs — NetCrux's schematic and LintCrux's CDC engine read the same model instead of parsing the same JSON twice. Sanctioned to carry that vocabulary by being the elaboration model itself; the charter guard matches whole words, so `NetlistModel`-style identifiers do not trip it. |
| `crux_cxp` | pure Dart | Cross-Tool eXchange Protocol bindings — the same-machine, localhost-TCP cross-probe gossip layer that lets Crux apps (and third-party tools) reconcile element identity across products. Wire format, line framing, message types, client, server, discovery, peer-manifest directory, and a conformance suite. `sharedCxpManifestDirectory` reads the environment through a conditional export, so a web build gets its documented `StateError` ("discovery unavailable") rather than a `dart:io` `UnsupportedError` — proven in Chrome by `packages/crux_cxp/test/web/cxp_manifest_directory_web_test.dart`. **The one package slated for pub.dev** — see the versioning contract below. |
| `crux_cxp_ui` | Flutter | The Flutter companion to `crux_cxp`: the one shared docked **cross-probe side-panel** all four products adopt (Connected Peers with per-peer direct send, Unreachable peers, Recent Events incl. selection-received + open-artifact), the app-agnostic `CrossProbePanelController` contract the widget renders against, and the shared sender-failure toast. Domain-neutral — carries CXP element vocabulary only, never a single-product noun. |
| `crux_license` | Flutter | Cross-suite license vocabulary and gating: `LicenseTier` (+ `featureEquivalent` EDU-as-Pro mapping), `FeatureGate`, `licenseTierProvider`, the `kBetaPeriod` / `kBetaExpiry` build flags and their beta-expiry state machine, the `kAiExperimental` AI-gating flag and its providers, and the `FeatureTierBadge` / `EditionBadge` chips. `CruxLicenseValidator` verifies here, in `crux-shared`, against a set of trusted issuers — the signing key is Keygen's and never ships, so a build carries only an account id and a public verify key, neither of which is a secret. The Ed25519 primitive itself now lives in `crux_signing`. Not a JWT: a Keygen `ED25519_SIGN` key is a signed payload carrying a policy id, resolved offline through the generated policy table. The rest of the licence lifecycle is here too: `KeygenLicenseClient` and `CruxLicenseController` (activation, periodic validation, `LicenseGracePolicy`), the `CruxLicensePanel` Settings category, `CruxUpgradeDialog`, and the `.crux-policy.json` day-one licence binding (`applyPolicyLicense`). Each Pro overlay supplies only its own `LicenseService` and `LicenseStore`, wired in by overriding `licenseStatusProvider`, `licenseActionsProvider` and `licenseTierProvider`; open core keeps the defaults, `CruxLicenseStatus.openCore` and `UnsupportedLicenseActions`. Second entry point `crux_license_core.dart` is the Flutter-free subset (tiers, `FeatureGate`, build flags, beta expiry, validator seam) that headless `dart build cli` binaries import; the main barrel drags in `dart:ui`. `CruxAuditRecorder` + `cruxAuditRecorderProvider` are the emit side of `crux_audit`: they stamp `product` and the CXP `peerId` so a call site names only its own kind and payload, and `record()` returns void — an audit write must never turn a synchronous call site into an asynchronous one, and a sink that throws is caught here rather than reaching the zone as an unhandled async error. |
| `crux_signing` | pure Dart | **Ed25519 signature verification, and nothing else.** Extracted from `crux_license` so the suite has exactly one verifier rather than one per consumer — grep proves it. Hand-written from RFC 8032 §5.1.7 rather than taken from `package:cryptography`, and the reason is legal rather than technical: that package ships AES-GCM and ChaCha20, and a cipher anywhere in `crux-shared` ends open core's freedom from non-exempt encryption for export control, and makes every store listing's `ITSAppUsesNonExemptEncryption=false` untrue. Verification is not encryption, which is the whole reason this package can exist here at all. **The public surface is one verify entry point: no signing, no key generation, no key agreement.** Signing a policy file is the organization's job with the organization's own key, and that signer ships in no product build. Not constant-time, deliberately — every input (signature, message, public key) is public by design, so there is no secret to leak through a timing channel. Pure Dart permanently, guarded by `no_flutter_dependency_test.dart`. |
| `crux_audit` | pure Dart | The shared audit envelope (`AuditEvent`, `AuditSeverity`, `AuditVerbosity`), the `AuditSink` seam, `NoopAuditSink`, and `JsonlAuditSink` — append-only JSON lines, timestamp first so `sort` and `grep` work without a tool from us. **Event KINDS are per-product plain strings**, registered by the product; only the envelope is fixed, so one file holding four products' events is still one parseable stream. **Rotation is deliberately not implemented**: the sink opens/appends/closes per event, so `mv`-then-recreate and copy-truncate both work with no staleness detection at all — and audit events are human-paced, so the syscalls are irrelevant next to correctness under somebody else's logrotate. `maxBytes` is a safety valve against filling a disk, not a rotation policy; it refuses to grow and reports unhealthy, and never deletes. Failure policy: **degrade loudly, never throw** — `AuditSinkHealth` is what a settings panel shows, and the first failure is logged exactly once so a full disk cannot produce a second log that fills what is left. No syslog, no webhook, no SIEM connector — an organization points its own log shipper at the file (<https://edacrux.app/audit-log#shipping>), and that is the whole design. `CruxSharedAuditKinds` is the one exception to kinds-are-per-product: `policy.loaded` / `policy.rejected` / `plugin.load.refused` describe the shared machinery rather than anything a product does, and four spellings of "the policy file was rejected" would make a shared file unfilterable for exactly the events an administrator most wants to find. |
| `crux_policy` | pure Dart | `.crux-policy.json` — parse, verify, resolve — and the `crux-policy` CLI in `bin/`. The normative contract is the policy file reference, <https://edacrux.app/policy-reference>; **where they disagree the reference wins and this is the bug.** Parsing is total (`PolicyDocument.parse` never throws). `PolicyLoader.load` never throws, on the web included: `dart:io` sits behind a conditional export (`policy_host.dart`), a browser has no environment and no file, so the answer there is absent — `packages/crux_policy/test/policy_loader_web_test.dart` proves it in Chrome, as its own CI step. Loading order is `CRUX_POLICY` → well-known per-platform path → absent, first hit wins, **never merged** — merging would leave an administrator debugging a value whose source they cannot see. Signature verification is against the **organization's own** key via `crux_signing`; we hold no key here and must never appear to. Two failures that look alike and are not: missing/unreadable/malformed → absent, bad signature → refuse the file. An unsigned file is honoured only from the trusted well-known path, and not even there when that location is writable by every user (`insecurePath`); an unsigned `CRUX_POLICY` file is refused whatever the key state (`untrustedUnsigned`) — a key widens what a *signed* file may do, never what an unsigned one may. The organization key is read only from `crux-policy.pub` beside the well-known file (ignored when world-writable), never from the environment; a signed file with no usable key is refused (`noPublicKey`), and `keyStatus` says why there was no key. Precedence is **locked > user setting > policy default > built-in**: a default that outranks the user cannot be departed from, making it a lock whose control forgot to grey itself. An invalid value is skipped, reported, and falls back to the *user's* setting rather than inventing one. **The signer lives in `tool/`, reachable only from `bin/` and not exported** — no product build may contain signing code. No Flutter and no `crux_license` edge, both guarded on every run. |
| `crux_file_watcher` | Flutter | File-system watcher with debounced events. Uses `package:flutter/foundation.dart` for `kIsWeb`. |
| `crux_settings` | Flutter | The shared `CoreSettings` model + its enums (`AppThemeMode`, `AutoReloadMode`, `OrientationLockMode`), the `SettingsCodec<T>` interface, `CoreSettingsCodec`, and the generic `SharedPreferences`-backed `SettingsService<T>`. |
| `crux_settings_ui` | Flutter | Master-detail Settings panel shell (`CruxSettingsMasterDetail` — category rail + scrolling detail pane, responsive collapse to list→detail) plus grouped-row widgets (`CruxSettingsCard`, `CruxSettingsControlTile`, `CruxSettingsSliderTile`). Domain-neutral chrome; the host supplies the category list. |
| `crux_keybindings` | Flutter | Customizable keyboard-binding system, generic over `CruxAction`: platform-neutral `KeyBinding`/`KeyModifier` (mod→Cmd/Ctrl, Option↔Alt, literal Ctrl), versioned `KeymapCodec` (diffs-from-default, `.crux-keymap`), `KeyBindingResolver`, `findShortcutConflicts`, `formatShortcutLabel`, the `SharedPreferences`-backed `KeyBindingsStore`, and the editor widgets (`KeyBindingsEditor`, `KeyBindingRow`). See the note below on what has *not* migrated. |
| `crux_command_palette` | Flutter | VS Code-style `CommandPalette<T extends CruxAction>` widget with fuzzy filtering, plus its `ScrollWrapperBuilder` / `ShortcutActivatorLabel` seams. |
| `crux_about_dialog` | Flutter | One `CruxAboutDialog` for the whole suite — modal on desktop, full-screen route on mobile. The host supplies branding, build metadata, chrome strings, icon, attribution sections and action buttons; tier and beta state come from `crux_license`. |
| `crux_ide_layout` | Flutter | Dockable four-region IDE shell (`CruxIdeLayout`) over `package:panes`. Each app projects its own panel state onto the `IdePanelLayout` (read) + `IdePanelLayoutSink` (write) adapters; the shared widget owns the controller, resizer theme and visibility/size sync. Also the shared IDE-chrome affordances: `PlatformContextMenu` (long-press = right-click), `showCruxInfoSnack` / `showCruxErrorSnack` (both also announce through the screen reader via `announceCrux`, because the desktop bridges ignore live regions), `confirmCruxDestructiveAction`, and the keyboard regions `CruxFocusRegion` / `CruxFocusRegionScope` (Tab stays inside a region; F6 / Shift+F6 move between regions; `CruxIdeLayout` makes each pane a region and keeps the `panes` resizers out of the Tab order). |
| `crux_dock` | Flutter | Cross-suite VSCode-style tabbed dock (`CruxDock`) for `CruxIdeLayout` regions. `CruxDockEntry.onClose` carries the presence semantics (pinned vs. on-demand); the strip auto-hides to a titled header with one pinned entry; `CruxDockPopOut` is the rendered-but-disabled multi-window affordance. Provider-agnostic, no localizations — hosts pass labels/tooltips in. |
| `crux_theme` | Flutter | Named-token color theming: `CruxColorTheme`, the `ThemeTokenCategory` / `ThemeTokenDescriptor` schema, `ThemePack` + `ThemePackCodec` + `ThemePackService`, built-in presets, `ThemeRegistry`, `cruxColorThemeProvider`, `CruxThemeExtension`, and the full Settings → Appearance UI (color picker, token editor, preset picker, theme-pack browser). |
| `crux_window_chrome` | Flutter | VS Code-style frameless window chrome for Windows/Linux (macOS keeps its native menu): the `useCustomWindowChrome` predicate, `window_manager` wiring (`initWindowChrome` / `buildWindowFrame` / `buildWindowGeometryPersister`, web-guarded), the `buildWindowTitleBar` custom title bar, the `MnemonicMenuBar` left-aligned Alt-access-key menu bar, the `WindowBounds` model, and the portable `requestUserAttention` primitive (dock bounce / taskbar flash / Wayland urgency). |
| `crux_menu_bar` | Flutter | Cross-suite desktop **menu bar**: one declarative `CruxMenuLayout` rendered as the native macOS `PlatformMenuBar` or the in-window VS Code-style Material menu bar on Windows/Linux. Owns separator grouping, platform-idiomatic About/Settings/Quit placement, the macOS application-menu tail and Window menu, and `nativeMenuShortcut` — which refuses to publish an unmodified accelerator to the macOS menu, where `NSMenuItem` key equivalents are matched ahead of the focused text field. |
| `crux_toolbar` | Flutter | Cross-suite application **toolbar**: `CruxToolbarMetrics` (40/36/18 desktop, 48/48/24 touch), `CruxToolbar` rendering `[common] │ [app-specific]` with a stable auto-hiding overflow slot, `CruxToolbarSplitButton` (a grouped tool button so a cluster of related commands earns one slot instead of none), `CruxRunStopButton`, badge counts, and `cruxToolbarTooltip`, which appends the user's live binding rather than baking the chord into the label. |
| `crux_heatmap` | Flutter | The GitHub-contributions-style **calendar heatmap** (`CruxCalendarHeatmap<T>` + `CruxHeatmapCell<T>`) shared by LintCrux Pro and SimCrux Pro. Owns the date-grid layout, the week-column offset arithmetic and the tap/tooltip wiring; the host supplies each cell's resolved colour and localized tooltip. `tooltip` is required, not optional — a cell has no visible text, so it is the only thing a screen reader can announce. No localizations, no providers. |
| `crux_stats_strip` | Flutter | Cross-suite live **statistics strip**: a collapsed-by-default disclosure row that docks above the status bar and carries ambient telemetry — process RSS, frame rate, frames over budget — with sparklines. Owns the rolling frame/memory stat providers (memory sampling is demand-gated, so it costs nothing while nobody is looking) and a `RenderProxyBox` paint-timing probe. Hosts supply their own product segments. |
| `crux_a11y` | Flutter | Accessibility workarounds and guards. `CruxSlider` hosts a `Slider` in its own `Overlay` so the value-indicator portal no longer serializes an unclaimed semantics node inside dialogs and pushed routes (the desktop accessibility bridge rejects the update and freezes the native tree). `CruxModalGate` / `CruxModalSurface` make a surface that cannot be a route (mounted above the `Navigator`) modal to the keyboard and a screen reader, and `CruxScrollRegion` makes scrolling text a keyboard-scrollable Tab stop; `crux_eula` and `crux_telemetry` build their blocking surfaces on them. `crux_a11y_testing.dart` ships two harnesses: the focus walk (`walkFocus` / `FocusWalk` / `expectCleanFocusWalk` / `expectFocusAnnounced` / `expectFocusWalkGolden` / `AnnouncementRecorder`), which presses Tab through a surface and records what a desktop screen reader hears at each stop, and `SemanticsOrphanGuard` / `SemanticsOrphanTestBinding` / `SemanticsOrphanRecording`, which mirrors the bridge's claimed-node invariant in Dart. Depends on `flutter_test` on purpose: the harnesses are the product. |
| `crux_status_bar` | Flutter | Cross-suite bottom **status bar**: one left-aligned, fixed-height, theme-aware bar mounted at the window bottom by every product so the suite's bottom-of-window chrome is consistent (WaveCrux is the canonical look, 24 dp / monospace). Hosts feed their own segments. |
| `crux_workspace` | Flutter | Workspace + multi-tab + split-pane infrastructure: the generic `Workspace<P>` model, `WorkspaceService<P>` persistence with quarantine, the `WorkspaceCodec.identityOf` duplicate-tab seam and the `WorkspaceNotifier.shouldRestoreOnLaunch` restore gate, per-tab and per-pane `ProviderContainer` managers, multi-window detachment scaffolding, and the `PaneHost<P>` / `ViewerTabBar<P>` / `EmptyCanvasState` widgets. `EmptyCanvasState`'s `footer` slot plus `CruxSuiteFooter` and `CruxSuitePeers` are the one implementation of the suite-membership line and the "More from EDACrux" section all four welcome screens render; the words and the destination URLs are per-product and stay with the product (the package takes labels and callbacks, and deliberately no `url_launcher`). `CruxSuiteProduct` is the welcome screen's product identity — name, slug, brand colour — held to `crux_license`'s `CruxProduct` by a test that takes crux_license as a dev dependency so the runtime does not. |
| `crux_updates` | Flutter | Update-check mechanism: fail-soft `UpdateManifest` / `UpdateInfo`, semver comparison, the `UpdateCheckService` seam plus `HttpUpdateCheckService` / `NoopUpdateCheckService`, `updateStatusProvider` (launch + periodic + always-on manual check), and `UpdateBanner` / `UpdateAvailableBanner`. Product config arrives via `cruxUpdateConfigProvider`; strings via `CruxUpdateStrings`. Emits the manifest `server_time` through `observedServerTimeSinkProvider` for `crux_license`'s beta-expiry clock-tampering hardening. |
| `crux_telemetry` | Flutter | Anonymous usage-statistics pipeline: `TelemetryEvent`, the JSON-Lines disk queue with its 2000-event / 7-day caps, the coalescing batcher that matches the ingestion Worker's payload contract, the never-throwing `LiveTelemetryService` (and its `Noop` and `Pending` twins), the public production and staging ingest URLs, the `kBetaPeriod` × `TELEMETRY_DEV` × Enterprise `TelemetryPolicy` × consent gate, and both consent surfaces (`TelemetryConsentGate` + `TelemetrySettingsSection`). After the beta, collection is default-on with an opt-out; the first-launch toggle arrives off where the locale (or, on web, the time zone) places the machine in the EEA, the UK, Switzerland or South Korea. Product config arrives via `cruxTelemetryConfigProvider`; strings via `CruxTelemetryStrings`; persistence via `telemetryStorageProvider`. Carries **no event catalog** — that is the one genuinely per-product part, and it stays in each product with its own conformance test. Inert for the whole beta by construction. |
| `crux_eula` | Flutter | First-launch **EULA acceptance**. `CruxEulaGate` blocks the routed content until the agreement is accepted and renders its child untouched afterwards; `CruxEulaAcceptanceDialog` scrolls the full text, arms Accept behind a checkbox, and restates section 3's promise that accepting is not a condition of any open-source licence. `CruxEulaAcceptanceStore` persists the **version** accepted, never a bool, so raising `kCruxEulaVersion` is what re-prompts under section 2.3. `eula_document.dart` is generated by `tool/generate-eula-document.py` from the agreement's markdown, passed in; the published text is at https://edacrux.app/eula. Mounts outside `TelemetryConsentGate` and inside any beta-expiry gate. English only, by decision — a translated EULA would be nine more legal texts able to drift from the one that binds. |
| `crux_issue_reporter` | Flutter | In-app issue reporter: `CruxIssueReporterLogBuffer` (500-entry ring, `logging` + `FlutterError` capture), `CruxIssueReporterService` (category assembly, markdown body, new-issue URL, clipboard, screenshot reveal), and `CruxIssueReporterDialog`. Two product seams — `cruxIssueSessionContextProvider` (the product's own session state) and `cruxIssueReporterDataProviderProvider` (the Pro overlay's extra categories). Config via `cruxIssueReporterConfigProvider`; strings via `CruxIssueReporterStrings`. |
| `crux_project` | pure Dart | The `<design>.crux-project` suite design manifest: `CruxProjectManifest`, `CruxProjectParser`, and `CruxProjectOpenPlanner`. One checked-in pointer file naming a design's RTL, dump, lint project and regression config, so opening a design in four products is one ritual instead of four. **A named file, never a bare dotfile** (`docs/adr/0004-crux-project-manifest-is-a-named-file.md`): `isManifestPath` matches the `crux-project` extension, the legacy `.crux-project` is read for one release with a deprecation warning, and a directory holding more than one manifest is refused by name (`CruxProjectAmbiguousException`) rather than guessed at. The load-bearing reason it is shared rather than copied: the CXP `design_id` must be derived from the manifest **directory** by every product, or cross-probe between manifest-opened designs silently stops joining. **Artifact kinds are opaque strings** — the charter keeps single-product nouns out of shared code, so each product owns the constant for the key it consumes. **Singular — not `crux_projects`**, which is the unrelated multi-project workspace layer directly below. |
| `crux_projects` | Flutter | Multi-project workspace layer: `ProjectDescriptor` stable identity, the `ProjectWorkspace` snapshot, the `ProjectRegistry` extension point with its `NoopProjectRegistry` open-core default, and the `perProjectScope` Riverpod helper that stops per-project state bleeding across the project switcher. The persistent multi-project registry the Pro overlays install is **not here** — it is the paid capability, and ADR 0005 moved it to the overlays' private shared code; this package is the seam it plugs into. |
| `crux_projects_ui` | Flutter | The Flutter chrome over `crux_projects`: the project switcher dialog, the recent-projects panel, and the empty-workspace state. Parameterized by product strings and a tier badge rather than importing either product, so SimCrux and LintCrux consume one implementation. Depends on `crux_projects`; carries no registry logic of its own. |
| `crux_secrets` | Flutter | Cross-suite secret storage: a narrow read/write/delete seam over the OS keychain (Keychain on macOS, DPAPI-backed credential storage on Windows, libsecret on Linux) via `flutter_secure_storage`, plus an in-memory fake for tests. Consumed wherever a credential must never reach `shared_preferences` plain text — the licence credential in every Pro overlay, WaveCrux's AI-assistant API key, SimCrux PR-annotation auth tokens, and the Enterprise shared-team database password in SimCrux and LintCrux. |

**These are not skeletons.** An earlier revision of this file described `crux_license`, `crux_cxp` and `crux_app_info` as "wired up enough to compile, analyze and test; concrete logic lands in later phases". That has not been true for a long time: `crux_cxp` is a complete protocol implementation with a conformance suite, and `crux_license` ships a working `FeatureGate`, beta-expiry state machine, badge widgets, and the cryptographic `CruxLicenseValidator` itself. The licence *lifecycle* is here as well, not in the overlays: activation against Keygen, machine identity, the grace windows and the re-validation cadence are `KeygenLicenseClient`, `LicenseMachineIdentity`, `LicenseGracePolicy` and `CruxLicenseController`, all in `crux_license`. What remains a seam is narrow — each Pro overlay supplies its own `LicenseStore` (the credential-store namespace) and a thin service that constructs the shared controller with the product's identity and commerce URLs, then overrides `licenseStatusProvider`, `licenseActionsProvider` and `licenseTierProvider`; open core leaves all three at their no-licence defaults. Nothing in that seam is secret. The closed half of the suite is the paid features, not the plumbing that gates them.

## Scope rules

- **Only suite-wide EDA infrastructure lives here:** code that more than one product actually uses. Anything specific to a single product's domain model — waveform rendering, netlist graphs, lint rule engines, test orchestration — belongs in that product repo. **The test is consumption, not vocabulary:** `crux_yosys` names HDL languages because Yosys elaboration is shared tooling two products invoke (NetCrux and LintCrux), not because it models any one product's domain.
- **Pure Dart packages preferred. Flutter packages allowed when needed.** Each package picks its own SDK constraint; the table above records which is which. Prefer pure Dart unless a Flutter-only API is genuinely required — twelve packages manage it (the table marks them). Five are guarded by test: `crux_cxp` (`no_riverpod_dependency_test.dart`, which also refuses a Flutter dependency) because a pub.dev consumer should not be forced to take Flutter, and `crux_sqlite`, `crux_signing`, `crux_audit` and `crux_policy` (`no_flutter_dependency_test.dart`, over the whole dependency closure) because the headless `dart build cli` binaries import them.
- **Packages are extracted, not authored greenfield.** Almost everything here was lifted from a shipping product once a second product needed it. Keep doing that: a package extracted on one consumer freezes an API that is still moving.
  - **`crux_keybindings` is partially migrated, in a specific way.** The neutral core (model, codec, resolver, conflicts, label), the `SharedPreferences`-backed `KeyBindingsStore`, **and the editor widgets** (`KeyBindingsEditor`, `KeyBindingRow`, and the internal `ShortcutCaptureField`) all live here. What has **not** migrated is the **Riverpod notifier** — the package contains no Riverpod at all, and each product still owns the notifier that drives the store. Each product also keeps its action enum, `defaultBindings()`, `Intent` subclass and localized labels. `KeyBindingsEditor` takes a `categoryCardBuilder` so the host supplies its own card chrome; drop it into a `CruxSettingsCategory` from `crux_settings_ui`.
  - **`crux_session`** (not extracted) — the real-time multi-peer **session-sync transport** behind Collaborative Viewing, an Enterprise feature. It does **not** exist in this repo; it is a registered extraction whose trigger has fired and whose extraction has not been done. **Not to be confused with CXP** (`crux_cxp`): CXP is same-machine, localhost-TCP, cross-*product* probe gossip; `crux_session` is cross-*machine*, cross-*user* shared viewing over WebSocket with LAN mDNS discovery + a WAN relay. Disjoint problems, disjoint transports.
    - **Shareable (→ here):** the versioned JSON envelope + version gate, the `CollabTransport` interface + `WebSocketCollabTransport`, mDNS/DNS-SD discovery, the relay *client* + WAN room-code logic, and the neutral participant / session-state model. Pure domain-neutral mechanism — its value does not depend on secrecy (same test that puts `crux_cxp` in the open).
    - **Product-specific (stays in each product):** the typed sync *payload* — WaveCrux syncs cursors/viewport/markers/waveform-identity-hash; NetCrux syncs cursors, selected element ids, and the hierarchy scope plus a netlist content hash.
    - **Pro-overlay-only (never here):** the Enterprise feature gate + license enforcement, the relay **server**, and the end-to-end frame encryption both overlays carry (`collab_crypto.dart`). A cipher in crux-shared fails `no_bundled_encryption_test.dart` and the export-control position it encodes, so the sealing layer cannot come here even though the transport under it can.
    - **Precedent note:** this would be the **first crux-shared package lifted from a Pro overlay** rather than from open-core. That is consistent with the charter (the shared mechanism is non-secret), but it is a deliberate first — call it out when the extraction lands.
    - **Extraction trigger:** do **not** extract on one consumer; lift it the way `crux_keybindings` was, from a proven implementation, once a *second* product needs collaborative viewing. That has happened: NetCrux Pro hosts sessions on WaveCrux's protocol with its own copy of the transport, discovery and settings, so the suite now carries two, one in each of those Pro overlays.

## What is allowed to be public after the open-core flip

Everything in this repo is intended to be public when the flip happens. There is no "private subset" of `crux_shared` — sensitive material stays in the per-product Pro overlays, not here. Specifically:

- **License-key cryptography:** the Keygen account id and Ed25519 verify key compiled into `crux_license` are public by design (they are in every distributed binary). The signing **private** key is generated and held by Keygen and is in no repository or CI secret store; `open_core_purity_test.dart` fails if any code a product build can reach gains the ability to sign. The one signer here — the `crux-policy sign` subcommand's, in `crux_policy/tool/` — signs an organization's policy file with the organization's own key, ships in no product, and is the guard's single named exemption.
- **CXP protocol bindings:** the wire protocol is already planned to be public. The Dart bindings being public is a direct continuation of that intent.
- **About-box models, file-watcher, future shared infrastructure:** pure mechanism, no domain secrets.

If anyone proposes adding a piece of code here whose value depends on staying secret, that's a signal it belongs in a Pro overlay instead — or, when more than one overlay needs it, in the private Pro-tier shared repository ([ADR 0005](docs/adr/0005-pro-implementations-leave-crux-shared.md)). The test is [ADR 0002](docs/adr/0002-pro-only-consumers-of-shared-packages.md)'s, applied per package: a package that *is* the paid capability leaves; a mechanism whose paid inputs stay with the overlays remains, whoever calls it.

## Versioning contract

**The submodule SHA is the compatibility contract.** Every product consumes these packages as bare `path:` dependencies into its `crux-shared` git submodule, with no version constraint. There is no version solver in the loop, so a package's `version:` field has *zero* enforcement effect. Treat every package version except `crux_cxp`'s as **informational**: bump them when it communicates something useful to a human, and do not pretend a stale one is a defect.

What actually protects the eight downstream repos is mechanical, not numeric:

1. `.github/workflows/consumers.yml` analyzes all four open-core products against every commit here — its own workflow, so a superseded push or an unrelated red step never cancels or skips it.
2. `api/*.api.txt` — committed public-API goldens, checked in CI. Regenerate with `tool/api-snapshot.sh --write` and commit the diff **in the same commit as the change that caused it**. See `api/README.md`.
3. `tool/check-consumers.sh` — the local form of (1). Run it before bumping a product's submodule pin.

**`crux_cxp` is the exception.** It will be published to pub.dev at the open-core flip, as the one package here third parties build against, at which point its version stops being informational and starts being solved against by strangers. It therefore carries real semver discipline *now*, enforced by `tool/check-cxp-version.sh` in CI: any change under `packages/crux_cxp/lib/` must move `version:` and add the matching `## <version>` section to its CHANGELOG.

Note that `crux_cxp`'s package version and its `cxpProtocolVersion` wire version are **deliberately independent** and answer different questions — the package version tracks the Dart API, the protocol version tracks the bytes on the socket. The authoritative statement of that policy is the "Versioning policy" section at the top of `packages/crux_cxp/CHANGELOG.md`; do not restate or contradict it here.

## Deprecation policy

Before the open-core flip, removing a public symbol is nearly free: four consumers, all in this org, all fixable in the same afternoon. After the flip it stops being free, and `crux_cxp` on pub.dev makes it permanently not free. Adopt the discipline now, while it is cheap to practise.

**Going forward, a public symbol is never removed or re-signatured in one step.** The sequence is:

1. **Deprecate.** Annotate with `@Deprecated('<what to use instead>. Removed after <version>.')`. The message must name the replacement — a deprecation that does not say what to do next is just a warning people learn to ignore. Keep the old symbol working.
2. **Migrate.** Update all four products, then bump their submodule pins.
3. **Remove.** In a later, separate commit, once no consumer references it. Record the removal in the package's CHANGELOG.

Applies to anything in a package's export namespace — i.e. anything that shows up in `api/*.api.txt`. `lib/src/**` internals not reachable through the barrel are free to change without ceremony.

**Retroactive note:** an earlier quality pass removed and un-exported several symbols outright, and made one deliberate breaking change (`KeyBindingsEditor` now requires a `categoryCardBuilder`). Under this policy each of those should have shipped as a deprecation first. They are grandfathered in — the policy binds from its adoption date, not retroactively — but the `api/*.api.txt` goldens now make the next such change visible in review, which is the point.

## Coding conventions

All conventions from WaveCrux's [`CLAUDE.md`](https://github.com/Ferrite-Engineering/wavecrux/blob/main/CLAUDE.md) apply unless contradicted below. Highlights:

- `very_good_analysis` ^10, zero-warnings policy.
- Dart SDK `^3.12.0`.
- Conventional Commits.
- Domain models are immutable plain Dart classes with `const` constructors, `copyWith`, `==`, `hashCode`. No `freezed`.
- Files: `snake_case.dart`. Classes: `PascalCase`. Variables/functions/params: `camelCase`. Constants: `camelCase`.
- Public API documented with `///` doc comments — `very_good_analysis` enforces `public_member_api_docs`.
- New `lib/` code gets tests under `test/`, mirroring the `lib/` path where the file is unit-testable on its own. The tree does not mirror one-to-one — many `lib/` files are covered through their barrel or a sibling's suite — so the enforced gate is the per-package coverage floor in `tool/coverage.sh`, not file parity.

### Static guards (`packages/crux_workspace/test/static/`)

Nine machine-enforced guards run in the default `melos run test` (they live in
`crux_workspace` because it is the natural home for the resolved-AST scope
scanner; the workspace-wide ones walk up to the repo root and scan every
package). The first six land the suite's quality-floor disciplines here; the
last three guard what makes the repo publishable:

- **`comment_hygiene_test.dart`** — clinical-comment convention: no work-item
  anchors (a two-letter round prefix and a number, or a ruling id) in any
  comment under `packages/*/lib` or `packages/*/test`, and, under
  `packages/*/lib`, no process-note dates and no session or reviewer voice.
- **`doc_truth_test.dart`** — every repo path named in `CLAUDE.md`,
  `README.md` or `docs/adr/README.md` must exist, and each root document's
  package table must match `ls packages/` exactly (a package inventory that
  drifted in both root docs is what this was written to stop; it enforces
  "Adding a new package" step 7 mechanically), and every package directory
  must carry a `README.md` and a `CHANGELOG.md` (step 6).
- **`charter_vocabulary_test.dart`** — encodes the domain-neutrality charter so
  its two boundary decisions cannot erode: no HDL-language vocabulary outside
  `crux_yosys` (the one sanctioned allowlist entry, because Yosys elaboration
  is shared tooling two products invoke), no single-product domain nouns, and
  no waveform-canvas token namespaces (`signal.x`, `cursor.delta`, …) anywhere
  in shared code (they were moved out of `crux_theme`'s shared presets into
  WaveCrux). It reads code, not comments.
- **`per_tab_provider_scope_leak_test.dart`** — a `package:analyzer`
  resolved-AST scanner over `crux_workspace/lib` + `crux_projects/lib` that
  fails if any shared provider reads a per-tab/per-pane scope key
  (`tabIdProvider` / `paneIdProvider`) directly or transitively without being a
  seed. It locks in the audited soundness (currently zero leaks). It closes
  four textual blind spots (`Ref`-on-field, helper method, extension method,
  runtime-selected family), pinned by `test/static/scope_leak_shapes/`. Cost is
  ~15 s over the two source roots; `crux_workspace` dev-deps `analyzer` for it.
- **`route_mounted_scope_leak_test.dart`** — the same resolved-AST machinery
  (shared via `test/static/scope_leak_scanner.dart`) applied to the *widget*
  form of the same bug: a dialog pushed with `showDialog` /
  `showModalBottomSheet` / `Navigator.push` mounts on a Navigator **outside**
  the active tab's `UncontrolledProviderScope`, so its `WidgetRef` reads resolve
  against the empty root container. NetCrux shipped exactly that in a beta
  (Search Design returned "No results." on a fully loaded design), and the provider guard
  structurally cannot see it — no provider is involved anywhere in the chain.
  The rule, its exemptions, and the seven things it deliberately does **not**
  catch are documented at the top of the file; read that before trusting a
  green run. That bug's shape and its shipped fix are pinned side by side in
  `test/static/route_scope_shapes/`, so the mutation verification stands rather
  than having been performed once. Cost ~14 s. Source roots and the per-tab
  seed set are environment-overridable (`CRUX_ROUTE_SCOPE_ROOTS`,
  `CRUX_ROUTE_SCOPE_SEED_OVERRIDES`) so the same guard can be pointed at a
  product checkout instead of being re-implemented there.
- **`lib_reachability_test.dart`** — every `lib/**.dart` file in every package
  is reachable from that package's entry points (its top-level `lib/*.dart`
  barrels and anything under `bin/`), following `import`, `export` and `part`
  directives parsed from the AST, every target of a conditional directive
  included; `part of` is not an edge. A file nothing reaches ships in nobody's
  build and still gets read and trusted, so it is deleted rather than kept.
  The allowlist (`_allowedUnreachable`, path → reason) is empty, and an entry
  that outlives its file fails. The walker is pinned against a synthetic
  package in the same file, so it cannot quietly become one that reaches
  everything. Cost ~1 s. What it cannot see — a reachable export no consumer
  uses — is `tool/unused-exports.py`'s report, which needs the consumer
  checkouts and so is not a CI gate.
- **`open_core_purity_test.dart`** — the property that makes crux-shared
  open-sourceable: no code a product build can reach — every package's `lib/`,
  `bin/` and `tool/` — may be able to *sign* (no keypair type, private seed or
  key, bytes-returning `sign`, or `package:cryptography` signing shape); the one
  signer in the repo, the `crux-policy sign` subcommand's in `crux_policy/tool/`,
  is exempt by name and held to still being a signer so the exemption cannot go
  stale; the licence issuer compiles in public key material only; no package
  outside `crux_license` branches on a paid `LicenseTier`; and no public type is
  named for a feature the four pricing pages sell at Pro or Enterprise, unless it
  is a listed seam (the interface, the no-op default, the mechanism the paid
  inputs flow through), each of which must keep existing.
- **`no_bundled_encryption_test.dart`** — no package in the resolved workspace
  `pubspec.lock` is an encryption implementation. A cipher here would reach
  every product and every store build that declares no non-exempt encryption.
- **`no_private_references_test.dart`** — no tracked file (source, test,
  README, changelog, pubspec, ADR, workflow or tool) points a reader at a
  closed repository, an unpublished planning document, a roadmap phase or a
  tracker id. State the reason in place, or cite a file in this repository or
  a public page (`https://edacrux.app/cxp#sec-<n>-<n>`,
  `https://edacrux.app/policy-reference`, …). Its patterns carry planted
  samples, so a rotted pattern fails too.

Every guard with an allowlist keeps it empty except the single sanctioned
charter entry (`crux_yosys`). An empty allowlist is the point: a violation is
fixed, not listed.

### IMPORTANT: Screen-reader and keyboard accessibility of shared widgets

A shared widget ships in four products, so an accessibility defect here is
four defects. The first external NVDA pass found the Settings dialog, the
shortcuts editor, the stats strip, the start screen and the IDE shell all
broken in ways every label and contrast guard passed. The rules below are the
ones that pass taught; ADR 0003 (`docs/adr/0003-semantics-orphan-discipline.md`)
records the semantics-orphan rule in full.

- **Every interactive widget gets a focus-walk test.** Use the harness in
  `packages/crux_a11y/lib/src/testing/focus_walk.dart`: `walkFocus` then
  `expectCleanFocusWalk`, and `expectFocusAnnounced` wherever focus must land
  (a dialog opening, a start screen appearing). Add `crux_a11y` as a
  `dev_dependencies` path dependency to use it.
- **One name per control.** A label *or* a tooltip; exclude the tooltip
  (`excludeFromSemantics: true`) or the visible caption (`ExcludeSemantics`)
  when the other already names it. Never wrap a named control in a container
  whose label repeats it.
- **Rows are single nodes.** A row with one action merges into one named node
  (`MergeSemantics` plus `Semantics(button:, selected:, expanded:)`); a row
  gesture beside a checkbox uses `excludeFromSemantics` so they merge. A
  `Card` or other container absorbs loose rows — make each row a container.
- **Columns are traversal groups.** Anything that lays focusable controls
  side by side in columns wraps each column in `FocusTraversalGroup`, or Tab
  alternates between them by height.
- **Dialogs** take focus on open and close on Escape, whatever the barrier.
  The exception is a surface that must be answered (the licence agreement,
  the consent disclosure): Escape does nothing there.
- **A surface stacked over the app instead of pushed as a route** is modal
  to the pointer only, unless it is built on `CruxModalGate` (which keeps
  the app behind it out of focus and semantics, and hands focus back when it
  closes) with the dialog in a `CruxModalSurface` (named, focus trapped,
  Escape consumed) and `autofocus` on its first control. A bare
  `Stack` + `ModalBarrier` leaves focus on the hidden app: Tab walks it
  silently and Enter presses its buttons.
- **Status is announced, not shown.** Use `announceCrux`; a SnackBar alone is
  never heard on desktop.
- **Focus listeners never mutate focus nodes synchronously** (for example
  `skipTraversal`); defer to a microtask, or the focus manager throws a
  concurrent modification. A node also notifies its listeners when its own
  `skipTraversal` changes, so act only when focus actually arrives.
- **Key handlers are invisible.** A `Focus` that wraps content only to catch
  keys takes `includeSemantics: false`. Never `CallbackShortcuts` around
  content: its `Focus` keeps semantics, and in LintCrux that merged a search
  field with the text below it.
- **Everything the pointer does has a key.** Focus arriving on a row selects
  it; Enter does what a double-click does; Shift+F10 and the Menu key open the
  context menu.
- **No arrows or box glyphs in anything spoken**, including shortcut labels —
  `formatShortcutSpokenLabel`, not `formatShortcutLabel`, for semantics.

### IMPORTANT: Writing files — one atomic-write helper

**Never hand-roll a temp-file-plus-rename.** Every crash-safe write in this repo and in the
products goes through `package:crux_io` (`writeStringAtomic` / `writeJsonAtomic`). It owns
parent-directory creation, the unique-per-write scratch filename, the `fsync`, the rename,
and scratch cleanup on failure.

This rule exists because atomic write had been written five times across `crux_projects`,
`crux_workspace` (twice), `crux_cxp` and `crux_theme`, and the copies had *accidentally*
diverged on all three of those axes. Three of the five would lose data on a crash in ways
the other two would not.

Durability is an explicit, documented parameter, not a default anybody inherits by
accident:

- **`WriteDurability.durable` (the default)** — everything the user cannot trivially
  reconstruct. Without the `fsync`, the rename can be ordered ahead of the data blocks, so
  a crash publishes a truncated file *over* the good one — worse than not writing at all.
- **`WriteDurability.ephemeral`** — only for state a running process republishes on a
  bounded timer, where loss self-heals. The CXP peer manifest (rewritten every 30 s) is
  the sole qualifying call site today. "It would be a bit faster" is not the bar.

### IMPORTANT: Deciding whether two paths are the same file

**Never compare file paths as raw strings, and never hand-roll the
normalization.** Every "is this already open / already registered?" check in
this repo and in the products goes through `package:crux_io`:

- `canonicalizePath(path)` — absolute, normalized, symlink-resolved, trailing
  separator dropped, **case preserved**. This returns a *path*: safe to store,
  display and open.
- `canonicalPathKey(path)` — `canonicalizePath` plus case folding on
  case-insensitive filesystems. This returns a *comparison key*: never store,
  display or open it.
- `isSamePath(a, b)` — the two-argument form. Two empty paths are deliberately
  **not** the same file; an absent path is unknown, not a shared identity.

The rule exists because a raw string does not survive a relative launch
argument, a `..` segment, a trailing separator, a symlink (`/tmp` →
`/private/tmp` on macOS), or a case-insensitive volume — and every one of
those failures presents to the user as a duplicate that comes back every
launch, unbounded.

**All three are safe to call from a web build**, so a product does not need a
`kIsWeb` branch around them. In a browser a location is an uploaded file's name
or a URL and is already canonical: `canonicalizePath` returns it trimmed and
otherwise unchanged (not made absolute against the page URL, not
dot-normalised), and keys preserve case. `dart:io` sits behind a conditional
export; `packages/crux_io/test/web/path_identity_web_test.dart` proves it in
Chrome.

**Where a path is the identity of a tab**, the seam is
`WorkspaceCodec.identityOf(payload)` in `crux_workspace`, which
`WorkspaceNotifier.openTab` consults to focus an existing tab rather than open
a second one. It defaults to `null` (dedupe inert), so a product opts in by
overriding it — and a payload with no path (a blank scratch tab) must keep
returning `null`, or the second blank tab becomes impossible to open.

### IMPORTANT: Spawning a process — resolve the executable first

**Never hand `Process.run` or `Process.start` a bare executable name that
reaches a Windows host.** `CreateProcess` searches the launching process's
current directory before the system directories and `PATH`, and a product
launched from a terminal inside a repository has that repository as its
current directory — so an `explorer.exe` or `yosys.exe` committed there runs
in place of the real one. Pass the name through `package:crux_io` first, and
use a **`require`** form, which never hands a bare name on:

- `requireSpawnExecutableForHost(name, environment: childEnv)` at a real spawn
  site. The identity off Windows. On Windows it returns an absolute path, or
  throws a `ProcessException` (`not found on PATH`, error code 2) when nothing
  on `PATH` answers — the type `Process.start` throws for a missing binary, so
  the caller's existing "not installed" handling applies and nothing is
  started. Pass the child's environment when the caller builds one, so a
  binary found only on an augmented `PATH` still resolves.
- `requireSpawnExecutable(name, pathEnvironment:, windows:, pathExt:, exists:)`
  where the host facts must be injectable, which is how the Windows branch is
  tested on the macOS and Linux machines CI runs on. A spawn layer takes a
  `SpawnHost` (default `SpawnHost.current()`) for the same reason; see
  `DefaultProcessRunner` in `crux_yosys`.

The `resolve` forms return an unmatched name unchanged, and a bare name handed
to a Windows spawn is still searched for in the launching directory. Use them
only where the caller decides for itself what an unmatched name means.

A path that reaches an editor's argv from outside the product must pass
`isAbsoluteSpawnPath` first, or the editor may read it as an option.

### IMPORTANT: Two different `workspace.json` files

Per app there are **two** files named `workspace.json`, in two directories,
written by two packages. Confusing them costs an afternoon:

| Path | Owner | Contents |
|---|---|---|
| `<appSupport>/workspace.json` | `crux_workspace`'s `WorkspaceService` | tabs + panes |
| `<appSupport>/<product>/workspace.json` | the Pro overlays' persistent `ProjectRegistry` (private shared code, not this repo) | open projects, active project, recent projects |

They re-seed each other: the products' `ProjectWorkspaceSync` opens a tab when
the registry's active project changes, so deleting only the tab document does
not clear the session. A third location, `<appSupport>/sessions/<tabId>.<ext>`,
holds per-tab sidecars and survives `WorkspaceService.clear()` —
`clearAllSidecars()` is what removes it. Resetting an app's session by hand
means all three.

### IMPORTANT: JSON document version gating

Four packages had four different `version`-field policies, one of which (`KeymapCodec`)
wrote the field and never read it. The line is drawn on **who authored the document**:

| Kind | Policy | Packages |
|---|---|---|
| **User-authored, shareable artifact** | **Refuse loudly.** Throw a `FormatException` subclass naming the offending version. | `ThemePackCodec` (`FormatException`), `KeymapCodec` (`KeymapSchemaVersionException`) |
| **App-managed recoverable state** | **Degrade gracefully.** Return an empty/null document so the host substitutes a fresh one; quarantine the bytes where a quarantine layer exists. | `Workspace` (typed `WorkspaceSchemaVersionException`, quarantined by `WorkspaceService`), `ProjectWorkspace` (returns `null`) |

The reasoning is about who can act on the failure. A theme pack or keymap arrived from
another human, often from a newer build; parsing it under today's assumptions does not
yield "most of" their document, it yields a silently *different* one, and the host can say
so. A workspace file is one the app wrote for itself and the user cannot hand-repair —
refusing there bricks launch, so the recoverable path wins.

Two corollaries that are easy to get wrong:

- **A missing version key is not the same as a malformed one.** Absent → treat as a legacy
  pre-versioning document and parse tolerantly. Present but not an int → unreadable.
  Collapsing those two into one `is! int` test is how `"version": "2"` gets parsed as
  legacy.
- **Do not swallow the refusal in a convenience wrapper.** `decodeString`-style helpers
  catch the JSON parse error and must let the version exception through; returning an
  empty result reads to the caller as "no customizations" and wipes user state on the next
  save.

## Naming

- Repo name: `crux-shared` (hyphenated, GitHub convention).
- Dart package names: underscored, Dart convention, always `crux_`-prefixed — see the package table for the current set.
- Melos workspace name: `crux_shared`.

## Build & test commands

```bash
# One-time setup
dart pub global activate melos

# From the repo root
melos bootstrap        # pub get for every package
melos run analyze      # dart analyze --fatal-infos --fatal-warnings
melos run test         # dart test for pure-Dart packages; flutter test for Flutter packages
melos run format-check # verify formatting
melos run format-fix   # apply dart format
```

Scripts outside Melos:

```bash
tool/api-snapshot.sh --check    # public-API goldens up to date? (CI runs this)
tool/api-snapshot.sh --write    # regenerate after an intentional API change
tool/check-consumers.sh         # analyze the four open cores against this working tree
                                #   (finds each at $CRUX_PRODUCTS_ROOT/<product>, default ../,
                                #   or one directory below it)
tool/check-cxp-version.sh <ref> # crux_cxp version + CHANGELOG moved since <ref>?
python3 tool/spdx-headers.py --check .           # Apache-2.0 SPDX header on every source file (CI)
python3 tool/gen-notices.py --check              # NOTICES matches pubspec.lock (CI, after bootstrap)
python3 tool/supply-chain.py --check-licences --tier open-core   # licence gate (CI)
bash tool/coverage.sh                            # per-package coverage floors (CI)
python3 tool/no-bundled-engines.py --check <repo> # no EDA engine binary in a distributed build; each open core's CI runs it
python3 tool/unused-exports.py                   # exported symbols no consumer checkout references (a report, not a gate)
```

`tool/country-names.sh` is not a check: it is the ISO-3166 name map the suite's
download-stats tools source.

## What CI actually does

`.github/workflows/ci.yml` runs on **push to `main`, on pull requests targeting `main`, on manual `workflow_dispatch`, and nightly at 01:20 UTC**. Do not disable the push/PR triggers: a job that never runs and a job that passes look identical from the outside.

It has five jobs:

- **`changed` — nightly no-op gate.** On a scheduled run only, skips `ci` and `supply-chain` when `HEAD` is the SHA of the last green run. Push, PR and manual runs always proceed.
- **`ci` — workspace-internal gate.** Checks SPDX headers first (pure Python, before any toolchain download), then installs Flutter at the suite's pinned version (not Dart-only: the workspace contains Flutter packages, so `melos bootstrap` needs `flutter pub get`), then `melos bootstrap` → `tool/gen-notices.py --check` → `format-check` → `analyze` → `test`, then the browser-only tests in headless Chrome — `dart test -p chrome` for all of `crux_policy` and for the `test/web` folders of `crux_cxp` and `crux_io`, `flutter test --platform chrome` for `crux_telemetry`'s time-zone test — because `melos run test` only runs the VM and each sits on a path web builds take, then `tool/api-snapshot.sh --check` for the public-API goldens, then `tool/check-cxp-version.sh` for the `crux_cxp` semver guard (skipped on schedule/dispatch, which have no meaningful base ref).
- **`consumers` — downstream gate.** A four-way matrix (`wavecrux`, `netcrux`, `lintcrux`, `simcrux`). Each leg checks out the product repo, drops **this** commit in at the `crux-shared` submodule path, runs `flutter pub get` + `build_runner` (where the product declares it) + `gen-l10n` (+ per-product prep), and then `flutter analyze --fatal-infos --fatal-warnings`. This is the job that actually catches a breaking change — the `ci` job only proves crux-shared is internally consistent, which says nothing about whether `wavecrux` still compiles. It analyzes rather than tests, because analysis is what detects a removed or re-signatured symbol and the products' own CI owns their suites. It needs the org-level `SUBMODULE_PAT` secret and is skipped on fork PRs, which do not receive secrets.
- **`supply-chain`.** Resolves the workspace, then `tool/supply-chain.py` runs the licence gate at the strictest (`open-core`) tier, writes a CycloneDX SBOM as a build artifact, and sweeps osv.dev advisories.
- **`coverage`.** `tool/coverage.sh` gates each package against its own floor; an aggregate would let one package lose half its coverage unseen. It fails first when its floor list and `packages/` disagree, so a new package cannot go ungated — seed its floor at measured minus two (`none` only for a package with no executable lines). Runs on every trigger, not behind `changed`.

`concurrency` is keyed by ref **and** event, so a push never cancels a nightly or vice versa. A newer push or PR update cancels the superseded run, on `main` too: GitHub cancels a still-queued run regardless and reports it as a failure, so gating the tip is the honest record.

Two advisory workflows sit beside it, and a red run in either is a scheduling signal, not a broken `main`: `.github/workflows/toolchain-canary.yml` (weekly, Linux, analyze + test on the *current* Flutter stable rather than the pin) and `.github/workflows/deps-canary.yml` (monthly, fails when `flutter pub outdated` finds in-range drift the tracked `pubspec.lock` has not taken).

## This repo ships one binary

Everything here is a library except `crux_policy`'s `crux-policy`, the CLI an
Enterprise administrator is told to run to author and sign the org-wide policy
file. `packages/crux_policy/tool/build_cli.sh` is its one build: `ci.yml` runs
it on every push, and `.github/workflows/release-crux-policy.yml` — dispatch-
only, gated on a green `ci.yml` run for the same commit — runs it per platform
(macOS arm64 and x64, Linux x64 and arm64, Windows x64), smoke-tests each
binary against its published contract, Developer ID signs and notarizes the
macOS archives, holds the Linux binaries to the promised glibc floor, and
publishes to the suite release bucket under `suite/<version>/`. Windows ships
unsigned until the Azure signing credentials reach this repository (they are
per product repository, not org-level). Every job carries `timeout-minutes`
and every third-party action is pinned to a full commit SHA — a moving major
tag is a supply-chain hole in a job that holds a code-signing identity.

Two consequences for anyone changing `crux_policy`:

- **Its exit codes are a published contract** (the policy file reference on
  edacrux.app): `0` ok, `1` lint findings, `3` I/O, `4` refused, `64` usage,
  `128 + N` on a signal. Add codes; never renumber one. `64` for a usage
  error is the suite-wide convention for headless tools, and `--help` /
  `--version` are answered anywhere on the command line with `0`.
- **The release workflow smoke-tests the binary against that contract** —
  `--version`, the documented `init` → `lint` → `inspect` sequence and the
  exit codes — so a build that compiles but cannot run does not get signed.

## Changes land through pull requests

Until the 1.0 code freeze, maintainers commit directly to `main`. From the
code freeze on, every change — by anyone — lands through a pull request
whose description documents the issue or feature, the fix or
implementation, how it was verified (tests added, CI gates passed), and
the user documentation updated in the same PR. Contributors sign a CLA
before a first merge, as described in `CONTRIBUTING.md`.

## Git conventions

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- Branch strategy: trunk-based development; `main` is always green.
- Never `--no-verify`. If a hook fails, fix the underlying issue.

## Adding a new package

1. Create `packages/<name>/` with `pubspec.yaml`, `analysis_options.yaml` (inheriting from the workspace root), `lib/`, `test/`.
2. Set `publish_to: 'none'` (we don't publish to pub.dev — products consume via `path:` deps).
3. Set `resolution: workspace` so the package participates in the shared lockfile.
4. Add the package path to the `workspace:` list in the root `pubspec.yaml`.
5. Run `melos bootstrap` from the repo root to wire the new package into the workspace.
6. Add a `README.md` and a `CHANGELOG.md` to the package (`doc_truth_test.dart` fails without either).
7. Add a row to the package table in this file and in [`README.md`](README.md), and an entry to `FLOORS` in `tool/coverage.sh` (measured minus two).
8. Run `tool/api-snapshot.sh --write` and commit the new `api/<name>.api.txt` golden. Every top-level `lib/*.dart` gets its own golden, so a secondary barrel (`crux_license_core.dart` — the constrained-host subset — and `crux_sqlite`'s test-support barrels) is tracked too; anything not meant to be public goes under `lib/src/`.
9. If the package embodies a cross-suite convention that future work could plausibly reverse (a filename shape, a persistence format, a protocol choice), write an ADR under [`docs/adr/`](docs/adr/) — see [`docs/adr/README.md`](docs/adr/README.md). Not every package needs one; a decision somebody will re-litigate does.

## Repo docs

- [`docs/adr/`](docs/adr/) — architecture decision records for cross-suite conventions. [`docs/adr/README.md`](docs/adr/README.md) is the index.
- [`api/README.md`](api/README.md) — what the public-API goldens are for and how to regenerate them.

## Relationship to the four products

- Each product's open-core repo holds `crux-shared` as a git submodule of itself (e.g. `wavecrux/crux-shared/`). The product's `pubspec.yaml` declares each consumed shared package as a `path:` dependency pointing into that submodule (e.g. `crux_file_watcher: { path: ./crux-shared/packages/crux_file_watcher }`).
- Each Pro overlay inherits `crux-shared` transitively through its open-core submodule — it does not register a second `crux-shared` submodule.
- Shared code that *is* a paid capability does not live here. It lives in a **private Pro-tier shared repository** that depends on this one and that the Pro overlays consume as a second submodule beside the open core ([ADR 0005](docs/adr/0005-pro-implementations-leave-crux-shared.md)). The arrow points one way: that repository → `crux-shared`. Nothing here depends on it, and nothing here names it — it is a closed repository, and the private-references guard rejects its name.
- This repo does **not** list any product as a workspace package or sibling dependency. The dependency arrow goes one way: products → `crux-shared`.
- **Visibility:** all four product open-core repos and this repo go public Apache 2.0 at the same moment (the post-beta open-core flip). The four Pro overlays stay private.

## What does NOT belong here

- License signing private keys (Keygen holds them; no repo does), Keygen admin tokens, and any other service credential — those live in the commerce backend's secret store, never in source. The telemetry ingest URL and `LiveTelemetryService` *do* belong here: the whole collection pipeline is public so it can be read and stripped, and abuse is handled by the ingest Worker's validation, not by hiding the URL.
- Any UI widget that is not domain-neutral (i.e. specific to waveforms, netlists, lint, or test results).
- The CXP wire protocol specification — that will be published as a separate public spec. Only the *bindings* (message types, server/client implementations) live here.
- Build artifacts, generated code, credentials.
