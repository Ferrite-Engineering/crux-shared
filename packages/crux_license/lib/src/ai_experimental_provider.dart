// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/ai_experimental.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod-overridable view of the [kAiExperimental] build flag.
///
/// Feature/UI code reads this rather than the constant directly so tests can
/// simulate an AI-enabled or AI-disabled build without `--dart-define` on the
/// test runner (`aiExperimentalBuildFlagProvider.overrideWithValue(true)`).
/// It gates the *existence* of the AI surface — e.g. whether the Settings → AI
/// section (which hosts the opt-in toggle) is offered at all.
final aiExperimentalBuildFlagProvider = Provider<bool>(
  (_) => kAiExperimental,
  name: 'aiExperimentalBuildFlagProvider',
);

/// The persisted, off-by-default **user** opt-in for experimental AI features
/// ("Enable experimental AI features").
///
/// `crux_license` ships the default `false`; each host product overrides this
/// with its own persisted setting (e.g. WaveCrux wires it to
/// `appSettingsProvider`'s `aiExperimentalEnabled`). Kept here — alongside the
/// build flag and [aiExperimentalEnabledProvider] — so the combine logic lives
/// in one place every product shares.
final aiExperimentalUserToggleProvider = Provider<bool>(
  (_) => false,
  name: 'aiExperimentalUserToggleProvider',
);

/// Whether experimental AI features are enabled for this build *and* this user:
/// the build flag ([aiExperimentalBuildFlagProvider]) **and** the persisted
/// user opt-in ([aiExperimentalUserToggleProvider]).
///
/// `false` unless both are on. AI configuration and every AI functional surface
/// gate on this; only the opt-in toggle itself remains reachable (under the
/// build flag) while this is `false`, so the user has a control to flip it on.
final aiExperimentalEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(aiExperimentalBuildFlagProvider) &&
      ref.watch(aiExperimentalUserToggleProvider),
  name: 'aiExperimentalEnabledProvider',
);
