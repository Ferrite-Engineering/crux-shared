// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/tab_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time flag that gates multi-window affordances across the suite.
///
/// When `false` (the default), products render the "Move to New Window" /
/// panel-pop-out affordances in a disabled state so the seam is visible but
/// the actions cannot be invoked. When Flutter's multi-window API reaches
/// the stable channel, products may flip this constant to `true` and register
/// concrete [TabDetachingDelegate] / [PanelPopOutDelegate] implementations
/// via [tabDetachingDelegateProvider] / [panelPopOutDelegateProvider].
///
/// ### This code is intentionally inert — do not delete it as dead code
///
/// Everything in this library is unreachable in production today, because
/// this constant is `const false` and the only registered delegates are
/// no-ops. That is deliberate, not abandoned scaffolding.
///
/// Multi-window tab detachment is a specified, roadmapped feature of the
/// commercial tier. The tab architecture — per-tab `ProviderContainer`s
/// resolved through a container manager, rather than tab state held in
/// globals — was designed so that adopting a real multi-window API is a
/// delegate registration rather than a rewrite. These abstracts and the
/// rendered-but-disabled affordances are what make that seam visible to a
/// reader of the open-source code; deleting them would hide the design and
/// guarantee the rewrite.
///
/// **Review trigger.** Revisit this library when Flutter's native
/// multi-window API reaches the stable channel (it is experimental as of
/// 3.41). At that point either flip [kMultiWindowAvailable] and land concrete
/// delegates, or — if the shipped API turns out to be shaped differently
/// enough that these abstracts no longer fit it — delete them and design
/// against the real API. Until that trigger fires, "unused" is the expected
/// state and is not a finding.
const bool kMultiWindowAvailable = false;

/// Delegate that moves a tab's [ProviderContainer] to a new platform window
/// and reattaches it back to the main window.
///
/// The no-op default [NoopTabDetachingDelegate] is registered as the value of
/// [tabDetachingDelegateProvider]. Products provide a concrete implementation
/// via a Pro/Enterprise overlay's provider overrides when
/// [kMultiWindowAvailable] is set to `true`.
abstract class TabDetachingDelegate {
  /// Move the tab identified by [id] — and its live [container] — into a new
  /// platform window. Callers are responsible for any post-detach bookkeeping
  /// (workspace state updates, lifecycle tracking).
  void detachTab(TabId id, ProviderContainer container);

  /// Move a previously detached tab back into the main window.
  void reattachTab(TabId id);
}

/// No-op implementation used until Flutter multi-window reaches stable.
class NoopTabDetachingDelegate implements TabDetachingDelegate {
  /// Creates the no-op delegate.
  const NoopTabDetachingDelegate();

  @override
  void detachTab(TabId id, ProviderContainer container) {}

  @override
  void reattachTab(TabId id) {}
}

/// Delegate that moves an individual panel — Stage, transaction view, or
/// diagnostics — into its own platform window while sharing the same Dart
/// isolate and Riverpod root [ProviderContainer].
///
/// The no-op default [NoopPanelPopOutDelegate] is registered as the value of
/// [panelPopOutDelegateProvider]. Products provide a concrete implementation
/// via a Pro/Enterprise overlay's provider overrides when
/// [kMultiWindowAvailable] is set to `true`.
abstract class PanelPopOutDelegate {
  /// Move the panel identified by [panelId] into a new platform window,
  /// providing the [container] from the enclosing tab scope so the panel
  /// can still watch per-tab providers.
  void popOutPanel(String panelId, ProviderContainer container);

  /// Move a previously popped-out panel back into its host tab window.
  void reattachPanel(String panelId);
}

/// No-op implementation used until Flutter multi-window reaches stable.
class NoopPanelPopOutDelegate implements PanelPopOutDelegate {
  /// Creates the no-op delegate.
  const NoopPanelPopOutDelegate();

  @override
  void popOutPanel(String panelId, ProviderContainer container) {}

  @override
  void reattachPanel(String panelId) {}
}

/// Provides the [TabDetachingDelegate] implementation.
///
/// Defaults to [NoopTabDetachingDelegate]. Products replace this with a
/// concrete implementation once [kMultiWindowAvailable] is set to `true`.
final Provider<TabDetachingDelegate> tabDetachingDelegateProvider =
    Provider<TabDetachingDelegate>(
      (ref) => const NoopTabDetachingDelegate(),
    );

/// Provides the [PanelPopOutDelegate] implementation.
///
/// Defaults to [NoopPanelPopOutDelegate]. Products replace this with a
/// concrete implementation once [kMultiWindowAvailable] is set to `true`.
final Provider<PanelPopOutDelegate> panelPopOutDelegateProvider =
    Provider<PanelPopOutDelegate>(
      (ref) => const NoopPanelPopOutDelegate(),
    );
