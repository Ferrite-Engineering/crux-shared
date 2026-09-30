// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/src/storage/eula_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The persistence binding for the accepted-version record.
///
/// Defaults to [InMemoryCruxEulaStorage], which re-presents the agreement on
/// every launch. That is the intended shape of the failure: a host that forgets
/// to bind this annoys its users, where a default that remembered nothing *and*
/// let the app through would ship an un-accepted build. Every product overrides
/// it in its root `ProviderScope` with an adapter over its own preferences
/// layer.
final Provider<CruxEulaStorage> cruxEulaStorageProvider =
    Provider<CruxEulaStorage>(
      (ref) => InMemoryCruxEulaStorage(),
      name: 'cruxEulaStorageProvider',
    );

/// Opens the published agreement in the user's browser.
///
/// Unbound by default and **deliberately not a hard dependency on a URL
/// launcher**: this package must build for a host that has none. A host that
/// leaves it unbound gets a dialog with no "read it online" affordance, which
/// `CruxEulaAcceptanceDialog` renders by hiding the link rather than by showing
/// one that does nothing.
///
/// Hosts bind it to whatever they already use to open external links.
final Provider<Future<void> Function()?> cruxEulaOpenOnlineProvider =
    Provider<Future<void> Function()?>(
      (ref) => null,
      name: 'cruxEulaOpenOnlineProvider',
    );

/// Called when the user declines the agreement.
///
/// EULA section 2.1 is explicit that the application does not proceed until the
/// agreement is accepted, so declining ends the session. The package does not
/// call `exit()` itself: a test must be able to drive the decline path without
/// killing the test runner, and a host on the web has no process to exit. Every
/// desktop product binds this to the same quit path its File → Quit uses.
///
/// Unbound, Decline does nothing visible, which is why
/// `CruxEulaAcceptanceDialog` hides the button rather than rendering a dead
/// one.
final Provider<void Function()?> cruxEulaOnDeclineProvider =
    Provider<void Function()?>(
      (ref) => null,
      name: 'cruxEulaOnDeclineProvider',
    );
