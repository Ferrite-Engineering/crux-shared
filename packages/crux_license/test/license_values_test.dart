// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

/// The value types the licensing surface is built out of.
///
/// Unglamorous, and worth testing anyway: `licenseStatusProvider` is a
/// `Provider<CruxLicenseStatus>`, so Riverpod decides whether to rebuild the
/// panel by calling `==`. A field missing from equality means the panel
/// silently stops updating when only that field changes — a bug that looks
/// like "the seat count is stale" and is very hard to trace back here.
void main() {
  LicenseGrant grantWith({
    LicenseTier tier = LicenseTier.pro,
    Set<CruxProduct> products = const <CruxProduct>{CruxProduct.waveCrux},
    String? licenseId = 'lic-1',
    String? sku = 'wavecrux-pro-monthly',
    DateTime? expiry,
    int? maxMachines = 3,
    String? email = 'buyer@example.com',
    bool fromEntitlements = false,
  }) => LicenseGrant(
    issuerId: 'keygen',
    tier: tier,
    products: products,
    licenseId: licenseId,
    policyId: 'policy-1',
    skuLookupKey: sku,
    expiry: expiry ?? DateTime.utc(2027),
    maxMachines: maxMachines,
    email: email,
    resolvedFromEntitlements: fromEntitlements,
  );

  group('LicenseGrant', () {
    test('two grants describing the same licence are equal', () {
      expect(grantWith(), grantWith());
      expect(grantWith().hashCode, grantWith().hashCode);
    });

    test('every field participates in equality', () {
      // Each of these is a field the panel renders. One left out of `==` is a
      // field the panel stops updating.
      expect(grantWith(tier: LicenseTier.enterprise), isNot(grantWith()));
      expect(
        grantWith(products: const <CruxProduct>{CruxProduct.netCrux}),
        isNot(grantWith()),
      );
      expect(grantWith(licenseId: 'other'), isNot(grantWith()));
      expect(grantWith(sku: 'suite-ent-annual'), isNot(grantWith()));
      expect(grantWith(expiry: DateTime.utc(2028)), isNot(grantWith()));
      expect(grantWith(maxMachines: 25), isNot(grantWith()));
      expect(grantWith(email: 'other@example.com'), isNot(grantWith()));
      expect(grantWith(fromEntitlements: true), isNot(grantWith()));
      expect(grantWith(), isNot('not a grant'));
    });

    test('product set equality is by value, not identity', () {
      final a = grantWith(
        products: <CruxProduct>{CruxProduct.waveCrux, CruxProduct.netCrux},
      );
      final b = grantWith(
        products: <CruxProduct>{CruxProduct.netCrux, CruxProduct.waveCrux},
      );
      expect(a, b, reason: 'order must not matter');
      expect(a.hashCode, b.hashCode);
    });

    test('grants answers per product', () {
      final suite = grantWith(products: CruxProduct.values.toSet());
      for (final product in CruxProduct.values) {
        expect(suite.grants(product), isTrue);
      }
      expect(grantWith().grants(CruxProduct.simCrux), isFalse);
    });

    test('expiry arithmetic', () {
      final grant = grantWith(expiry: DateTime.utc(2027, 6, 15));
      expect(grant.isExpiredAt(DateTime.utc(2027, 6, 14)), isFalse);
      expect(grant.isExpiredAt(DateTime.utc(2027, 6, 16)), isTrue);
      expect(grant.remainingAt(DateTime.utc(2027, 6, 5))!.inDays, 10);
      expect(
        grant.remainingAt(DateTime.utc(2027, 7))!.isNegative,
        isTrue,
        reason: 'past expiry the remainder runs negative rather than clamping',
      );
    });

    test('a perpetual grant never expires and has no remainder', () {
      final grant = LicenseGrant(
        issuerId: 'keygen',
        tier: LicenseTier.enterprise,
        products: CruxProduct.values.toSet(),
      );
      expect(grant.isExpiredAt(DateTime.utc(2099)), isFalse);
      expect(grant.remainingAt(DateTime.utc(2099)), isNull);
    });

    test('toString names the tier and the SKU, for logs', () {
      expect(grantWith().toString(), contains('pro'));
      expect(grantWith().toString(), contains('wavecrux-pro-monthly'));
    });
  });

  group('CruxLicenseStatus', () {
    test('tier follows activation, and grace keeps the licensed tier', () {
      const table = <CruxLicenseActivation, LicenseTier>{
        CruxLicenseActivation.openCore: LicenseTier.openCore,
        CruxLicenseActivation.active: LicenseTier.pro,
        CruxLicenseActivation.notActivatedOnThisMachine: LicenseTier.pro,
        CruxLicenseActivation.grace: LicenseTier.pro,
        CruxLicenseActivation.expired: LicenseTier.openCore,
        CruxLicenseActivation.noSeat: LicenseTier.openCore,
        CruxLicenseActivation.invalid: LicenseTier.openCore,
      };
      expect(
        table.keys.toSet(),
        CruxLicenseActivation.values.toSet(),
        reason: 'a new activation state needs a decided tier, not a default',
      );
      for (final entry in table.entries) {
        final status = CruxLicenseStatus(
          activation: entry.key,
          grant: grantWith(),
        );
        expect(status.tier, entry.value, reason: entry.key.name);
      }
    });

    test('a grant-less status is Open Core whatever the activation', () {
      for (final activation in CruxLicenseActivation.values) {
        expect(
          CruxLicenseStatus(activation: activation).tier,
          LicenseTier.openCore,
          reason: activation.name,
        );
      }
    });

    test('hasCredential is false only at Open Core', () {
      for (final activation in CruxLicenseActivation.values) {
        expect(
          CruxLicenseStatus(activation: activation).hasCredential,
          activation != CruxLicenseActivation.openCore,
          reason: activation.name,
        );
      }
    });

    test('grace days count down, and never go negative', () {
      final status = CruxLicenseStatus(
        activation: CruxLicenseActivation.grace,
        grant: grantWith(),
        graceEndsAt: DateTime.utc(2027, 2),
      );
      expect(status.graceDaysRemainingAt(DateTime.utc(2027)), 31);
      expect(
        status.graceDaysRemainingAt(DateTime.utc(2027, 3)),
        0,
        reason: 'a negative countdown would render as "-12 days remaining"',
      );
    });

    test('grace days are null when not in grace', () {
      expect(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
          grant: grantWith(),
          graceEndsAt: DateTime.utc(2027, 2),
        ).graceDaysRemainingAt(DateTime.utc(2027)),
        isNull,
      );
      expect(
        const CruxLicenseStatus(
          activation: CruxLicenseActivation.grace,
        ).graceDaysRemainingAt(DateTime.utc(2027)),
        isNull,
        reason: 'in grace with no end date, there is nothing to count',
      );
    });

    test('copyWith replaces only what it is given', () {
      final base = CruxLicenseStatus(
        activation: CruxLicenseActivation.active,
        grant: grantWith(),
        seatsUsed: 1,
        seatsTotal: 3,
        machineLabel: 'lab-01',
        lastCheckedAt: DateTime.utc(2026, 9),
      );
      final busy = base.copyWith(busy: true);
      expect(busy.busy, isTrue);
      expect(busy.activation, base.activation);
      expect(busy.grant, base.grant);
      expect(busy.seatsUsed, 1);
      expect(busy.seatsTotal, 3);
      expect(busy.machineLabel, 'lab-01');
      expect(busy.lastCheckedAt, base.lastCheckedAt);

      final moved = base.copyWith(
        activation: CruxLicenseActivation.grace,
        graceEndsAt: DateTime.utc(2027, 2),
        seatsUsed: 2,
        rejection: LicenseRejection.unknownPolicy,
      );
      expect(moved.activation, CruxLicenseActivation.grace);
      expect(moved.seatsUsed, 2);
    });

    test('equality covers every rendered field', () {
      const base = CruxLicenseStatus(activation: CruxLicenseActivation.active);
      expect(
        base,
        const CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
        ),
      );
      expect(
        base.hashCode,
        const CruxLicenseStatus(
          activation: CruxLicenseActivation.active,
        ).hashCode,
      );
      expect(base, isNot(base.copyWith(busy: true)));
      expect(base, isNot(base.copyWith(seatsUsed: 1)));
      expect(base, isNot(base.copyWith(seatsTotal: 3)));
      expect(base, isNot(base.copyWith(machineLabel: 'x')));
      expect(base, isNot(base.copyWith(grant: grantWith())));
      expect(base, isNot(base.copyWith(graceEndsAt: DateTime.utc(2027))));
      expect(base, isNot(base.copyWith(lastCheckedAt: DateTime.utc(2027))));
      expect(base, isNot('not a status'));
    });

    test('openCore is the documented starting point', () {
      expect(
        CruxLicenseStatus.openCore.activation,
        CruxLicenseActivation.openCore,
      );
      expect(CruxLicenseStatus.openCore.busy, isFalse);
      expect(CruxLicenseStatus.openCore.grant, isNull);
      expect(CruxLicenseStatus.openCore.toString(), contains('openCore'));
    });
  });

  group('UnsupportedLicenseActions', () {
    const actions = UnsupportedLicenseActions();

    test('every action refuses, and none of them throws', () async {
      final results = <CruxLicenseActionResult>[
        await actions.activate('key/whatever'),
        await actions.deactivateThisMachine(),
        await actions.refresh(),
        await actions.exportOfflineRequest(),
        await actions.importOfflineToken('token'),
        await actions.openPurchasePage(),
        await actions.openManagePage(),
        await actions.requestEducationalLicense('a@b.edu'),
      ];
      for (final result in results) {
        expect(result.isOk, isFalse);
        expect(
          (result as LicenseActionFailed).failure,
          CruxLicenseActionFailure.notSupported,
        );
      }
    });

    test('it advertises none of the capabilities', () {
      expect(actions.supportsDeactivation, isFalse);
      expect(actions.supportsOfflineActivation, isFalse);
      expect(actions.supportsPurchaseLinks, isFalse);
      expect(actions.supportsManageLink, isFalse);
      expect(actions.supportsEducationalRequest, isFalse);
    });
  });

  group('action results', () {
    test('success carries an optional payload', () {
      expect(const LicenseActionSucceeded().isOk, isTrue);
      expect(const LicenseActionSucceeded().payload, isNull);
      expect(
        const LicenseActionSucceeded(payload: 'blob').payload,
        'blob',
      );
      expect(const LicenseActionSucceeded().toString(), contains('Succeeded'));
    });

    test('failure names its kind, and its rejection when it has one', () {
      const plain = LicenseActionFailed(CruxLicenseActionFailure.offline);
      expect(plain.isOk, isFalse);
      expect(plain.toString(), contains('offline'));

      const rejected = LicenseActionFailed(
        CruxLicenseActionFailure.rejected,
        rejection: LicenseRejection.wrongAccount,
        detail: 'account mismatch',
      );
      expect(rejected.toString(), contains('wrongAccount'));
      expect(rejected.detail, 'account mismatch');
    });
  });

  group('LicenseValidation outcomes', () {
    test('absent is Open Core and carries no grant', () {
      const absent = LicenseAbsent();
      expect(absent.tier, LicenseTier.openCore);
      expect(absent.grant, isNull);
      expect(absent.toString(), contains('Absent'));
    });

    test('accepted exposes the grant tier', () {
      final accepted = LicenseAccepted(grantWith(tier: LicenseTier.edu));
      expect(accepted.tier, LicenseTier.edu);
      expect(accepted.grant.tier, LicenseTier.edu);
      expect(accepted.toString(), contains('Accepted'));
    });

    test('expired keeps the grant but grants no tier on its own', () {
      final expired = LicenseExpired(grantWith());
      expect(expired.grant.tier, LicenseTier.pro);
      expect(
        expired.tier,
        LicenseTier.openCore,
        reason: 'grace is LicenseService s decision, not the validator s',
      );
      expect(expired.toString(), contains('Expired'));
    });

    test('rejected names the reason and stays Open Core', () {
      const rejected = LicenseRejected(
        LicenseRejection.unknownPolicy,
        'policy absent',
      );
      expect(rejected.tier, LicenseTier.openCore);
      expect(rejected.grant, isNull);
      expect(rejected.toString(), contains('unknownPolicy'));
      expect(rejected.toString(), contains('policy absent'));
      expect(
        const LicenseRejected(LicenseRejection.malformed).toString(),
        isNot(contains(':')),
        reason: 'no detail means no trailing colon',
      );
    });
  });

  group('LicenseClaims and KeygenPolicy render for diagnostics', () {
    test('claims name the issuer, policy and entitlement count', () {
      const claims = LicenseClaims(
        issuerId: 'keygen',
        policyId: 'policy-1',
        entitlementCodes: <String>{'WAVECRUX', 'TIER_PRO'},
      );
      final text = claims.toString();
      expect(text, contains('keygen'));
      expect(text, contains('policy-1'));
      expect(text, contains('2'));
    });

    test('a policy renders its name and tier', () {
      const policy = KeygenPolicy(
        id: 'p1',
        name: 'wavecrux-pro-monthly',
        tier: LicenseTier.pro,
        products: <CruxProduct>{CruxProduct.waveCrux},
        duration: Duration(days: 31),
      );
      expect(policy.toString(), contains('wavecrux-pro-monthly'));
      expect(policy.toString(), contains('pro'));
    });
  });

  group('the English panel strings are all present', () {
    // Every getter is rendered somewhere. An empty one is a blank label in a
    // shipped build, and the abstract class cannot catch that.
    const s = CruxLicensePanelStringsEn();
    test('no string is empty', () {
      final values = <String>[
        s.licenseCategoryLabel,
        s.licenseStatusSectionTitle,
        s.licenseKeySectionTitle,
        s.licenseMachineSectionTitle,
        s.licenseOfflineSectionTitle,
        s.licenseTierOpenCore,
        s.licenseTierPro,
        s.licenseTierEnterprise,
        s.licenseTierEdu,
        s.licenseStateOpenCoreBody,
        s.licenseStateActive('2027-01-01'),
        s.licenseStatePerpetual,
        s.licenseStateNotActivated,
        s.licenseStateGrace(12),
        s.licenseStateExpired,
        s.licenseStateInvalid,
        s.licenseSeatsInUse(1, 3),
        s.licenseIdLabel,
        s.licenseSkuLabel,
        s.licenseEmailLabel,
        s.licenseLastChecked('now'),
        s.licenseNeverChecked,
        s.licenseKeyFieldLabel,
        s.licenseKeyFieldHelper,
        s.licenseKeyFieldHelperActive,
        s.licenseActivateButton,
        s.licenseChooseFileButton,
        s.licenseActivatedMessage,
        s.licenseDeactivateButton,
        s.licenseDeactivateConfirmTitle,
        s.licenseDeactivateConfirmBody,
        s.licenseDeactivateConfirmAction,
        s.licenseCancelAction,
        s.licenseDeactivatedMessage,
        s.licenseRefreshButton,
        s.licenseMachineLabel,
        s.licenseOfflineBody,
        s.licenseOfflineSteps,
        s.licenseExportRequestButton,
        s.licenseImportTokenButton,
        s.licenseExportRequestTitle,
        s.licenseCopyAction,
        s.licenseCopiedMessage,
        s.licenseCloseAction,
        s.licenseEduSectionTitle,
        s.licenseEduBody,
        s.licenseEduEmailLabel,
        s.licenseEduRequestButton,
        s.licenseEduCheckYourEmail,
        s.licenseBuyButton,
        s.licenseManageButton,
        s.licenseErrorMalformed,
        s.licenseErrorSignature,
        s.licenseErrorAccount,
        s.licenseErrorUnknownPolicy,
        s.licenseErrorProduct,
        s.licenseErrorEncryptedFile,
        s.licenseErrorOffline,
        s.licenseErrorNoSeat,
        s.licenseErrorRefused,
        s.licenseErrorInvalidEmail,
        s.licenseErrorAlreadyRequested,
        s.licenseErrorNotSupported,
        s.licenseErrorUnknown,
      ];
      for (final value in values) {
        expect(value.trim(), isNotEmpty);
      }
    });

    test('the parameterised ones actually interpolate', () {
      expect(s.licenseStateActive('2027-01-01'), contains('2027-01-01'));
      expect(s.licenseStateGrace(12), contains('12'));
      expect(s.licenseSeatsInUse(1, 3), contains('1'));
      expect(s.licenseSeatsInUse(1, 3), contains('3'));
      expect(s.licenseLastChecked('yesterday'), contains('yesterday'));
    });

    test('the upgrade-dialog English strings are present too', () {
      const u = CruxUpgradeDialogStringsEn();
      for (final value in <String>[
        u.title,
        u.body('Debug Advisor', 'Pro'),
        u.tierNamePro,
        u.tierNameEnterprise,
        u.dismissLabel,
        u.seePricingLabel,
      ]) {
        expect(value.trim(), isNotEmpty);
      }
      expect(u.body('Debug Advisor', 'Pro'), contains('Debug Advisor'));
    });
  });
}
