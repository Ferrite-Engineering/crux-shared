// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite workspace + multi-tab + split-pane infrastructure for the
/// EDACrux suite.
///
/// This release ships the foundation (value types, generic `Workspace<P>`
/// domain model, `WorkspaceService<P>` persistence, per-tab and per-pane
/// `ProviderContainer` managers, multi-window detachment scaffolding) plus
/// the consumer-facing widgets (`PaneHost<P>`, `ViewerTabBar<P>`,
/// `EmptyCanvasState`) and the generic `WorkspaceNotifier<P>` Async
/// notifier base. The WaveCrux open-core migration lands in a follow-on
/// batch alongside the in-package ARB-generated localization sweep.
///
/// See the package README for the canonical adoption pattern.
library;

export 'src/id_providers.dart';
export 'src/multi_window.dart';
export 'src/pane_container_manager.dart';
export 'src/pane_id.dart';
export 'src/scoped_container_manager.dart';
export 'src/tab_container_manager.dart';
export 'src/tab_id.dart';
export 'src/widgets/crux_glowing_app_icon.dart';
export 'src/widgets/crux_suite_footer.dart';
export 'src/widgets/crux_suite_peers.dart';
export 'src/widgets/empty_canvas_state.dart';
export 'src/widgets/pane_host.dart'
    show
        PaneBorderBuilder,
        PaneHost,
        PaneSplitLayoutBuilder,
        PaneStackBuilder,
        TabContentBuilder;
export 'src/widgets/viewer_tab_bar.dart'
    show
        PaneTrailingActionsBuilder,
        TabContextAction,
        TabContextMenuBuilder,
        TabContextMenuItemsBuilder,
        TabTooltipBuilder,
        ViewerTabBar,
        ViewerTabBarSizing;
export 'src/widgets/viewer_tab_bar_strings.dart';
export 'src/workspace.dart';
export 'src/workspace_codec.dart';
export 'src/workspace_lifecycle_observer.dart';
export 'src/workspace_notifier.dart';
export 'src/workspace_scopes.dart';
export 'src/workspace_service.dart';
