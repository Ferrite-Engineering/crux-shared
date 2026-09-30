// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TabContainerManager', () {
    test(
      'containerFor returns a parented container with tabIdProvider set',
      () {
        final root = ProviderContainer();
        final manager = TabContainerManager(rootContainer: root);
        final id = TabId.generate();
        final tabContainer = manager.containerFor(id);
        expect(tabContainer.read(tabIdProvider), equals(id));
        manager.dispose();
        root.dispose();
      },
    );

    test('containerFor caches across calls for the same TabId', () {
      final root = ProviderContainer();
      final manager = TabContainerManager(rootContainer: root);
      final id = TabId.generate();
      final c1 = manager.containerFor(id);
      final c2 = manager.containerFor(id);
      expect(identical(c1, c2), isTrue);
      manager.dispose();
      root.dispose();
    });

    test('disposeTab evicts the container', () {
      final root = ProviderContainer();
      final manager = TabContainerManager(rootContainer: root);
      final id = TabId.generate();
      manager.containerFor(id);
      expect(manager.hasContainerFor(id), isTrue);
      manager.disposeTab(id);
      expect(manager.hasContainerFor(id), isFalse);
      manager.dispose();
      root.dispose();
    });

    test('overridesFactory contributes per-tab providers', () {
      final root = ProviderContainer();
      final myProvider = Provider<String>((ref) => 'default');
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: (id) => [myProvider.overrideWithValue(id.value)],
      );
      final id = TabId.generate();
      final tabContainer = manager.containerFor(id);
      expect(tabContainer.read(myProvider), equals(id.value));
      manager.dispose();
      root.dispose();
    });
  });

  group('PaneContainerManager', () {
    test(
      'containerFor returns a parented container with paneIdProvider set',
      () {
        final root = ProviderContainer();
        final manager = PaneContainerManager(rootContainer: root);
        final id = PaneId.generate();
        final paneContainer = manager.containerFor(id);
        expect(paneContainer.read(paneIdProvider), equals(id));
        manager.dispose();
        root.dispose();
      },
    );

    test('disposePane evicts the container', () {
      final root = ProviderContainer();
      final manager = PaneContainerManager(rootContainer: root);
      final id = PaneId.generate();
      manager.containerFor(id);
      expect(manager.hasContainerFor(id), isTrue);
      manager.disposePane(id);
      expect(manager.hasContainerFor(id), isFalse);
      manager.dispose();
      root.dispose();
    });
  });
}
