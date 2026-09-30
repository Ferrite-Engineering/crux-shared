// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_actions.dart';
import 'package:crux_license/src/license_status.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The licence situation the panel renders.
///
/// Defaults to [CruxLicenseStatus.openCore] — the absence of a licence, which
/// is where every user starts and is not an error. Each Pro overlay
/// overrides it from its own `LicenseService`:
///
/// ```dart
/// licenseStatusProvider.overrideWith(
///   (ref) => ref.watch(licenseServiceProvider).status,
/// ),
/// ```
///
/// Deliberately a plain `Provider` of an immutable value rather than a
/// notifier: the service owns the state machine, and this is the one-way
/// window the shared widget looks through. A widget that could mutate licence
/// state would be a widget four products' services would have to agree with.
final licenseStatusProvider = Provider<CruxLicenseStatus>(
  (ref) => CruxLicenseStatus.openCore,
  name: 'licenseStatusProvider',
);

/// What the licence panel can do, as a seam.
///
/// Defaults to [UnsupportedLicenseActions], so an open-core build — or a
/// product mid-wiring — renders a panel whose controls are honestly disabled
/// rather than a panel that throws when pressed.
final licenseActionsProvider = Provider<CruxLicenseActions>(
  (ref) => const UnsupportedLicenseActions(),
  name: 'licenseActionsProvider',
);

/// The upgrade dialog's "See pricing" action, resolved from [context], or
/// `null` when this build has nothing to sell.
///
/// Exists so all four products wire the same action the same way from launchers
/// that have a `BuildContext` and no `WidgetRef` — which is every one of them,
/// because a deny path is reached from a menu callback rather than a widget
/// build. Reading through `ProviderScope.containerOf` rather than threading a
/// ref down to each call site keeps the wiring to one line per product.
///
/// `listen: false` because a dialog that rebuilt when the licence changed
/// underneath it would be a dialog arguing with itself.
///
/// **Total by construction.** `ProviderScope.containerOf` throws when there is
/// no scope above [context] — a widget test that pumps the dialog directly, a
/// dialog raised above the scope, a host that has not installed one yet. This
/// returns `null` instead, because the caller is a *deny* path: the user has
/// already been refused something, and turning that refusal into a crash is
/// strictly worse than showing the dialog without its pricing button.
Future<void> Function()? cruxSeePricingActionFor(BuildContext context) {
  final CruxLicenseActions actions;
  try {
    actions = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(licenseActionsProvider);
  } on Object {
    return null;
  }
  return cruxSeePricingAction(actions);
}

/// Whether this installation's licence came from the organization's policy
/// file rather than from something a user typed.
///
/// `false` everywhere by default, and overridden by a Pro overlay when
/// `.crux-policy.json` carried a `license` key.
///
/// ### The panel is LOCKED, not hidden, and that is a decision
///
/// When this is true the licence panel disables entry, activation and
/// deactivation, and says in one line that the organization licensed this
/// installation. Everything else — tier, expiry, seat state, product
/// entitlements — stays visible.
///
/// Hiding the panel would be tidier and is wrong. Support needs the engineer on
/// the phone to be able to read their own tier, expiry and seat state; a hidden
/// panel turns every licence question into a blind ticket. If it seems cleaner
/// to hide it, that is the reason not to.
final licenseManagedByOrganizationProvider = Provider<bool>(
  (ref) => false,
  name: 'licenseManagedByOrganizationProvider',
);
