// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/src/project_registry_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:meta/meta.dart';

/// Sentinel id used by [perProjectScope] when the workspace is
/// empty. Keeps the returned provider resolving to a stable value
/// even before any project has been opened.
const String emptyWorkspaceProjectId = '<none>';

/// Construct a Riverpod provider whose state is **scoped per active
/// project**.
///
/// ### What this solves
///
/// A product's multi-project workspace lets the user keep several projects
/// open in browser-style tabs simultaneously. Each project carries its own
/// state — the product's per-feature stores plus dashboard filter / sort /
/// column-visibility state — and those state spaces must not bleed across
/// the project switcher. The naïve approach (global providers reading
/// `activeProjectId`) discards a project's state the moment the user
/// switches tabs; the equally-naïve `family` approach reconstructs state
/// from scratch on every read.
///
/// `perProjectScope` is the binding contract for these scoped providers.
/// Internally it keys the per-project cache by [activeProjectIdProvider];
/// widgets watch the returned provider **as if it were a global provider**
/// (no `.call(id)` boilerplate, no awareness of the multi-project surface at
/// the call site). When the active project switches the returned provider
/// re-emits the next project's state without throwing away the previous
/// project's cached instance — re-activating the prior project snaps back to
/// its retained state.
///
/// ### How features opt in
///
/// A feature whose state should be per-project keeps its real state in a
/// `family` provider keyed by `projectId` and exposes a `perProjectScope`
/// wrapper for widget code:
///
/// ```dart
/// // The real per-project state lives in a family.
/// final _fooStorePerProject =
///     NotifierProvider.family<FooStoreNotifier, FooStore, String>(
///   FooStoreNotifier.new,
/// );
///
/// // Widget-facing scope: keys off the active project automatically.
/// final Provider<FooStore> fooStoreProvider =
///     perProjectScope<FooStore>(
///   'foo_store',
///   (ref, projectId) => ref.watch(_fooStorePerProject(projectId)),
/// );
/// ```
///
/// Writes happen through the underlying family
/// (`ref.read(_fooStorePerProject(id).notifier).mutate(...)`), and the
/// per-project state is retained until the project is hard-removed from the
/// workspace's recent list.
///
/// ### Open Core surface
///
/// Open-core uses `NoopProjectRegistry` which only ever has one project
/// active at a time; the scoping mechanism is a no-op in that mode (one
/// project ⇒ one cached instance ⇒ same shape as a regular provider). The
/// Pro overlay activates the multi-project surface and the scoping becomes
/// load-bearing.
/// ### Retention and eviction — read this before assuming a bound
///
/// The scope caches one wrapper instance per project id **for the lifetime of
/// the `ProviderContainer`**. Nothing evicts it automatically, and that is a
/// deliberate limitation rather than an oversight: the scope does not own the
/// state. The real per-project state lives in the *product's* family (the
/// `_fooStorePerProject` above), and a wrapper this package invalidates
/// cannot free memory the product's family is holding.
///
/// Automatic eviction was evaluated and rejected. Driving it off the
/// workspace's known-project set makes the scope evict on any transient
/// unresolved snapshot, and it silently drops a project's state at a moment
/// the product did not choose — trading a bounded cache for a state-loss bug,
/// which is the worse failure. A host that needs the bound calls
/// [PerProjectScope.evictProject] at a point it controls (a hard close, an
/// explicit "forget this project").
///
/// For that call to actually reclaim memory, the product's underlying family
/// must release when unwatched, or the host must invalidate it too. Evicting
/// the wrapper alone only drops this package's reference.
///
/// In practice the cache is bounded in the shape that matters: one small
/// wrapper per project id the user has opened in this session.
Provider<T> perProjectScope<T>(
  String name,
  T Function(Ref ref, String projectId) build,
) => perProjectScopeWithFamily<T>(name, build).provider;

/// The pair of providers [perProjectScopeWithFamily] produces: the
/// widget-facing [provider] and the [family] that actually backs it.
///
/// Holding both together is the whole point. The obvious-looking alternative —
/// a standalone helper that rebuilds "the same" family from the same name —
/// does not work, because Riverpod identifies providers by **object identity,
/// not by name**. Two `Provider.family` built from identical arguments are
/// different providers with different storage, so seeding one and reading the
/// other silently no-ops. Getting [family] from the same call that produced
/// [provider] is the only way to be sure you are addressing the slot the
/// provider reads.
@immutable
class PerProjectScope<T> {
  const PerProjectScope._({required this.provider, required this.family});

  /// Widget-facing provider. Resolves to the active project's instance; watch
  /// it as if it were a plain global provider.
  final Provider<T> provider;

  /// The underlying per-project family, keyed by project id. Use it to seed
  /// or inspect a specific project's state — including
  /// [emptyWorkspaceProjectId] for the no-project-open case — from tests and
  /// from overlay code that restores a project's prior state.
  ///
  /// Treat this as an escape hatch: widget code should watch [provider].
  final ProviderFamily<T, String> family;

  /// Drops this scope's cached instance for [projectId] from [container].
  ///
  /// Call it when the host decides a project is gone for good — a hard close,
  /// or an explicit "forget this project" — so the cache stays bounded across
  /// a long session. Re-reading the scope for [projectId] afterwards rebuilds
  /// from scratch.
  ///
  /// This releases only *this package's* reference. The product's underlying
  /// family must release when unwatched (or be invalidated alongside) for the
  /// per-project state itself to be reclaimed; see the note on
  /// [perProjectScope]. Evicting the currently-active project is legal but
  /// pointless — the next read immediately rebuilds it.
  void evictProject(ProviderContainer container, String projectId) =>
      container.invalidate(family(projectId));
}

/// Constructs a per-project scope and returns both halves of it — see
/// [perProjectScope] for the full contract, and [PerProjectScope] for why the
/// family must come from this same call.
PerProjectScope<T> perProjectScopeWithFamily<T>(
  String name,
  T Function(Ref ref, String projectId) build,
) {
  final family = Provider.family<T, String>(
    (ref, projectId) => build(ref, projectId),
    name: 'perProjectScope($name)_family',
  );
  final provider = Provider<T>(
    (ref) {
      final id = ref.watch(activeProjectIdProvider) ?? emptyWorkspaceProjectId;
      return ref.watch(family(id));
    },
    name: 'perProjectScope($name)',
  );
  return PerProjectScope<T>._(provider: provider, family: family);
}
