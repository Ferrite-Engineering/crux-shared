# crux_workspace

Cross-suite workspace + multi-tab + split-pane infrastructure for the EDACrux suite.

This package supplies the value types, the generic domain model, the
persistence service, the Riverpod plumbing for per-tab and per-pane
`ProviderContainer` management, the multi-window detachment scaffolding,
and the consumer-facing widgets every Crux product composes into its
multi-tab workspace UI.

## Status

**Foundation + widgets (`0.2.0`).** The package surface is now sufficient
to host a workspace-aware product end-to-end:

| Layer | Surfaces |
|---|---|
| Value types | `TabId`, `PaneId` |
| Domain | `Workspace<P>`, `WorkspaceTab<P>`, `WorkspacePane` |
| Persistence | `WorkspaceCodec<P>`, `WorkspaceService<P>` |
| Riverpod plumbing | `tabIdProvider`, `paneIdProvider`, `TabContainerManager`, `PaneContainerManager` |
| State | `WorkspaceNotifier<P>` (AsyncNotifier base), `WorkspaceLifecycleObserver<P>` |
| Widgets | `EmptyCanvasState`, `CruxSuiteFooter`, `CruxSuitePeers`, `ViewerTabBar<P>`, `PaneHost<P>`, `ViewerTabBarStrings` |
| Multi-window | `kMultiWindowAvailable`, `TabDetachingDelegate` / `Noop` + provider, `PanelPopOutDelegate` / `Noop` + provider |

**Deferred to follow-on releases**:

- In-package ARB-generated localizations for the widget strings (today the
  caller supplies a `ViewerTabBarStrings` subclass — typically resolving its
  fields from the product's own `AppLocalizations`).
- Widget-level integration tests for `ViewerTabBar` and `PaneHost`. The
  static / public-surface tests pin the constructor shape; rendering tests
  share a Riverpod-3.x container/widget timing quirk under investigation.
- Reference adopter wiring in WaveCrux open-core. The migration runs
  alongside the next consumer batch.

## Why generic over `P`

The persistence-relevant per-tab data is product-specific:

- WaveCrux needs `filePath` and an optional `sessionExportPath`.
- Future Crux products will carry their own payloads (selection state,
  run ids, breakpoints, …) behind the same seam.

Hard-coding any one of those into the framework would force the others to
either share a kitchen-sink struct or to fork the framework. The generic
parameter `P` defers that decision to the consumer: each product defines
its own payload class and supplies a `WorkspaceCodec<P>` that handles
serialization. The framework itself remains domain-neutral.

## Adoption sketch — minimal worked example

```dart
// 1. Define the per-tab payload.
class MyPayload {
  const MyPayload({required this.filePath});
  final String filePath;
}

// 2. Implement the workspace codec.
class MyCodec extends WorkspaceCodec<MyPayload> {
  const MyCodec();
  @override
  int get schemaVersion => 1;
  @override
  Map<String, Object?> payloadToJson(MyPayload p) => {'filePath': p.filePath};
  @override
  MyPayload payloadFromJson(Map<String, Object?> j) =>
      MyPayload(filePath: j['filePath']! as String);
  @override
  String displayNameFor(MyPayload p) => p.filePath.split('/').last;
}

// 3. Wire the service + provider.
final myWorkspaceService = WorkspaceService<MyPayload>(codec: const MyCodec());

final myWorkspaceProvider = AsyncNotifierProvider<
  WorkspaceNotifier<MyPayload>,
  Workspace<MyPayload>
>(
  () => WorkspaceNotifier<MyPayload>(service: myWorkspaceService),
);

// 4. Set up per-tab and per-pane container managers at app startup.
final root = ProviderContainer();
final tabs = TabContainerManager(
  rootContainer: root,
  overridesFactory: (tabId) => [
    // Register per-tab providers here, e.g.
    // myCursorTimeProvider.overrideWith(...),
  ],
);
final panes = PaneContainerManager(
  rootContainer: root,
  overridesFactory: (paneId) => [
    // Register per-pane providers here, e.g.
    // myRenderStatsProvider.overrideWith(...),
  ],
);

// 5. Compose the UI.
class MyAppRoot extends StatelessWidget {
  const MyAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: root,
      child: WorkspaceLifecycleObserver<MyPayload>(
        provider: myWorkspaceProvider,
        child: MaterialApp(
          home: Scaffold(
            body: PaneHost<MyPayload>(
              provider: myWorkspaceProvider,
              tabs: tabs,
              panes: panes,
              defaultPayloadBuilder: () => const MyPayload(filePath: 'new.dat'),
              emptyCanvasContent: const EmptyCanvasState(
                title: 'Welcome',
                primaryActions: [Text('(wire your open-file button here)')],
              ),
              tabContentBuilder: (ctx, tab) => MyTabBody(payload: tab.payload),
            ),
          ),
        ),
      ),
    );
  }
}
```

## Workspace document schema

`Workspace<P>` serializes to a JSON document with this top-level shape:

```json
{
  "version": 1,
  "tabs": [
    {
      "id": "...",
      "displayName": "...",
      "paneId": "...",
      "<...product-specific payload keys flattened in>": "..."
    }
  ],
  "panes": [
    {"id": "...", "activeTabId": "..."}
  ],
  "activePaneId": "...",
  "extras": {}
}
```

- `version` is the framework schema version. Unknown values raise
  `WorkspaceSchemaVersionException` and the consumer falls back to an
  empty workspace.
- Per-tab payload keys (returned by `WorkspaceCodec.payloadToJson`) are
  flattened into the tab map alongside `id`, `displayName`, `paneId`. The
  framework reserves those three keys; product codecs must not emit them.
- `extras` is a free-form top-level map products use for ambient flags
  (panel visibility, statistics-strip visibility, …) that don't justify
  a schema-version bump. Unknown keys round-trip safely.
- Invariants enforced by the constructor: 1 or 2 panes, unique tab ids,
  every `WorkspaceTab.paneId` references one of `panes`, every
  `WorkspacePane.activeTabId` references a tab hosted in that pane.

## Mutation API

`WorkspaceNotifier<P>` exposes the full mutation surface — see the
package-level docs on the class for the exact set. Each mutation updates
state immediately and schedules a debounced save via `WorkspaceService`.
The notifier tracks the in-flight save future so `flushPendingSave`
reliably observes the post-save filesystem state — wire it into
`AppLifecycleState.paused` / `detached` via [`WorkspaceLifecycleObserver`]
or your own `WidgetsBindingObserver` to guarantee the app's last
in-memory state survives a hard quit.

## Localization

`ViewerTabBar` reads all chip and menu strings from a
`ViewerTabBarStrings` instance. The default `ViewerTabBarStringsEn` ships
English fallbacks; products that already wire ARB-generated
localizations subclass the interface and pass it in via
`ViewerTabBar.strings` (forwarded by `PaneHost.strings`). In-package
ARB-generated localizations are deferred to a follow-on batch.

## Theme

`ViewerTabBar` follows the active theme's `tabBar.*` chrome tokens, read from
`crux_theme`'s `CruxChromeColors`: `tabBar.background` fills the strip (no
fill when unset), `tabBar.selected` fills the active tab
(`surfaceContainerHighest` when unset), and `tabBar.label` colours every tab
title (`bodyMedium`'s colour when unset).

## Multi-window

`kMultiWindowAvailable` is `false` in this release. The two delegate
abstracts (`TabDetachingDelegate`, `PanelPopOutDelegate`) plus their
`Noop*` defaults exist so products can render multi-window affordances
in a disabled state today — and so the Pro/Enterprise overlay that
ships the concrete delegate implementations only needs to register a
provider override when Flutter multi-window reaches stable. The
`ViewerTabBar` context menu already includes the disabled "Move to New
Window" entry.

## License

Apache 2.0 (at the public flip — currently private alongside the other
`crux-shared` packages).
