// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite table model for the EDACrux suite.
///
/// A sortable header over a virtualized list, columns sized by weight and
/// resizable by dragging the dividers between them, widths that persist, and
/// body cells with a hover-only tooltip. Generic over the host's column enum
/// `C`, so each product keeps its own columns, default weights, preference
/// key and row widget, and shares everything else:
///
/// - `CruxTableColumns<C>` / `CruxColumnLayout<C>` — the column set with its
///   default weights and minimum width, and a layout of weights over it
///   (`flexOf`, `resize` between neighbours).
/// - `CruxColumnLayoutCodec<C>` — the `SettingsCodec` that stores a layout as
///   one JSON object of column name to weight under the host's key.
/// - `CruxColumnLayoutProviders<C>` — the Riverpod seam: the settings-service
///   provider, the launch provider a host overrides so a restored tab draws
///   at its saved widths on its first frame, and the `NotifierProvider` whose
///   `CruxColumnLayoutNotifier` offers `resize` / `commit` / `reset`.
/// - `CruxTableHeader<C>`, `CruxSortableHeaderCell`,
///   `CruxColumnResizeHandle<C>` and `CruxTableCell` — the widgets, with the
///   header tokens, the 28 dp row height and the `<table>Header-<column>` /
///   `<table>Resize-<column>` key convention the products' tests already use.
library;

export 'src/column_layout.dart';
export 'src/column_layout_codec.dart';
export 'src/column_layout_providers.dart';
export 'src/column_resize_handle.dart';
export 'src/sortable_header_cell.dart';
export 'src/table_cell.dart';
export 'src/table_header.dart';
export 'src/table_metrics.dart';
