// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_validation.dart';
import 'package:meta/meta.dart';

/// Why a licence action did not do what was asked.
enum CruxLicenseActionFailure {
  /// The credential itself was refused. [LicenseActionFailed.rejection]
  /// carries which way.
  rejected,

  /// The issuer could not be reached. Distinguished from every other failure
  /// because it is the one the user should simply retry — and because a
  /// validated key keeps working through it, so it is never fatal.
  offline,

  /// The licence has no free seat. `overageStrategy: NO_OVERAGE` means the
  /// seat after the last one is refused rather than tolerated, so this is a
  /// designed outcome.
  noSeatAvailable,

  /// The issuer refused for a reason of its own — revoked, suspended,
  /// banned.
  refusedByIssuer,

  /// This build does not offer the operation. Offline activation on a
  /// product that has not wired it yet lands here.
  notSupported,

  /// The address supplied is not one this flow accepts — an educational
  /// licence needs an institutional address, and the check is a courtesy to
  /// the user rather than the enforcement (which is the issuer's).
  invalidEmail,

  /// The educational address has already been used to request a licence and
  /// the previous request has not expired.
  alreadyRequested,

  /// Anything else. The detail string is what gets logged.
  unknown,
}

/// Result of a licence action.
@immutable
sealed class CruxLicenseActionResult {
  const CruxLicenseActionResult();

  /// Whether the action did what was asked.
  bool get isOk => this is LicenseActionSucceeded;
}

/// The action succeeded.
@immutable
final class LicenseActionSucceeded extends CruxLicenseActionResult {
  /// Create a success, optionally carrying a [payload] — the exported token
  /// for an export action, for instance.
  const LicenseActionSucceeded({this.payload, this.underReview = false});

  /// Data the action produced, when it produces any.
  final String? payload;

  /// The request was accepted but handed to a person rather than fulfilled.
  ///
  /// Only educational requests set this, and only for an address whose domain
  /// the backend does not recognise. It matters because the two paths give
  /// the user completely different instructions: the automatic one sends a
  /// confirmation link to follow, and this one sends nothing to act on at
  /// all. Telling a reviewed applicant to watch for a link is telling them to
  /// wait for mail that is never coming.
  final bool underReview;

  @override
  String toString() => 'LicenseActionSucceeded()';
}

/// The action failed.
@immutable
final class LicenseActionFailed extends CruxLicenseActionResult {
  /// Create a failure.
  const LicenseActionFailed(this.failure, {this.rejection, this.detail = ''});

  /// What kind of failure.
  final CruxLicenseActionFailure failure;

  /// Which validation rejection, when [failure] is
  /// [CruxLicenseActionFailure.rejected]. The panel maps this to a sentence.
  final LicenseRejection? rejection;

  /// Developer-facing detail for logs. Never rendered raw.
  final String detail;

  @override
  String toString() =>
      'LicenseActionFailed(${failure.name}'
      '${rejection == null ? '' : ', ${rejection!.name}'})';
}

/// What the licence panel can *do*, as a seam.
///
/// Storage, activation against the issuer, machine fingerprinting, grace
/// policy and the phone-home cadence all live in each product's Pro overlay
/// `LicenseService` — they differ per product and they are closed
/// source. The shared panel talks to them only through this interface, which
/// is what lets one widget serve four products.
///
/// The capability getters exist so the panel can render an honest UI on a
/// build that has not wired everything yet: an unsupported action is a
/// disabled control with an explanation, never a button that fails when
/// pressed.
abstract class CruxLicenseActions {
  /// Validate, store and register [credential] — a pasted licence key or the
  /// contents of a licence file.
  Future<CruxLicenseActionResult> activate(String credential);

  /// Release this machine's seat and forget the stored credential.
  Future<CruxLicenseActionResult> deactivateThisMachine();

  /// Re-check the stored credential against the issuer now, out of cadence.
  Future<CruxLicenseActionResult> refresh();

  /// Produce a machine-identifying request for an airgapped activation.
  ///
  /// Returns the request in [LicenseActionSucceeded.payload]. The full flow
  /// is the offline-activation flow; this is the seam it lands on.
  Future<CruxLicenseActionResult> exportOfflineRequest();

  /// Consume an offline activation token or licence file obtained out of
  /// band.
  Future<CruxLicenseActionResult> importOfflineToken(String token);

  /// Open the purchase page in the user's browser.
  Future<CruxLicenseActionResult> openPurchasePage();

  /// Open the subscription-management page in the user's browser.
  Future<CruxLicenseActionResult> openManagePage();

  /// Whether [deactivateThisMachine] is offered.
  bool get supportsDeactivation => true;

  /// Whether [exportOfflineRequest] and [importOfflineToken] are offered.
  bool get supportsOfflineActivation => true;

  /// Whether [openPurchasePage] is offered.
  bool get supportsPurchaseLinks => true;

  /// Whether [openManagePage] is offered.
  ///
  /// Separate from [supportsPurchaseLinks] because the two destinations arrive
  /// at different times: a pricing page exists from day one, while managing a
  /// subscription needs an account page and a Stripe customer-portal link that
  /// only exist once there is something to manage. A build with nowhere to
  /// send the user must not render the button — a "Manage subscription" link
  /// that 404s is worse than no link, because the user concludes their
  /// purchase is broken.
  bool get supportsManageLink => true;

  /// Start the educational-licence round trip for [email].
  ///
  /// The app's whole part in it: collect the address, call the endpoint, and
  /// say "check your email". The issuing side — creating the unactivated
  /// licence, minting a pending token, sending the mail, and honouring the
  /// link — belongs to the commerce backend, which already sends the suite's
  /// transactional mail. **Keygen sends no email of any kind**, so the round
  /// trip is entirely ours and none of it can live here.
  ///
  /// EDU is suite-wide: one `edu-annual` policy grants all four products, so
  /// this is the same call whichever app makes it.
  Future<CruxLicenseActionResult> requestEducationalLicense(String email);

  /// Whether [requestEducationalLicense] is offered.
  bool get supportsEducationalRequest => true;
}

/// The "See pricing" action for `CruxUpgradeDialog`, or `null` when this build
/// has nothing to sell.
///
/// Returning `null` rather than a no-op is the point: an open-core build's
/// actions are [UnsupportedLicenseActions], the dialog renders dismiss alone,
/// and the user never meets a button that goes nowhere. The Pro overlay binds a
/// real `LicenseService` and the button appears, pointing at the same pricing
/// URL the licence panel's own Buy button uses — one address per product rather
/// than one per call site.
Future<void> Function()? cruxSeePricingAction(CruxLicenseActions actions) {
  if (!actions.supportsPurchaseLinks) return null;
  return () async {
    await actions.openPurchasePage();
  };
}

/// Actions that do nothing and say so.
///
/// The default behind `licenseActionsProvider`, and what an open-core build
/// gets: open-core has no `LicenseService` to talk to, and the panel is not
/// part of an open-core build in the first place. Also what tests use when the
/// actions are not the point of the test.
@immutable
class UnsupportedLicenseActions implements CruxLicenseActions {
  /// Const constructor — there is no state.
  const UnsupportedLicenseActions();

  static const CruxLicenseActionResult _unsupported = LicenseActionFailed(
    CruxLicenseActionFailure.notSupported,
    detail: 'no LicenseService is wired into this build',
  );

  @override
  Future<CruxLicenseActionResult> activate(String credential) async =>
      _unsupported;

  @override
  Future<CruxLicenseActionResult> deactivateThisMachine() async => _unsupported;

  @override
  Future<CruxLicenseActionResult> refresh() async => _unsupported;

  @override
  Future<CruxLicenseActionResult> exportOfflineRequest() async => _unsupported;

  @override
  Future<CruxLicenseActionResult> importOfflineToken(String token) async =>
      _unsupported;

  @override
  Future<CruxLicenseActionResult> openPurchasePage() async => _unsupported;

  @override
  Future<CruxLicenseActionResult> openManagePage() async => _unsupported;

  @override
  bool get supportsDeactivation => false;

  @override
  bool get supportsOfflineActivation => false;

  @override
  Future<CruxLicenseActionResult> requestEducationalLicense(
    String email,
  ) async => _unsupported;

  @override
  bool get supportsPurchaseLinks => false;

  @override
  bool get supportsManageLink => false;

  @override
  bool get supportsEducationalRequest => false;
}
