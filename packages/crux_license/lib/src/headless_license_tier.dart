// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Pure Dart only: this file is the `crux_license_headless.dart` barrel, which
// the products' headless binaries and MCP servers link without `dart:ui`, and
// `test/headless_license_tier_closure_test.dart` walks its closure.

import 'dart:io';

import 'package:crux_license/src/beta_period.dart';
import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/feature_gate.dart';
import 'package:crux_license/src/install_fingerprint.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/license_grace.dart';
import 'package:crux_license/src/license_grant.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/license_tier_dev.dart';
import 'package:crux_license/src/license_validation.dart';
import 'package:crux_license/src/license_validator.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:meta/meta.dart';

/// A licence source the user named explicitly (`--license-file` or the
/// product's licence-file environment variable) could not be read.
///
/// Fatal for the run: a CI job that asked for a licence and silently ran as
/// Open Core would skip every licensed check and still report success.
class HeadlessLicenseException implements Exception {
  /// Creates the exception with a user-facing [message].
  const HeadlessLicenseException(this.message);

  /// What went wrong, naming the source.
  final String message;

  @override
  String toString() => message;
}

/// The tier a headless run resolved, and what to tell the user about it.
@immutable
class HeadlessLicenseResolution {
  /// Creates a resolution.
  const HeadlessLicenseResolution({
    required this.tier,
    this.notes = const <String>[],
    this.betaPeriod = kBetaPeriod,
  });

  /// The tier this invocation runs as. During the beta this is still the tier
  /// the licence grants (Open Core when there is none); the beta opens the
  /// gate in [admits], it does not invent a licence.
  final LicenseTier tier;

  /// Lines worth printing: where the licence came from, or why it was not
  /// honoured.
  final List<String> notes;

  /// Whether the public-beta unlock was in effect when this was resolved:
  /// [kBetaPeriod] unless the resolver was built with another value.
  final bool betaPeriod;

  /// Whether a feature gated at [required] may run, as `FeatureGate` answers
  /// it in the app: always during the beta, otherwise when [tier] satisfies
  /// [required] (EDU counts as Pro).
  bool admits(LicenseTier required) =>
      betaPeriod || FeatureGate.satisfiesTier(required, tier);
}

/// Resolves the licence tier for a product's headless binary (its command
/// line and its MCP server), which has no desktop licence store.
///
/// The app learns its tier from a keychain-backed licence controller; a CI
/// agent has no keychain entry and no GUI session, so a headless run looks
/// for a credential in, first hit wins:
///
/// 1. `--license-file <path>`
/// 2. the [envVar] environment variable (`<PRODUCT>_LICENSE_FILE`)
/// 3. the `license` key of the organization's `.crux-policy.json`
///    (inline, or a file path)
///
/// and validates it offline with [CruxLicenseValidator.production], the same
/// Ed25519 check the app runs, with no network call. Licence files parse at
/// every tier. An expired paid licence keeps its tier through the suite grace
/// period, as it does in the app; an expired evaluation does not, as it does
/// not in the app. Anything that does not resolve to a grant runs as Open
/// Core with a note saying why; a source the user named explicitly that
/// cannot be read throws [HeadlessLicenseException].
///
/// A machine file, the offline-activation credential, resolves only on the
/// machine whose fingerprint it names, so for one of those the resolver also
/// says which machine this is. It reads the suite's shared fingerprint file
/// ([SharedInstallFingerprint]), the one the desktop app of every EDACrux
/// product on this account uses, never the OS credential store: that store
/// is a plugin a headless binary cannot link, and on a build agent it would
/// block on a prompt. A licence key or licence file names no machine and
/// needs no fingerprint.
///
/// The result passes through [applyLicenseTierOverride], so a build made with
/// `--dart-define=LICENSE_TIER=...` behaves the same headless as in the app,
/// and carries [kBetaPeriod] so [HeadlessLicenseResolution.admits] opens
/// every gate during the beta, as `FeatureGate` does in the app.
///
/// The source order and the note wording are the ones LintCrux's and
/// SimCrux's command lines already print, so an operator who learned one
/// command line does not re-learn another.
class HeadlessLicenseTierResolver {
  /// Creates a resolver for [product]. Every collaborator is injectable for
  /// tests.
  ///
  /// [envVar] defaults to [licenseFileEnvVarFor] of [product]
  /// (`WAVECRUX_LICENSE_FILE`, `NETCRUX_LICENSE_FILE`, `LINTCRUX_LICENSE_FILE`,
  /// `SIMCRUX_LICENSE_FILE`). [installFingerprint] defaults to
  /// [sharedInstallFingerprint] for [product] and [environment]. [betaPeriod]
  /// defaults to [kBetaPeriod].
  HeadlessLicenseTierResolver({
    required this.product,
    String? envVar,
    LicenseValidator? validator,
    Map<String, String>? environment,
    PolicyLoadResult Function()? loadPolicy,
    Future<String> Function(String path)? readFile,
    DateTime Function()? clock,
    Future<String?> Function()? installFingerprint,
    this.grace = LicenseGracePolicy.standard,
    this.betaPeriod = kBetaPeriod,
  }) : envVar = envVar ?? licenseFileEnvVarFor(product),
       _validator =
           validator ?? CruxLicenseValidator.production(product: product),
       _environment = environment,
       _loadPolicy = loadPolicy ?? const PolicyLoader().load,
       _readFile = readFile ?? _defaultReadFile,
       _clock = clock ?? DateTime.now,
       _installFingerprint =
           installFingerprint ??
           sharedInstallFingerprint(product: product, environment: environment);

  /// The environment variable naming a licence file for [product]'s headless
  /// runs: `<PRODUCT>_LICENSE_FILE`, from the product's entitlement code.
  static String licenseFileEnvVarFor(CruxProduct product) =>
      '${product.entitlementCode}_LICENSE_FILE';

  /// Reads this installation's fingerprint from the suite's shared file for
  /// [environment]: the one every EDACrux product on this account uses.
  ///
  /// When there is none yet it adopts a fingerprint an earlier release of a
  /// command-line product kept in its own legacy file ([product]'s own first,
  /// then the others, in the order the desktop app's licence store tries
  /// them, so the two converge on one value), and failing that mints one into
  /// the shared file. Never the credential store, which a headless binary
  /// cannot link and which would block a build agent on a prompt.
  ///
  /// The default installation fingerprint of the resolver, and what a
  /// product's `license fingerprint` command should print, so a machine file
  /// issued for the value the command printed is the one the resolver
  /// resolves against.
  static Future<String?> Function() sharedInstallFingerprint({
    required CruxProduct product,
    Map<String, String>? environment,
  }) {
    final own = product.slug;
    final files = <String>[
      if (_legacyFingerprintProducts.contains(own)) own,
      ..._legacyFingerprintProducts.where((other) => other != own),
    ];
    return () =>
        SharedInstallFingerprint(environment: environment).readOrCreate(
          legacy: <Future<String?> Function()>[
            for (final file in files)
              InstallFingerprintFile.legacy(
                file,
                environment: environment,
              ).read,
          ],
        );
  }

  /// The products whose earlier releases kept a fingerprint file of their own
  /// for headless runs, read only as migration sources. The same list, in
  /// the same order, as the desktop app's licence store.
  static const List<String> _legacyFingerprintProducts = <String>[
    'lintcrux',
    'simcrux',
  ];

  /// The product whose entitlement a licence must carry.
  final CruxProduct product;

  /// The environment variable naming a licence file, read second.
  final String envVar;

  final LicenseValidator _validator;
  final Map<String, String>? _environment;
  final PolicyLoadResult Function() _loadPolicy;
  final Future<String> Function(String path) _readFile;
  final DateTime Function() _clock;
  final Future<String?> Function() _installFingerprint;

  /// Grace windows applied to an expired licence.
  final LicenseGracePolicy grace;

  /// Whether the public-beta unlock is in effect; carried on every
  /// resolution.
  final bool betaPeriod;

  static Future<String> _defaultReadFile(String path) =>
      File(path).readAsString();

  /// Resolves the tier, naming [licenseFilePath] as the explicit source when
  /// the user passed `--license-file`.
  Future<HeadlessLicenseResolution> resolve({String? licenseFilePath}) async {
    final flag = licenseFilePath?.trim();
    if (flag != null && flag.isNotEmpty) {
      return await _fromExplicitFile(
        flag,
        'license file $flag (--license-file)',
      );
    }

    final env = (_environment ?? Platform.environment)[envVar]?.trim();
    if (env != null && env.isNotEmpty) {
      return await _fromExplicitFile(env, 'license file $env ($envVar)');
    }

    return await _fromPolicy();
  }

  Future<HeadlessLicenseResolution> _fromExplicitFile(
    String path,
    String label,
  ) async {
    final String credential;
    try {
      credential = await _readFile(path);
    } on Object catch (e) {
      throw HeadlessLicenseException('cannot read $label: $e');
    }
    if (credential.trim().isEmpty) {
      throw HeadlessLicenseException('$label is empty');
    }
    return await _validate(credential, label);
  }

  Future<HeadlessLicenseResolution> _fromPolicy() async {
    final PolicyLoadResult loaded;
    try {
      loaded = _loadPolicy();
    } on Object {
      // The loader is documented never to throw; an injected one that does
      // must not take the run down with it.
      return _openCore(const <String>[]);
    }
    if (loaded.wasRejected) {
      final note =
          'license: ignored the policy file ${loaded.sourcePath ?? ''} '
          '(${loaded.rejection!.name}: ${loaded.detail ?? ''}); '
          'running as Open Core.';
      return _openCore(<String>[note]);
    }
    final license = DayOnePolicy.of(loaded.document).license;
    if (license == null) return _openCore(const <String>[]);

    final label = switch (license.kind) {
      PolicyLicenseKind.inline => 'the license in the policy file',
      PolicyLicenseKind.file => 'license file ${license.value} (policy file)',
    };
    final String credential;
    switch (license.kind) {
      case PolicyLicenseKind.inline:
        credential = license.value;
      case PolicyLicenseKind.file:
        try {
          credential = await _readFile(license.value);
        } on Object catch (e) {
          // An organization share that is unreachable from this agent is not
          // the user's typo, so it degrades rather than failing the run.
          return _openCore(<String>[
            'license: cannot read $label ($e); running as Open Core.',
          ]);
        }
    }
    return await _validate(credential, label);
  }

  Future<HeadlessLicenseResolution> _validate(
    String credential,
    String label,
  ) async {
    final now = _clock();
    final validation = await _validator.validate(
      credential,
      now: now,
      fingerprint: await _fingerprintFor(credential),
    );
    switch (validation) {
      case LicenseAccepted(:final grant):
        return _resolved(grant.tier, <String>[
          'license: ${_tierName(grant.tier)} from $label.',
        ]);
      case LicenseExpired(:final grant):
        final expiry = grant.expiry;
        final kept = tierAfterExpiry(grant, now);
        if (expiry != null && kept != null) {
          final ends = grace.endsAfter(
            expiry,
            grant.tier,
            evaluation: grant.isEvaluation,
          );
          final note =
              'license: ${_tierName(kept)} from $label expired on '
              '${_date(expiry)}; its grace period ends on ${_date(ends)}.';
          return _resolved(kept, <String>[note]);
        }
        final on = expiry == null ? '' : ' on ${_date(expiry)}';
        final note = grant.isEvaluation
            ? 'license: $label is an evaluation that expired$on; an '
                  'evaluation has no grace period; running as Open Core.'
            : 'license: $label expired$on and is past its grace period; '
                  'running as Open Core.';
        return _openCore(<String>[note]);
      case LicenseRejected(:final reason, :final detail):
        final why = detail.isEmpty ? reason.name : '${reason.name}: $detail';
        return _openCore(<String>[
          'license: $label was not accepted ($why); running as Open Core.',
        ]);
      case LicenseAbsent():
        return _openCore(<String>[
          'license: $label holds no credential; running as Open Core.',
        ]);
    }
  }

  /// The tier an expired [grant] still grants at [now]: its own while the
  /// suite grace period covers it, `null` once it is past.
  ///
  /// An evaluation gets no grace, as in the app's licence controller: its
  /// expiry is the agreement, with nothing being renewed. A grant with no
  /// expiry cannot have expired, and is refused here rather than read as
  /// perpetual.
  ///
  /// Overridable only so the test suite can run a deliberately broken
  /// resolver (one that keeps every expired tier) and prove its expiry tests
  /// fail against it.
  @protected
  @visibleForOverriding
  LicenseTier? tierAfterExpiry(LicenseGrant grant, DateTime now) {
    final expiry = grant.expiry;
    if (expiry == null) return null;
    final covered = grace.covers(
      expiry: expiry,
      tier: grant.tier,
      now: now,
      evaluation: grant.isEvaluation,
    );
    return covered ? grant.tier : null;
  }

  /// This machine's fingerprint when [credential] is a machine file, else
  /// `null`.
  ///
  /// Only a machine file names a machine, so only a machine file asks which
  /// machine this is, and a run licensed by a key or a licence file never
  /// creates the fingerprint file. A fingerprint that cannot be had is `null`,
  /// which the validator refuses as the wrong machine: failing closed.
  Future<String?> _fingerprintFor(String credential) async {
    final kind = parseLicenseCredential(credential).envelope?.kind;
    if (kind != LicenseCredentialKind.machineFile) return null;
    try {
      return await _installFingerprint();
    } on Object {
      return null;
    }
  }

  HeadlessLicenseResolution _openCore(List<String> notes) =>
      _resolved(LicenseTier.openCore, notes);

  HeadlessLicenseResolution _resolved(LicenseTier tier, List<String> notes) =>
      HeadlessLicenseResolution(
        tier: applyLicenseTierOverride(tier),
        notes: List<String>.unmodifiable(notes),
        betaPeriod: betaPeriod,
      );

  static String _tierName(LicenseTier tier) => switch (tier) {
    LicenseTier.openCore => 'Open Core',
    LicenseTier.edu => 'EDU',
    LicenseTier.pro => 'Pro',
    LicenseTier.enterprise => 'Enterprise',
  };

  static String _date(DateTime at) =>
      at.toUtc().toIso8601String().substring(0, 10);
}
