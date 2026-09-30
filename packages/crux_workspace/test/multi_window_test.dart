// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('multi-window placeholders', () {
    test('kMultiWindowAvailable starts disabled', () {
      // Flipping this constant to true is gated on Flutter multi-window
      // reaching stable AND a concrete delegate being registered.
      expect(kMultiWindowAvailable, isFalse);
    });

    test('NoopTabDetachingDelegate methods are non-throwing', () {
      const delegate = NoopTabDetachingDelegate();
      final container = ProviderContainer();
      expect(
        () => delegate.detachTab(TabId.generate(), container),
        returnsNormally,
      );
      expect(() => delegate.reattachTab(TabId.generate()), returnsNormally);
      container.dispose();
    });

    test('NoopPanelPopOutDelegate methods are non-throwing', () {
      const delegate = NoopPanelPopOutDelegate();
      final container = ProviderContainer();
      expect(() => delegate.popOutPanel('stage', container), returnsNormally);
      expect(() => delegate.reattachPanel('stage'), returnsNormally);
      container.dispose();
    });

    test(
      'tabDetachingDelegateProvider defaults to NoopTabDetachingDelegate',
      () {
        final container = ProviderContainer();
        final delegate = container.read(tabDetachingDelegateProvider);
        expect(delegate, isA<NoopTabDetachingDelegate>());
        container.dispose();
      },
    );

    test('panelPopOutDelegateProvider defaults to NoopPanelPopOutDelegate', () {
      final container = ProviderContainer();
      final delegate = container.read(panelPopOutDelegateProvider);
      expect(delegate, isA<NoopPanelPopOutDelegate>());
      container.dispose();
    });
  });
}
