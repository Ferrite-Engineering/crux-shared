// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Behaviour that used to be asserted twice — once against
// `TabContainerManager` and once against a token-for-token identical
// `PaneContainerManager` — now lives once against the shared
// `ScopedContainerManager` base, plus the type-level guarantees that make the
// two subclasses genuinely non-interchangeable.
//
// The existing per-subclass tests in `container_managers_test.dart` and
// `scope_eviction_test.dart` are deliberately kept as-is: they are the
// regression net proving this refactor changed no observable behaviour.

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer root;

  setUp(() => root = ProviderContainer());
  tearDown(() => root.dispose());

  group('ScopedContainerManager — shared behaviour via both subclasses', () {
    test('containerFor caches, hasContainerFor reports, dispose clears', () {
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);
      final tabId = TabId.generate();
      final paneId = PaneId.generate();

      expect(tabs.hasContainerFor(tabId), isFalse);
      expect(
        identical(tabs.containerFor(tabId), tabs.containerFor(tabId)),
        isTrue,
      );
      expect(tabs.hasContainerFor(tabId), isTrue);

      expect(panes.hasContainerFor(paneId), isFalse);
      expect(
        identical(panes.containerFor(paneId), panes.containerFor(paneId)),
        isTrue,
      );
      expect(panes.hasContainerFor(paneId), isTrue);

      tabs.dispose();
      panes.dispose();
      expect(tabs.hasContainerFor(tabId), isFalse);
      expect(panes.hasContainerFor(paneId), isFalse);
    });

    test('the id provider is overridden inside each child container', () {
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);
      final tabId = TabId.generate();
      final paneId = PaneId.generate();

      expect(tabs.containerFor(tabId).read(tabIdProvider), tabId);
      expect(panes.containerFor(paneId).read(paneIdProvider), paneId);

      tabs.dispose();
      panes.dispose();
    });

    test('the overrides factory contributes per-scope providers', () {
      final marker = Provider<String>((_) => 'unset');
      final tabs = TabContainerManager(
        rootContainer: root,
        overridesFactory: (id) => <Override>[
          marker.overrideWithValue('tab:${id.value}'),
        ],
      );
      final panes = PaneContainerManager(
        rootContainer: root,
        overridesFactory: (id) => <Override>[
          marker.overrideWithValue('pane:${id.value}'),
        ],
      );
      final tabId = TabId.generate();
      final paneId = PaneId.generate();

      expect(tabs.containerFor(tabId).read(marker), 'tab:${tabId.value}');
      expect(panes.containerFor(paneId).read(marker), 'pane:${paneId.value}');

      tabs.dispose();
      panes.dispose();
    });

    test('disposeScope is the generic form of disposeTab / disposePane', () {
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);
      final tabId = TabId.generate();
      final paneId = PaneId.generate();
      tabs
        ..containerFor(tabId)
        ..disposeScope(tabId);
      panes
        ..containerFor(paneId)
        ..disposeScope(paneId);
      expect(tabs.hasContainerFor(tabId), isFalse);
      expect(panes.hasContainerFor(paneId), isFalse);

      // No-op for an id that was never cached.
      expect(() => tabs.disposeScope(TabId.generate()), returnsNormally);
      expect(() => panes.disposeScope(PaneId.generate()), returnsNormally);

      tabs.dispose();
      panes.dispose();
    });
  });

  group('reconcile semantics are preserved for both key spaces', () {
    test('returns the evicted ids and keeps the live ones', () {
      final tabs = TabContainerManager(rootContainer: root);
      final keep = TabId.generate();
      final drop = TabId.generate();
      tabs
        ..containerFor(keep)
        ..containerFor(drop);

      expect(tabs.reconcile({keep}), {drop});
      expect(tabs.hasContainerFor(keep), isTrue);
      expect(tabs.hasContainerFor(drop), isFalse);
      tabs.dispose();
    });

    test('returns an empty set when nothing is stale', () {
      final panes = PaneContainerManager(rootContainer: root);
      final id = PaneId.generate();
      panes.containerFor(id);
      expect(panes.reconcile({id}), isEmpty);
      expect(panes.hasContainerFor(id), isTrue);
      panes.dispose();
    });

    test(
      'an empty set clears everything and leaves the manager usable',
      () {
        // The wholesale-replacement path: unlike dispose(), which is terminal.
        final tabs = TabContainerManager(rootContainer: root);
        final a = TabId.generate();
        final b = TabId.generate();
        tabs
          ..containerFor(a)
          ..containerFor(b);

        expect(tabs.reconcile(const {}), {a, b});
        expect(tabs.hasContainerFor(a), isFalse);

        // Still usable: a fresh container is created, not a dead one revived.
        final revived = tabs.containerFor(a);
        expect(revived.read(tabIdProvider), a);
        expect(tabs.hasContainerFor(a), isTrue);
        tabs.dispose();
      },
    );

    test('reconcileScopes reads only the half the manager owns', () {
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);
      final tabId = TabId.generate();
      final paneId = PaneId.generate();
      tabs.containerFor(tabId);
      panes.containerFor(paneId);

      // A snapshot in which the tab survives and the pane does not. A manager
      // that read the wrong half would evict the wrong container.
      tabs.reconcileScopes(
        WorkspaceScopeSnapshot(tabIds: {tabId}, paneIds: const {}),
      );
      panes.reconcileScopes(
        WorkspaceScopeSnapshot(tabIds: {tabId}, paneIds: const {}),
      );

      expect(tabs.hasContainerFor(tabId), isTrue);
      expect(panes.hasContainerFor(paneId), isFalse);
      tabs.dispose();
      panes.dispose();
    });

    test('the empty snapshot clears both managers', () {
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);
      final tabId = TabId.generate();
      final paneId = PaneId.generate();
      tabs.containerFor(tabId);
      panes.containerFor(paneId);

      const empty = WorkspaceScopeSnapshot.empty();
      tabs.reconcileScopes(empty);
      panes.reconcileScopes(empty);

      expect(tabs.hasContainerFor(tabId), isFalse);
      expect(panes.hasContainerFor(paneId), isFalse);
      tabs.dispose();
      panes.dispose();
    });
  });

  group('TabId and PaneId are NOT substitutable', () {
    // Deduplicating the managers must not deduplicate the key spaces. If a
    // future refactor gave TabId and PaneId a common supertype, or erased the
    // manager's generic to that supertype, mixing them up would start to
    // compile — and mixing them up is the exact bug this substrate prevents.
    // These assertions fail the moment that happens.

    test('the managers are unrelated generic instantiations', () {
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);

      expect(tabs, isA<ScopedContainerManager<TabId>>());
      expect(panes, isA<ScopedContainerManager<PaneId>>());
      expect(tabs, isNot(isA<ScopedContainerManager<PaneId>>()));
      expect(panes, isNot(isA<ScopedContainerManager<TabId>>()));
      expect(tabs, isNot(isA<PaneContainerManager>()));
      expect(panes, isNot(isA<TabContainerManager>()));

      tabs.dispose();
      panes.dispose();
    });

    test('the manager exposes a different static id type on each side', () {
      // Reads the *static* type argument through a generic capture. If a
      // refactor erased the generic to a shared supertype, both sides would
      // report that supertype here and the assertion fails. (Runtime tear-off
      // types cannot be used for this: the base class's methods are
      // generic-erased at runtime.)
      final tabs = TabContainerManager(rootContainer: root);
      final panes = PaneContainerManager(rootContainer: root);

      expect(_scopeIdTypeOf(tabs), TabId);
      expect(_scopeIdTypeOf(panes), PaneId);
      expect(_scopeIdTypeOf(tabs), isNot(_scopeIdTypeOf(panes)));

      tabs.dispose();
      panes.dispose();
    });

    test('neither key-space collection is assignable to the other', () {
      // `tabs.reconcile(setOfPaneIds)` is a compile error; these assertions
      // are the runtime shadow of that, and they fail if the two id types
      // ever acquire a common supertype that the managers key on.
      expect(<TabId>{}, isNot(isA<Set<PaneId>>()));
      expect(<PaneId>{}, isNot(isA<Set<TabId>>()));
      expect(<TabId, int>{}, isNot(isA<Map<PaneId, int>>()));
    });

    test('neither id type is assignable to the other', () {
      final tabId = TabId.generate();
      final paneId = PaneId.generate();
      expect(tabId, isNot(isA<PaneId>()));
      expect(paneId, isNot(isA<TabId>()));
    });

    test('ids with identical UUID strings are still unequal', () {
      // The failure mode that motivates the whole design: a TabId and a PaneId
      // can carry the same UUID text (they do round-trip through the same JSON
      // document) and must never compare equal or collide as map keys.
      const uuid = '11111111-2222-3333-4444-555555555555';
      final tabId = TabId.fromString(uuid);
      final paneId = PaneId.fromString(uuid);

      expect(tabId.value, paneId.value);
      expect(tabId, isNot(equals(paneId)));
      expect(paneId, isNot(equals(tabId)));

      final keyed = <Object, String>{tabId: 'tab', paneId: 'pane'};
      expect(keyed, hasLength(2));
      expect(keyed[tabId], 'tab');
      expect(keyed[paneId], 'pane');
    });

    test(
      'colliding UUIDs address different containers in each manager',
      () {
        const uuid = '99999999-8888-7777-6666-555555555555';
        final tabs = TabContainerManager(rootContainer: root);
        final panes = PaneContainerManager(rootContainer: root);
        final tabId = TabId.fromString(uuid);
        final paneId = PaneId.fromString(uuid);

        final tabContainer = tabs.containerFor(tabId);
        final paneContainer = panes.containerFor(paneId);
        expect(identical(tabContainer, paneContainer), isFalse);
        expect(tabContainer.read(tabIdProvider), tabId);
        expect(paneContainer.read(paneIdProvider), paneId);

        // Evicting the tab must not touch the pane, despite the shared UUID.
        tabs.reconcile(const {});
        expect(tabs.hasContainerFor(tabId), isFalse);
        expect(panes.hasContainerFor(paneId), isTrue);

        tabs.dispose();
        panes.dispose();
      },
    );
  });

  group('the sentinel throw at root is preserved', () {
    // The single best anti-leak decision in the package: reading an id
    // provider outside a scoped container is a loud programming error, not a
    // silent default that quietly bleeds state across tabs. Riverpod wraps the
    // UnimplementedError in a ProviderException, so assert on the guidance
    // text rather than the exception type.

    void expectSentinelThrow(void Function() read, String expectedHint) {
      Object? caught;
      try {
        read();
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'reading at root must throw');
      expect(caught.toString(), contains('UnimplementedError'));
      expect(caught.toString(), contains(expectedHint));
    }

    test('tabIdProvider throws at the root scope', () {
      expectSentinelThrow(
        () => root.read(tabIdProvider),
        'must be overridden inside a per-tab ProviderContainer',
      );
    });

    test('paneIdProvider throws at the root scope', () {
      expectSentinelThrow(
        () => root.read(paneIdProvider),
        'must be overridden inside a per-pane ProviderContainer',
      );
    });

    test('a tab container does not satisfy paneIdProvider', () {
      // Each manager overrides only its own provider — a tab container is not
      // a pane container with a different label.
      final tabs = TabContainerManager(rootContainer: root);
      final container = tabs.containerFor(TabId.generate());
      expectSentinelThrow(
        () => container.read(paneIdProvider),
        'must be overridden inside a per-pane ProviderContainer',
      );
      tabs.dispose();
    });

    test('a pane container does not satisfy tabIdProvider', () {
      final panes = PaneContainerManager(rootContainer: root);
      final container = panes.containerFor(PaneId.generate());
      expectSentinelThrow(
        () => container.read(tabIdProvider),
        'must be overridden inside a per-tab ProviderContainer',
      );
      panes.dispose();
    });
  });
}

/// Captures the *static* scope-id type argument of a manager.
Type _scopeIdTypeOf<Id extends Object>(ScopedContainerManager<Id> manager) =>
    Id;
