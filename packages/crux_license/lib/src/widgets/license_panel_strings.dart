// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by `CruxLicensePanel`.
///
/// Same pattern as `LicenseBadgeStrings`: every product supplies a subclass
/// backed by its own generated localizations, and the English-only
/// [CruxLicensePanelStringsEn] default lets the widget render in a test or a
/// prototype without wiring l10n first.
///
/// The panel is contributed by the Pro overlay, so these keys live in each
/// overlay's own ARB files rather than the open-core app's. None of them names
/// a product, which is what lets one identical block of keys be added to all
/// four overlays.
@immutable
abstract class CruxLicensePanelStrings {
  /// Const constructor for subclasses.
  const CruxLicensePanelStrings();

  // --- Category and sections -------------------------------------------

  /// Settings rail label for the category, e.g. "License".
  String get licenseCategoryLabel;

  /// Heading of the current-status section.
  String get licenseStatusSectionTitle;

  /// Heading of the key-entry section.
  String get licenseKeySectionTitle;

  /// Heading of the this-machine section.
  String get licenseMachineSectionTitle;

  /// Heading of the offline-activation section.
  String get licenseOfflineSectionTitle;

  // --- Tier and state ---------------------------------------------------

  /// Display name of the Open Core tier.
  String get licenseTierOpenCore;

  /// Display name of the Pro tier.
  String get licenseTierPro;

  /// Display name of the Enterprise tier.
  String get licenseTierEnterprise;

  /// Display name of the Educational tier.
  String get licenseTierEdu;

  /// Explanation shown when no licence is present. Must not read as an
  /// error — Open Core is a complete product, not a broken Pro.
  ///
  /// Names all three paid tiers, EDU included. An earlier wording offered only
  /// "the Pro and Enterprise features", which told an educational user their
  /// key was for something else.
  String get licenseStateOpenCoreBody;

  /// State line for a current licence expiring on [date].
  String licenseStateActive(String date);

  /// State line for a current licence with no expiry.
  String get licenseStatePerpetual;

  /// State line for a valid licence not yet registered on this machine.
  String get licenseStateNotActivated;

  /// State line while the grace period is running, with [days] left.
  String licenseStateGrace(int days);

  /// State line once grace has run out.
  String get licenseStateExpired;

  /// State line when a stored credential no longer validates.
  String get licenseStateInvalid;

  /// Seat usage, e.g. "2 of 3 machines activated".
  String licenseSeatsInUse(int used, int total);

  /// Label of the licence-id row, shown for support.
  String get licenseIdLabel;

  /// Label of the SKU row.
  String get licenseSkuLabel;

  /// Label of the licensee-email row.
  String get licenseEmailLabel;

  /// Row showing when the app last reached the issuer, at [time].
  String licenseLastChecked(String time);

  /// Row shown when the app has never reached the issuer — which is a
  /// perfectly good state, since a validated key works offline.
  String get licenseNeverChecked;

  // --- Key entry --------------------------------------------------------

  /// Label of the credential text field.
  String get licenseKeyFieldLabel;

  /// Helper text under the credential field, with no licence yet.
  String get licenseKeyFieldHelper;

  /// Helper text under the credential field when a licence is already active.
  ///
  /// The field stays available on purpose — a licence is replaced more often
  /// than it is first entered: upgrading EDU to Pro or Pro to Enterprise,
  /// moving to a renewed key, or swapping a personal key for a company one.
  /// Hiding it would strand every one of those. What it needs is to stop
  /// reading like the first-run text, which is what this says.
  String get licenseKeyFieldHelperActive;

  /// Label of the activate button.
  String get licenseActivateButton;

  /// Label of the button that loads a licence file from disk.
  String get licenseChooseFileButton;

  /// Snack message after a successful activation.
  String get licenseActivatedMessage;

  // --- This machine -----------------------------------------------------

  /// Label of the deactivate button.
  String get licenseDeactivateButton;

  /// Title of the deactivate confirmation dialog.
  String get licenseDeactivateConfirmTitle;

  /// Body of the deactivate confirmation dialog.
  String get licenseDeactivateConfirmBody;

  /// Confirm action of the deactivate dialog.
  String get licenseDeactivateConfirmAction;

  /// Cancel action of any dialog in this panel.
  String get licenseCancelAction;

  /// Snack message after a successful deactivation.
  String get licenseDeactivatedMessage;

  /// Label of the re-check button.
  String get licenseRefreshButton;

  /// Label of the row naming this machine.
  String get licenseMachineLabel;

  // --- Offline activation -----------------------------------------------

  /// Explanation of what the offline-activation controls are for.
  ///
  /// Leads with the fact that a key already works without a network, because
  /// the commonest airgap mistake is assuming it does not and going looking
  /// for a flow that is not needed. An earlier wording said only "export a
  /// request, have it signed where there is a connection" — which named no
  /// actor, so there was no way to act on it.
  String get licenseOfflineBody;

  /// The actual steps, for the case where the round trip *is* wanted.
  String get licenseOfflineSteps;

  /// Label of the export-request button.
  String get licenseExportRequestButton;

  /// Label of the import-token button.
  String get licenseImportTokenButton;

  /// Title of the dialog showing the exported request.
  String get licenseExportRequestTitle;

  /// Label of the copy-to-clipboard action.
  String get licenseCopyAction;

  /// Confirmation that the request was copied.
  String get licenseCopiedMessage;

  /// Close action of any dialog in this panel.
  String get licenseCloseAction;

  // --- Educational licence ----------------------------------------------

  /// Heading of the educational-licence section.
  String get licenseEduSectionTitle;

  /// Explanation of what an educational licence is and what it costs.
  String get licenseEduBody;

  /// Label of the institutional-email field.
  String get licenseEduEmailLabel;

  /// Label of the request button.
  String get licenseEduRequestButton;

  /// Shown after a request is accepted. The licence does not arrive here —
  /// it arrives by email, and saying so is the whole job of this string.
  String get licenseEduCheckYourEmail;

  /// Shown when the request went to a person instead of being fulfilled
  /// automatically, because the address's domain is not one the backend
  /// recognises.
  ///
  /// Defaulted rather than abstract, unlike every other string here. Each
  /// product implements this interface from its own ARB files, so a new
  /// abstract getter compiles nowhere until five locales have a new entry in
  /// each of four products. Shipping the English sentence now and localising
  /// it next is the lesser fault: the alternative on the shelf is telling a
  /// reviewed applicant to follow a link that does not exist.
  String get licenseEduUnderReview =>
      'Thanks — that domain is not one we recognise automatically, so a '
      'person is checking the request. There is no link to follow: the '
      'license will arrive by email. If you have not heard within two '
      'working days, write to edu@ferriteengineering.com.';

  // --- Commerce links ---------------------------------------------------

  /// Label of the buy-a-licence button.
  String get licenseBuyButton;

  /// Label of the manage-subscription button.
  String get licenseManageButton;

  // --- Failures ---------------------------------------------------------

  /// The text is not a licence key or licence file at all.
  String get licenseErrorMalformed;

  /// The signature does not verify — tampered, or not ours.
  String get licenseErrorSignature;

  /// Authentic, but minted under an account this build does not trust.
  String get licenseErrorAccount;

  /// Authentic, but names a product this build cannot resolve. The remedy is
  /// updating the app, so the message should say so.
  String get licenseErrorUnknownPolicy;

  /// A licence for one of the other products in the suite.
  String get licenseErrorProduct;

  /// A machine file checked out for another machine. Concrete rather than
  /// abstract so an adapter written before machine files existed still
  /// compiles; an overlay overrides it to localise.
  String get licenseErrorWrongMachine =>
      'This license file was issued for a different machine. Export an '
      'offline activation request from this machine and ask for a file '
      'issued against it.';

  /// An encrypted licence file, which a paste alone cannot open.
  ///
  /// **Name both schemes.** The Keygen portal issues `base64+ed25519` and
  /// `aes-256-gcm+ed25519` and will happily hand over the second by mistake;
  /// the second uses the licence key itself as its decryption secret, so a
  /// pasted file alone can never open it. Whoever hits this has to go back to
  /// whichever administrator issued the file and ask for a specific thing, and
  /// "this file is encrypted" does not tell them what to ask for. It is the
  /// most likely support ticket in the offline-activation flow.
  String get licenseErrorEncryptedFile;

  /// One line stating that the organization licensed this installation, shown
  /// in place of the key-entry controls on a managed deployment.
  ///
  /// The panel is locked rather than hidden so support can ask the engineer on
  /// the phone to read their own tier and expiry — see
  /// `licenseManagedByOrganizationProvider`.
  String get licenseManagedByOrganization;

  /// What a managed installation is told when its policy licence has expired
  /// and the machine cannot reach the issuer.
  ///
  /// Deliberately does not tell the user to do anything: on a managed
  /// deployment they cannot, and an instruction they cannot follow is worse
  /// than none. It names the grace window and points at the administrator.
  String get licenseManagedExpired;

  // --- A refused policy file ---------------------------------------------

  /// The line every refusal starts with: the organization's policy file was
  /// found and **refused**, so nothing in it is in force. Points at the
  /// administrator — none of the causes below can be fixed from the keyboard,
  /// and an instruction the user cannot follow is worse than none.
  ///
  /// Without this a refused policy is a line in the process log, and from the
  /// app a refused file and an absent one look identical: an ungoverned seat.
  String get licensePolicyRefused;

  /// Why, when the file is signed and the machine has no usable organization
  /// public key to check it against — not installed, unreadable, malformed,
  /// or writable by every user.
  String get licensePolicyRefusedNoPublicKey;

  /// Why, when the signature does not verify against the installed key: the
  /// file was changed after signing, or signed with a different key.
  String get licensePolicyRefusedBadSignature;

  /// Why, when the file is unsigned and was reached through `CRUX_POLICY`,
  /// which any process can set and is therefore not a trusted location.
  String get licensePolicyRefusedUntrustedUnsigned;

  /// Why, when the `signature` field is present but is not a signature.
  String get licensePolicyRefusedMalformedSignature;

  /// Why, when the file is unsigned and sits at the well-known path, but that
  /// path is writable by every user and so is not the trusted location it is
  /// meant to be.
  String get licensePolicyRefusedInsecurePath;

  /// The issuer could not be reached.
  String get licenseErrorOffline;

  /// Every seat on the licence is in use.
  String get licenseErrorNoSeat;

  /// The issuer refused — revoked, suspended.
  String get licenseErrorRefused;

  /// The address supplied does not look institutional.
  String get licenseErrorInvalidEmail;

  /// A request for this address is already outstanding.
  String get licenseErrorAlreadyRequested;

  /// This build does not offer the operation.
  String get licenseErrorNotSupported;

  /// Anything else.
  String get licenseErrorUnknown;
}

/// Default English [CruxLicensePanelStrings].
class CruxLicensePanelStringsEn extends CruxLicensePanelStrings {
  /// Creates the default English string set.
  const CruxLicensePanelStringsEn();

  @override
  String get licenseCategoryLabel => 'License';

  @override
  String get licenseStatusSectionTitle => 'Status';

  @override
  String get licenseKeySectionTitle => 'License key';

  @override
  String get licenseMachineSectionTitle => 'This machine';

  @override
  String get licenseOfflineSectionTitle => 'Offline activation';

  @override
  String get licenseTierOpenCore => 'Open Core';

  @override
  String get licenseTierPro => 'Pro';

  @override
  String get licenseTierEnterprise => 'Enterprise';

  @override
  String get licenseTierEdu => 'Educational';

  @override
  String get licenseStateOpenCoreBody =>
      'You are running Open Core — the complete free edition. Enter a license '
      'key below to unlock what it covers: Educational, Pro or Enterprise.';

  @override
  String licenseStateActive(String date) => 'Active until $date';

  @override
  String get licenseStatePerpetual => 'Active — no expiry';

  @override
  String get licenseStateNotActivated =>
      'Valid license — this machine is not registered yet';

  @override
  String licenseStateGrace(int days) =>
      'Renewal overdue — $days days of grace remaining';

  @override
  String get licenseStateExpired => 'Expired — running as Open Core';

  @override
  String get licenseStateInvalid =>
      'The stored license is no longer valid — running as Open Core';

  @override
  String licenseSeatsInUse(int used, int total) =>
      '$used of $total machines activated';

  @override
  String get licenseIdLabel => 'License ID';

  @override
  String get licenseSkuLabel => 'Plan';

  @override
  String get licenseEmailLabel => 'Licensed to';

  @override
  String licenseLastChecked(String time) => 'Last checked $time';

  @override
  String get licenseNeverChecked => 'Never checked online — works offline';

  @override
  String get licenseKeyFieldLabel => 'License key or license file';

  @override
  String get licenseKeyFieldHelper =>
      'Paste the key from your purchase email. The contents of a license file '
      'work here too.';

  @override
  String get licenseKeyFieldHelperActive =>
      'Replacing a license? Paste the new key here — after upgrading to Pro '
      'or Enterprise, for example. The one above keeps working until you do.';

  @override
  String get licenseActivateButton => 'Activate';

  @override
  String get licenseChooseFileButton => 'Load file…';

  @override
  String get licenseActivatedMessage => 'License activated.';

  @override
  String get licenseDeactivateButton => 'Deactivate this machine';

  @override
  String get licenseDeactivateConfirmTitle => 'Deactivate this machine?';

  @override
  String get licenseDeactivateConfirmBody =>
      'This machine releases its seat and returns to Open Core. That covers '
      'every EDACrux product on this computer, because a seat is a machine. '
      'Your files and settings are untouched, and you can activate again at '
      'any time.';

  @override
  String get licenseDeactivateConfirmAction => 'Deactivate';

  @override
  String get licenseCancelAction => 'Cancel';

  @override
  String get licenseDeactivatedMessage => 'This machine was deactivated.';

  @override
  String get licenseRefreshButton => 'Check now';

  @override
  String get licenseMachineLabel => 'Machine';

  @override
  String get licenseOfflineBody =>
      'You do not need this to run offline. A license key is verified on this '
      'machine, not on our servers, so pasting it above already works with no '
      'network at all. Use this only to register this machine against your '
      'license so its seat is counted, or if this app does not recognise your '
      'plan yet.';

  @override
  String get licenseOfflineSteps =>
      'Export the request, send it to support@ferriteengineering.com with '
      'your license key, and import the license file you get back.';

  @override
  String get licenseExportRequestButton => 'Export request';

  @override
  String get licenseImportTokenButton => 'Import token';

  @override
  String get licenseExportRequestTitle => 'Offline activation request';

  @override
  String get licenseCopyAction => 'Copy';

  @override
  String get licenseCopiedMessage => 'Copied to the clipboard.';

  @override
  String get licenseCloseAction => 'Close';

  @override
  String get licenseEduSectionTitle => 'Educational license';

  @override
  String get licenseEduBody =>
      'Free for students and educators, for non-commercial use. One license '
      'covers all four products and renews annually.';

  @override
  String get licenseEduEmailLabel => 'Institutional email address';

  @override
  String get licenseEduRequestButton => 'Request a license';

  @override
  String get licenseEduCheckYourEmail =>
      'Check your email — we have sent a link to confirm the address. The '
      'license arrives once you follow it.';

  @override
  String get licenseBuyButton => 'Buy a license';

  @override
  String get licenseManageButton => 'Manage subscription';

  @override
  String get licenseErrorMalformed =>
      'That does not look like a license key or a license file.';

  @override
  String get licenseErrorSignature =>
      'This license could not be verified. Check that the whole key was '
      'copied, including the leading "key/".';

  @override
  String get licenseErrorAccount =>
      'This license was not issued for this product family.';

  @override
  String get licenseErrorUnknownPolicy =>
      'This license is newer than this version of the app. Update to the '
      'latest release, or load your license file instead.';

  @override
  String get licenseErrorProduct =>
      'This license is for a different product in the suite.';

  @override
  String get licenseErrorEncryptedFile =>
      'This license file is encrypted (aes-256-gcm+ed25519) and cannot be '
      'opened by pasting it. Ask for a base64+ed25519 license file instead, '
      'or use your license key.';

  @override
  String get licenseManagedByOrganization =>
      'Your organization licensed this installation. Its license is managed '
      'centrally and cannot be changed here.';

  @override
  String get licenseManagedExpired =>
      'The license your organization deployed has expired. This installation '
      'keeps working during its grace period; contact your administrator to '
      'have it renewed.';

  @override
  String get licensePolicyRefused =>
      "Your organization's policy file was found but refused, so none of its "
      'settings are in force. Ask your administrator.';

  @override
  String get licensePolicyRefusedNoPublicKey =>
      'The file is signed, but this machine has no usable organization public '
      'key to verify it against.';

  @override
  String get licensePolicyRefusedBadSignature =>
      'Its signature does not verify against the installed organization '
      'public key: the file was changed after it was signed, or signed with a '
      'different key.';

  @override
  String get licensePolicyRefusedUntrustedUnsigned =>
      'The file is unsigned and was reached through the CRUX_POLICY '
      'environment variable, which is not a trusted location.';

  @override
  String get licensePolicyRefusedMalformedSignature =>
      'Its signature field is not a valid Ed25519 signature.';

  @override
  String get licensePolicyRefusedInsecurePath =>
      'The file is unsigned and its location is writable by every user, so it '
      'cannot be trusted.';

  @override
  String get licenseErrorOffline =>
      'Could not reach the license server. Your license keeps working; try '
      'again when you are online.';

  @override
  String get licenseErrorNoSeat =>
      'Every seat on this license is in use. Deactivate another machine '
      'first, or email support@ferriteengineering.com to free a seat on a '
      'machine you can no longer reach.';

  @override
  String get licenseErrorRefused =>
      'The license server refused this license. Contact support.';

  @override
  String get licenseErrorInvalidEmail =>
      'That does not look like an institutional email address.';

  @override
  String get licenseErrorAlreadyRequested =>
      'A license request for that address is already on its way. Check your '
      'email, including the spam folder.';

  @override
  String get licenseErrorNotSupported =>
      'This build does not offer that action.';

  @override
  String get licenseErrorUnknown => 'Something went wrong. Please try again.';
}
