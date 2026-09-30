// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('aiExperimentalBuildFlagProvider', () {
    test('defaults to kAiExperimental (true on the test runner)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(aiExperimentalBuildFlagProvider), kAiExperimental);
      expect(container.read(aiExperimentalBuildFlagProvider), isTrue);
    });
  });

  group('aiExperimentalUserToggleProvider', () {
    test('defaults to false (off-by-default opt-in)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(aiExperimentalUserToggleProvider), isFalse);
    });
  });

  group('aiExperimentalEnabledProvider', () {
    ProviderContainer containerWith({
      required bool buildFlag,
      required bool userToggle,
    }) {
      final container = ProviderContainer(
        overrides: [
          aiExperimentalBuildFlagProvider.overrideWithValue(buildFlag),
          aiExperimentalUserToggleProvider.overrideWithValue(userToggle),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'is true only when BOTH the build flag and the user toggle are on',
      () {
        expect(
          containerWith(
            buildFlag: true,
            userToggle: true,
          ).read(aiExperimentalEnabledProvider),
          isTrue,
        );
      },
    );

    test('is false when the build flag is off, even if the user opted in', () {
      expect(
        containerWith(
          buildFlag: false,
          userToggle: true,
        ).read(aiExperimentalEnabledProvider),
        isFalse,
      );
    });

    test('is false when the user has not opted in, even on an AI build', () {
      expect(
        containerWith(
          buildFlag: true,
          userToggle: false,
        ).read(aiExperimentalEnabledProvider),
        isFalse,
      );
    });

    test('is false when both are off', () {
      expect(
        containerWith(
          buildFlag: false,
          userToggle: false,
        ).read(aiExperimentalEnabledProvider),
        isFalse,
      );
    });

    test('reacts to the user toggle flipping at runtime', () {
      var userToggle = false;
      final container = ProviderContainer(
        overrides: [
          aiExperimentalBuildFlagProvider.overrideWithValue(true),
          aiExperimentalUserToggleProvider.overrideWith((ref) => userToggle),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(aiExperimentalEnabledProvider), isFalse);
      userToggle = true;
      container.invalidate(aiExperimentalUserToggleProvider);
      expect(container.read(aiExperimentalEnabledProvider), isTrue);
    });
  });
}
