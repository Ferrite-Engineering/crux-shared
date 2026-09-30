// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite multi-project chrome for the EDACrux suite.
///
/// The project switcher dialog, the recent-projects panel, and the
/// providers that parameterize them. Built on `crux_projects`' registry, so
/// every host that already has a `ProjectRegistry` gets the UI for free.
///
/// Everything product-specific is configuration: the copy arrives as a
/// `CruxProjectsUiStrings` through `cruxProjectsUiStringsProvider`, the tier
/// badge through `cruxProjectsUiBadgeBuilderProvider`, the optional
/// cross-project-search handoff through `crossProjectSearchOpenerProvider`,
/// and the message for a recent project that can no longer be opened through
/// `recentProjectUnavailableReporterProvider`. Per crux-shared convention the
/// package carries no ARB of its own.
///
/// Extracted from SimCrux's shipped project switcher at the moment LintCrux
/// became the second consumer.
library;

export 'src/crux_projects_ui_strings.dart';
export 'src/project_activation_observer.dart';
export 'src/recent_project_reopen.dart';
export 'src/widgets/project_switcher_dialog.dart';
export 'src/widgets/recent_projects_panel.dart';
