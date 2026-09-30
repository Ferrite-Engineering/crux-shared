// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/src/models/update_manifest.dart';

/// Which of the releases a manifest advertises matter to this seat.
///
/// Every desktop download is one binary per product, and a licence key unlocks
/// paid features in place. A user who never buys therefore runs the same build
/// a paying customer does, and a release that changed only paid features is
/// still "newer" for them. The manifest's `open_core_version` names the newest
/// release that changed what a seat without paid features gets; this says
/// whether the running seat is one.
///
/// Mirrors a licence tier without depending on `crux_license`, the same way
/// `UpdatePolicy` mirrors `crux_policy`: this package knows the shape of the
/// answer, not how a licence is validated or what a tier unlocks. Each product
/// binds `updateEditionProvider` from its own tier and beta-period providers.
enum UpdateEdition {
  /// Paid features are unlocked on this seat — a Pro, Educational or
  /// Enterprise licence, or any tier while a beta period holds every gate
  /// open. Every newer release is offered.
  ///
  /// Also the unbound default: a product that forgets the binding tells its
  /// free users about a release they cannot use, which is the lesser failure
  /// than hiding a release from the customers who paid for it.
  unlocked,

  /// No paid features are unlocked. A newer release is offered only when it
  /// changed what this seat gets, or when it is mandatory.
  openCore;

  /// The edition for a seat whose paid features are, or are not, unlocked.
  ///
  /// The host computes [paidFeaturesUnlocked] with the same gate its paid
  /// features use, so the update banner and the features cannot disagree about
  /// what the seat is:
  ///
  /// ```dart
  /// updateEditionProvider.overrideWith(
  ///   (ref) => UpdateEdition.of(
  ///     paidFeaturesUnlocked:
  ///         ref.watch(betaPeriodProvider) ||
  ///         FeatureGate.satisfiesTier(
  ///           LicenseTier.pro,
  ///           ref.watch(licenseTierProvider),
  ///         ),
  ///   ),
  /// ),
  /// ```
  static UpdateEdition of({required bool paidFeaturesUnlocked}) =>
      paidFeaturesUnlocked ? unlocked : openCore;

  /// Whether [info] may be offered to a seat running [currentVersion].
  ///
  /// [info] is a release the update check has already found newer than
  /// [currentVersion]; this decides only whether it is *relevant*. Pure, and
  /// the whole of the rule:
  ///
  /// * **[unlocked]** — always.
  /// * **[openCore]** — when [UpdateInfo.mandatory] is set, or when the
  ///   running build predates the manifest's `open_core_version`
  ///   ([UpdateInfo.changesOpenCoreSince]).
  ///
  /// `mandatory` covers both a release the manifest marks critical and a
  /// running build below `min_supported_version`, because the update check
  /// forces `mandatory` on for the latter before this is consulted. Neither is
  /// ever withheld: a security fix or an end of support applies to every seat,
  /// paid or not.
  ///
  /// A seat that is withheld a release is not stranded on an old build. The
  /// moment a later release changes open core, `open_core_version` moves past
  /// the running version and the seat is offered the newest release, which
  /// carries everything in between.
  bool offers(UpdateInfo info, {required String currentVersion}) =>
      switch (this) {
        unlocked => true,
        openCore => info.mandatory || info.changesOpenCoreSince(currentVersion),
      };
}
