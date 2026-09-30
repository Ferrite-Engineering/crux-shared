// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Builds the content a [CruxDockEntry] shows while it is the active tab.
///
/// Only the **active** entry's builder runs — `CruxDock` deliberately does not
/// keep inactive tabs alive in an `IndexedStack`. In this suite, panel state
/// (scroll position, loaded data, playback) lives in Riverpod providers, not
/// in widget state, so rebuilding on re-activation is loss-free and the dock
/// never pays for seven live panels to show one.
typedef CruxDockEntryBuilder = Widget Function(BuildContext context);

/// One tab in a `CruxDock`.
///
/// The suite's presence semantics are carried by [onClose], not by a flag:
///
/// - **Pinned** tabs (Transactions, Values, Inspector, Log…) are assembled
///   into the entry list unconditionally and pass no [onClose] — they render
///   no `×` and are always available.
/// - **On-demand** tabs (FSM, X-Trace, Activity, Diff, Cross-Probe…) are
///   included only while their feature is active, and pass an [onClose] that
///   *deactivates the feature* — closing the tab and clearing the analysis are
///   the same gesture, which is what keeps the strip honest about what is
///   actually running.
///
/// The list itself is host-assembled each build from the host's providers, so
/// "presence" is simply membership. Dynamic groups (one dock tab per Stage
/// panel) are a host-side `for` loop over its own collection — the dock needs
/// no group concept.
@immutable
class CruxDockEntry {
  /// Creates a dock tab entry.
  const CruxDockEntry({
    required this.id,
    required this.icon,
    required this.label,
    required this.builder,
    this.closeSemanticLabel,
    this.badgeCount = 0,
    this.actions = const <Widget>[],
    this.movable = false,
    this.onClose,
  });

  /// Stable identifier, unique within one dock (e.g. `'transactions'`,
  /// `'stage:stagePanel_0'`). Persisted by the host as the active-tab id, so
  /// it must be stable across sessions for pinned tabs.
  final String id;

  /// Icon shown in the tab, at the strip's icon size.
  final IconData icon;

  /// Localized tab label. Resolved by the host (the package carries no
  /// localizations of its own).
  final String label;

  /// Accessible name for this tab's close (`×`) affordance.
  ///
  /// The `×` carries no visible text and, until 2026-08-18, no semantic label
  /// either — a screen reader announced it as an unnamed button in all four
  /// products. When null the dock falls back to [label], so the control is at
  /// least named after the panel it closes rather than being anonymous; a host
  /// wanting a verb ("Close Transactions") passes its own localized string.
  ///
  /// The package deliberately supplies no English default here: it carries no
  /// localizations, and [label] is already host-resolved.
  final String? closeSemanticLabel;

  /// Builds the tab's content when active. See [CruxDockEntryBuilder].
  final CruxDockEntryBuilder builder;

  /// A count rendered as a `Badge` on the tab (violations, transactions,
  /// connected peers). Zero hides it — the suite's zero-suppression rule.
  final int badgeCount;

  /// View-specific action widgets rendered in the strip's action cluster
  /// while this entry is **active** — VSCode's panel-title-bar actions
  /// (the terminal's `+`, Stage's add-panel / add-widget). They sit before
  /// the standard maximize / pop-out / collapse buttons and disappear when
  /// another tab activates.
  final List<Widget> actions;

  /// Whether the tab can be dragged to another dock (`CruxDock.dockId` +
  /// `CruxDock.onTabMovedIn` must also be configured on both ends). The host
  /// decides which tabs travel — pinned identity tabs (Transactions, Values,
  /// Inspector) stay home; on-demand feature tabs are the natural movers.
  final bool movable;

  /// Deactivates the feature behind an on-demand tab. Non-null makes the tab
  /// closable (renders the `×`); null marks the tab pinned.
  final VoidCallback? onClose;

  /// Whether this entry renders a close affordance.
  bool get closable => onClose != null;

  @override
  bool operator ==(Object other) => other is CruxDockEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
