// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_shortcut_action/src/action_category.dart';

/// The cross-suite shared interface every product's action enum implements.
///
/// Each Crux product owns its own
/// product-specific action enum with however many values it needs. The
/// product enum implements [CruxAction] so generic infrastructure
/// (command palettes, menu builders, telemetry sinks, settings UIs) can
/// reason about actions across the suite without depending on a specific
/// product's enum.
///
/// The interface deliberately exposes only the suite-wide structural
/// concerns:
///
/// - [id] — a stable string identifier suitable for serialization (workspace
///   files, command palette IDs, telemetry events). Convention is to prefix
///   with the product name to avoid collisions across the suite, e.g.
///   `'wavecrux.openFile'`, `'<product>.<actionName>'`.
/// - [category] — the [ActionCategory] grouping the action belongs to, used
///   to build menus and grouped command palette views.
///
/// Things that intentionally stay out of this interface (and live in each
/// product instead):
///
/// - **Localized labels.** Labels reference each product's own `L10N`
///   class; the product writes a label-resolution extension on its own
///   enum.
/// - **Default key bindings.** Each product has its own canonical
///   keyboard layout and may differ in modifier conventions; the bindings
///   map lives next to the product's enum.
/// - **The Flutter `Intent` subclass used for dispatch.** Each product
///   wires its own Intent so `Actions.maybeInvoke<MyProductIntent>` keeps
///   working with type-specific dispatch.
/// - **Menu-hidden filters and grouped-action helpers.** Each product
///   decides which of its actions to hide from menus.
abstract interface class CruxAction {
  /// A stable, suite-unique identifier. Conventionally
  /// `'<product>.<actionName>'` — e.g. `'wavecrux.openFile'`,
  /// `'wavecrux.openFile'`. Used for serialization (workspace files,
  /// command palette IDs) and telemetry event names.
  String get id;

  /// The [ActionCategory] this action belongs to. Drives menu grouping in
  /// the desktop platform menu bar, the mobile overflow action menu, and
  /// the command palette's grouped view.
  ActionCategory get category;
}
