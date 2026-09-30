// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The `<design>.crux-project` suite design manifest.
///
/// One checked-in pointer file naming a design's RTL, dump, lint project and
/// regression config, so opening a design in four products is one ritual
/// instead of four. Named like `uart_tx.crux-project` so file pickers show it;
/// the legacy bare `.crux-project` is still read, with a deprecation warning.
///
/// The load-bearing rule this package exists to enforce: the CXP `design_id`
/// comes from the manifest's **directory**, not from whichever artifact a
/// product opened. Get that wrong in one product and cross-probe between
/// manifest-opened designs stops joining, silently.
library;

export 'src/crux_project_manifest.dart';
export 'src/crux_project_open_plan.dart';
export 'src/crux_project_parser.dart';
