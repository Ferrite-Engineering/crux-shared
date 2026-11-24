// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared headless tier resolver.
//
// The first two groups are the two product copies' own suites (LintCrux's
// and SimCrux's command lines each carried a resolver and its tests), ported
// and run once per product against this one resolver. The rest add what the
// copies did not test: the documented environment variable names, every
// tier's grace window, evaluations, real missing and unreadable files, a
// foreign licence signed for real, the beta flag, and a mutation proof that a
// resolver keeping an expired tier fails the expiry oracle.
//
// Expected values come from outside the resolver: the source order and the
// `<PRODUCT>_LICENSE_FILE` names are the documented command-line contract;
// the grace windows are the suite's policy (30 days Pro, 60 EDU, 90
// Enterprise, none for an evaluation); dates are derived by hand from the
// signed expiry; credentials are signed with a throwaway test key (seed 7,
// as the copies' committed fixtures were) and checked by the real validator.
import 'dart:io';

import 'package:crux_license/crux_license_core.dart';
import 'package:crux_license/crux_license_headless.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/license_fixtures.dart';

/// A validator that answers from a table keyed by the credential text, so
/// the resolver's source order and outcome mapping are testable without a
/// signed credential. Records every credential it was asked about.
class _TableValidator implements LicenseValidator {
  _TableValidator(this.outcomes);

  final Map<String, LicenseValidation> outcomes;
  final List<String> seen = <String>[];

  @override
  String get name => 'table';

  @override
  Future<LicenseValidation> validate(
    String? rawCredential, {
    DateTime? now,
    String? fingerprint,
  }) async {
    seen.add(rawCredential?.trim() ?? '');
    return outcomes[rawCredential?.trim()] ??
        const LicenseRejected(LicenseRejection.malformed, 'not in table');
  }
}

PolicyLoadResult _policy(String json) =>
    PolicyLoadResult(document: PolicyDocument.parse(json));

PolicyLoadResult _noPolicy() =>
    const PolicyLoadResult(document: PolicyDocument.absent);

/// The fingerprint the signed machine files are checked out for.
const String _boundFingerprint = 'this-install-fp-0001';

/// The products whose command lines carried a copy of the resolver.
const List<CruxProduct> _copyProducts = <CruxProduct>[
  CruxProduct.lintCrux,
  CruxProduct.simCrux,
];

void main() {
  final now = DateTime.utc(2027, 3);

  for (final product in _copyProducts) {
    _portedTableSuite(product, now);
    _portedSignedSuite(product, now);
  }

  group('the licence-file environment variable', () {
    test('is <PRODUCT>_LICENSE_FILE for each product', () {
      const documented = <CruxProduct, String>{
        CruxProduct.waveCrux: 'WAVECRUX_LICENSE_FILE',
        CruxProduct.netCrux: 'NETCRUX_LICENSE_FILE',
        CruxProduct.lintCrux: 'LINTCRUX_LICENSE_FILE',
        CruxProduct.simCrux: 'SIMCRUX_LICENSE_FILE',
      };
      for (final product in CruxProduct.values) {
        expect(
          HeadlessLicenseTierResolver.licenseFileEnvVarFor(product),
          documented[product],
        );
        expect(
          HeadlessLicenseTierResolver(product: product).envVar,
          documented[product],
        );
      }
    });

    test('an explicit envVar replaces the default, and the default is not '
        'read', () async {
      final validator = _TableValidator({
        'MINE': LicenseAccepted(_grant(CruxProduct.waveCrux, LicenseTier.pro)),
      });
      final r = await HeadlessLicenseTierResolver(
        product: CruxProduct.waveCrux,
        envVar: 'CUSTOM_LICENSE',
        validator: validator,
        environment: const {
          'WAVECRUX_LICENSE_FILE': '/default.lic',
          'CUSTOM_LICENSE': '/mine.lic',
        },
        loadPolicy: _noPolicy,
        readFile: (path) async => path == '/mine.lic' ? 'MINE' : 'DEFAULT',
        clock: () => now,
      ).resolve();
      expect(r.tier, LicenseTier.pro);
      expect(validator.seen, <String>['MINE']);
      expect(r.notes.single, contains('(CUSTOM_LICENSE)'));
    });
  });

  group('source order', () {
    late _TableValidator validator;
    late List<String> read;

    HeadlessLicenseTierResolver resolver({
      Map<String, String> environment = const {},
      PolicyLoadResult Function()? loadPolicy,
    }) => HeadlessLicenseTierResolver(
      product: CruxProduct.netCrux,
      validator: validator,
      environment: environment,
      loadPolicy: loadPolicy ?? _noPolicy,
      readFile: (path) async {
        read.add(path);
        return switch (path) {
          '/flag.lic' => 'FLAG',
          '/env.lic' => 'ENV',
          '/share.lic' => 'SHARE',
          _ => throw FileSystemException('No such file', path),
        };
      },
      clock: () => now,
    );

    setUp(() {
      final pro = LicenseAccepted(_grant(CruxProduct.netCrux, LicenseTier.pro));
      validator = _TableValidator({
        'FLAG': LicenseAccepted(
          _grant(CruxProduct.netCrux, LicenseTier.enterprise),
        ),
        'ENV': LicenseAccepted(_grant(CruxProduct.netCrux, LicenseTier.edu)),
        'POLICY': pro,
        'SHARE': pro,
      });
      read = <String>[];
    });

    PolicyLoadResult inlinePolicy() =>
        _policy('{"schema":1,"suite":{"license":{"key":"POLICY"}}}');

    test('1: the flag, and nothing after it is read', () async {
      final r = await resolver(
        environment: const {'NETCRUX_LICENSE_FILE': '/env.lic'},
        loadPolicy: inlinePolicy,
      ).resolve(licenseFilePath: '/flag.lic');
      expect(r.tier, LicenseTier.enterprise);
      expect(read, <String>['/flag.lic']);
      expect(validator.seen, <String>['FLAG']);
    });

    test('2: the environment variable, when there is no flag', () async {
      final r = await resolver(
        environment: const {'NETCRUX_LICENSE_FILE': '/env.lic'},
        loadPolicy: inlinePolicy,
      ).resolve();
      expect(r.tier, LicenseTier.edu);
      expect(read, <String>['/env.lic']);
      expect(validator.seen, <String>['ENV']);
    });

    test('2: a blank flag and a blank variable count as absent', () async {
      final r = await resolver(
        environment: const {'NETCRUX_LICENSE_FILE': '   '},
        loadPolicy: inlinePolicy,
      ).resolve(licenseFilePath: '  ');
      expect(r.tier, LicenseTier.pro);
      expect(validator.seen, <String>['POLICY']);
    });

    test('3: the policy file, inline, when neither is given', () async {
      final r = await resolver(loadPolicy: inlinePolicy).resolve();
      expect(r.tier, LicenseTier.pro);
      expect(read, isEmpty);
      expect(validator.seen, <String>['POLICY']);
    });

    test('3: the policy file, as a path', () async {
      final r = await resolver(
        loadPolicy: () => _policy(
          '{"schema":1,"suite":{"license":{"file":"/share.lic"}}}',
        ),
      ).resolve();
      expect(r.tier, LicenseTier.pro);
      expect(read, <String>['/share.lic']);
    });

    test(
      'a failed explicit source does not fall through to the next',
      () async {
        await expectLater(
          () => resolver(
            environment: const {'NETCRUX_LICENSE_FILE': '/env.lic'},
            loadPolicy: inlinePolicy,
          ).resolve(licenseFilePath: '/missing.lic'),
          throwsA(isA<HeadlessLicenseException>()),
        );
        expect(validator.seen, isEmpty);
      },
    );

    test('a policy loader that throws is Open Core, silently', () async {
      final r = await resolver(
        loadPolicy: () => throw StateError('loader broke'),
      ).resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes, isEmpty);
    });
  });

  group('real files', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('headless_files_'));
    tearDown(() => dir.deleteSync(recursive: true));

    HeadlessLicenseTierResolver real() => HeadlessLicenseTierResolver(
      product: CruxProduct.waveCrux,
      environment: const {},
      loadPolicy: _noPolicy,
      clock: () => now,
    );

    test('a missing --license-file throws, naming the path', () {
      final missing = p.join(dir.path, 'absent.lic');
      expect(
        () => real().resolve(licenseFilePath: missing),
        throwsA(
          isA<HeadlessLicenseException>().having(
            (e) => e.message,
            'message',
            allOf(contains('cannot read'), contains(missing)),
          ),
        ),
      );
    });

    test('an unreadable --license-file (a directory) throws', () {
      expect(
        () => real().resolve(licenseFilePath: dir.path),
        throwsA(
          isA<HeadlessLicenseException>().having(
            (e) => e.message,
            'message',
            contains('cannot read'),
          ),
        ),
      );
    });

    test('an empty file throws, naming it empty', () {
      final empty = File(p.join(dir.path, 'empty.lic'))
        ..writeAsStringSync('\n \n');
      expect(
        () => real().resolve(licenseFilePath: empty.path),
        throwsA(
          isA<HeadlessLicenseException>().having(
            (e) => e.message,
            'message',
            contains('is empty'),
          ),
        ),
      );
    });

    test('a policy licence path that is a directory degrades to Open Core '
        'with a note', () async {
      final r = await HeadlessLicenseTierResolver(
        product: CruxProduct.waveCrux,
        environment: const {},
        loadPolicy: () => _policy(
          '{"schema":1,"suite":{"license":{"file":${_json(dir.path)}}}}',
        ),
        clock: () => now,
      ).resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('cannot read'));
      expect(r.notes.single, contains('running as Open Core'));
    });
  });

  group('signed credentials, real validator', () {
    late TestIssuerKeys keys;

    setUpAll(() async => keys = await TestIssuerKeys.fromSeed(7));

    HeadlessLicenseTierResolver resolver(
      CruxProduct product,
      String credential, {
      DateTime? at,
    }) => HeadlessLicenseTierResolver(
      product: product,
      validator: _validator(product, keys),
      environment: const {},
      loadPolicy: _noPolicy,
      readFile: (_) async => credential,
      clock: () => at ?? now,
    );

    test('a licence for another product is refused as not entitled', () async {
      final simOnly = await keys.mintFile(
        filePayload(
          entitlements: const ['SIMCRUX', 'TIER_ENTERPRISE'],
          expiry: '2099-01-01T00:00:00.000Z',
        ),
      );
      final r = await resolver(
        CruxProduct.lintCrux,
        simOnly,
      ).resolve(licenseFilePath: '/sim.lic');
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('productNotEntitled'));
      expect(r.notes.single, contains('running as Open Core'));

      // The same file is good where it is entitled.
      final ok = await resolver(
        CruxProduct.simCrux,
        simOnly,
      ).resolve(licenseFilePath: '/sim.lic');
      expect(ok.tier, LicenseTier.enterprise);
    });

    test('a licence signed by another key is refused as untrusted', () async {
      final stranger = await TestIssuerKeys.fromSeed(8);
      final forged = await stranger.mintFile(
        filePayload(
          entitlements: const ['WAVECRUX', 'TIER_ENTERPRISE'],
          expiry: '2099-01-01T00:00:00.000Z',
        ),
      );
      final r = await resolver(
        CruxProduct.waveCrux,
        forged,
      ).resolve(licenseFilePath: '/forged.lic');
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('untrustedIssuer'));
    });

    test('the production validator refuses a test-key licence', () async {
      // The fixture's default entitlements: WaveCrux at Pro.
      final file = await keys.mintFile(
        filePayload(expiry: '2099-01-01T00:00:00.000Z'),
      );
      final r = await HeadlessLicenseTierResolver(
        product: CruxProduct.waveCrux,
        environment: const {},
        loadPolicy: _noPolicy,
        readFile: (_) async => file,
        clock: () => now,
      ).resolve(licenseFilePath: '/test-key.lic');
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('untrustedIssuer'));
    });

    // Each tier's window, hand-derived: a licence expiring 2027-01-01T00:00Z
    // (the fixture payloads' default expiry, left implicit below)
    // keeps Pro until 2027-01-31T00:00Z (30 days), EDU until 2027-03-02
    // (60 days), Enterprise until 2027-04-01 (90 days); one second before the
    // end it is kept, at the end it is not.
    final windows = <String, (LicenseTier, DateTime)>{
      'TIER_PRO': (LicenseTier.pro, DateTime.utc(2027, 1, 31)),
      'TIER_EDU': (LicenseTier.edu, DateTime.utc(2027, 3, 2)),
      'TIER_ENTERPRISE': (LicenseTier.enterprise, DateTime.utc(2027, 4)),
    };
    for (final MapEntry(key: code, value: (tier, end)) in windows.entries) {
      test(
        '$code keeps its tier through its grace window and no longer',
        () async {
          final file = await keys.mintFile(
            filePayload(entitlements: <String>['NETCRUX', code]),
          );
          final inside = await resolver(
            CruxProduct.netCrux,
            file,
            at: end.subtract(const Duration(seconds: 1)),
          ).resolve(licenseFilePath: '/l.lic');
          expect(inside.tier, tier, reason: inside.notes.join('\n'));
          expect(inside.notes.single, contains('expired on 2027-01-01'));
          expect(
            inside.notes.single,
            contains('grace period ends on ${_day(end)}'),
          );

          final after = await resolver(
            CruxProduct.netCrux,
            file,
            at: end,
          ).resolve(licenseFilePath: '/l.lic');
          expect(after.tier, LicenseTier.openCore);
          expect(after.notes.single, contains('past its grace period'));
        },
      );
    }

    test('an expired evaluation gets no grace, as in the app', () async {
      // Expires 2027-01-01T00:00Z, the fixture payloads' default.
      final evaluation = await keys.mintFile(
        filePayload(
          entitlements: const ['WAVECRUX', 'TIER_ENTERPRISE', 'EVALUATION'],
        ),
      );
      final beforeExpiry = await resolver(
        CruxProduct.waveCrux,
        evaluation,
        at: DateTime.utc(2026, 12, 31, 23, 59, 59),
      ).resolve(licenseFilePath: '/eval.lic');
      expect(beforeExpiry.tier, LicenseTier.enterprise);

      final aDayAfter = await resolver(
        CruxProduct.waveCrux,
        evaluation,
        at: DateTime.utc(2027, 1, 2),
      ).resolve(licenseFilePath: '/eval.lic');
      expect(aDayAfter.tier, LicenseTier.openCore);
      expect(aDayAfter.notes.single, contains('evaluation'));
      expect(aDayAfter.notes.single, contains('no grace period'));
    });
  });

  group('the beta flag', () {
    HeadlessLicenseTierResolver resolver({required bool betaPeriod}) =>
        HeadlessLicenseTierResolver(
          product: CruxProduct.waveCrux,
          validator: _TableValidator(const {}),
          environment: const {},
          loadPolicy: _noPolicy,
          betaPeriod: betaPeriod,
        );

    test('defaults to kBetaPeriod, on the resolver and the resolution', () {
      expect(
        HeadlessLicenseTierResolver(product: CruxProduct.waveCrux).betaPeriod,
        kBetaPeriod,
      );
      expect(
        const HeadlessLicenseResolution(tier: LicenseTier.openCore).betaPeriod,
        kBetaPeriod,
      );
    });

    test('during the beta every tier is admitted at Open Core, and the tier '
        'reported is still Open Core', () async {
      final r = await resolver(betaPeriod: true).resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.betaPeriod, isTrue);
      for (final required in LicenseTier.values) {
        expect(r.admits(required), isTrue, reason: required.name);
      }
    });

    test('outside the beta Open Core admits only Open Core', () async {
      final r = await resolver(betaPeriod: false).resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.admits(LicenseTier.openCore), isTrue);
      expect(r.admits(LicenseTier.pro), isFalse);
      expect(r.admits(LicenseTier.enterprise), isFalse);
    });

    test('outside the beta EDU admits Pro and not Enterprise; Enterprise '
        'admits both', () {
      const edu = HeadlessLicenseResolution(
        tier: LicenseTier.edu,
        // Spelled out although it matches this build's default: a build
        // defining BETA_PERIOD=true must still check the tier order.
        // ignore: avoid_redundant_argument_values
        betaPeriod: false,
      );
      expect(edu.admits(LicenseTier.pro), isTrue);
      expect(edu.admits(LicenseTier.enterprise), isFalse);
      const ent = HeadlessLicenseResolution(
        tier: LicenseTier.enterprise,
        // As above: the tier order, whatever BETA_PERIOD this build has.
        // ignore: avoid_redundant_argument_values
        betaPeriod: false,
      );
      expect(ent.admits(LicenseTier.pro), isTrue);
      expect(ent.admits(LicenseTier.enterprise), isTrue);
    });
  });

  group(
    'the shared machine fingerprint for products without a legacy file',
    () {
      late Directory home;
      late Map<String, String> env;
      late TestIssuerKeys keys;

      setUpAll(() async => keys = await TestIssuerKeys.fromSeed(7));
      setUp(() {
        home = Directory.systemTemp.createTempSync('headless_fp_wave_');
        env = _homeEnv(home);
      });
      tearDown(() => home.deleteSync(recursive: true));

      test('WaveCrux adopts a fingerprint LintCrux kept, as the desktop store '
          'does, rather than minting a second identity', () async {
        _record(
          File(legacyInstallFingerprintPath('lintcrux', environment: env)),
          _boundFingerprint,
        );
        // The fixture's default entitlements: WaveCrux at Pro.
        final machine = await keys.mintMachineFile(
          machineFilePayload(
            fingerprint: _boundFingerprint,
            expiry: '2099-01-01T00:00:00.000Z',
          ),
        );
        final r = await HeadlessLicenseTierResolver(
          product: CruxProduct.waveCrux,
          validator: _validator(CruxProduct.waveCrux, keys),
          environment: env,
          loadPolicy: _noPolicy,
          readFile: (_) async => machine,
          clock: () => now,
        ).resolve(licenseFilePath: '/ci/machine.lic');
        expect(r.tier, LicenseTier.pro, reason: r.notes.join('\n'));
        expect(_sharedFile(env).readAsStringSync().trim(), _boundFingerprint);
      });

      test("a product's own legacy file is preferred over another's", () async {
        _record(
          File(legacyInstallFingerprintPath('lintcrux', environment: env)),
          'lintcrux-legacy-fp-0001',
        );
        _record(
          File(legacyInstallFingerprintPath('simcrux', environment: env)),
          'simcrux-legacy-fp-0001',
        );
        final read = HeadlessLicenseTierResolver.sharedInstallFingerprint(
          product: CruxProduct.simCrux,
          environment: env,
        );
        expect(await read(), 'simcrux-legacy-fp-0001');
        expect(
          _sharedFile(env).readAsStringSync().trim(),
          'simcrux-legacy-fp-0001',
        );
      });
    },
  );

  // Mutation proof (rule: decision code ships with a broken variant that the
  // oracle tests must catch). The oracle is the expiry decision against
  // hand-derived dates; the mutant keeps every expired tier.
  group('mutation proof: a resolver that keeps an expired tier fails', () {
    late TestIssuerKeys keys;

    setUpAll(() async => keys = await TestIssuerKeys.fromSeed(7));

    test('the oracle passes against the resolver', () async {
      final failures = await _expiryOracle(
        keys,
        now,
        (validator, credential, at) => HeadlessLicenseTierResolver(
          product: CruxProduct.lintCrux,
          validator: validator,
          environment: const {},
          loadPolicy: _noPolicy,
          readFile: (_) async => credential,
          clock: () => at,
        ),
      );
      expect(failures, isEmpty);
    });

    test('the oracle fails against the mutant', () async {
      final failures = await _expiryOracle(
        keys,
        now,
        (validator, credential, at) => _KeepsExpiredTier(
          validator: validator,
          readFile: (_) async => credential,
          clock: () => at,
        ),
      );
      expect(failures, hasLength(2), reason: failures.join('\n'));
    });
  });
}

/// The broken variant: an expired licence keeps its tier forever.
class _KeepsExpiredTier extends HeadlessLicenseTierResolver {
  _KeepsExpiredTier({
    required LicenseValidator super.validator,
    required super.readFile,
    required super.clock,
  }) : super(
         product: CruxProduct.lintCrux,
         environment: const {},
         loadPolicy: _noPolicy,
       );

  @override
  LicenseTier? tierAfterExpiry(LicenseGrant grant, DateTime now) => grant.tier;
}

/// Runs the expiry checks against the resolver [make] builds and returns a
/// line per check that failed. Two must-refuse cases: a paid Pro licence one
/// day past its 30-day window, and an evaluation one day past its expiry. One
/// must-keep case, so a resolver that refuses everything fails too.
Future<List<String>> _expiryOracle(
  TestIssuerKeys keys,
  DateTime now,
  HeadlessLicenseTierResolver Function(
    LicenseValidator validator,
    String credential,
    DateTime at,
  )
  make,
) async {
  final validator = _validator(CruxProduct.lintCrux, keys);
  // Both expire 2027-01-01T00:00Z, the fixture payloads' default.
  final paid = await keys.mintFile(
    filePayload(entitlements: const ['LINTCRUX', 'TIER_PRO']),
  );
  final evaluation = await keys.mintFile(
    filePayload(entitlements: const ['LINTCRUX', 'TIER_PRO', 'EVALUATION']),
  );
  final cases = <(String, String, DateTime, LicenseTier)>[
    ('paid Pro, day 31', paid, DateTime.utc(2027, 2), LicenseTier.openCore),
    (
      'evaluation, day 1',
      evaluation,
      DateTime.utc(2027, 1, 2),
      LicenseTier.openCore,
    ),
    ('paid Pro, day 29', paid, DateTime.utc(2027, 1, 30), LicenseTier.pro),
  ];
  final failures = <String>[];
  for (final (name, credential, at, expected) in cases) {
    final r = await make(
      validator,
      credential,
      at,
    ).resolve(licenseFilePath: '/oracle.lic');
    if (r.tier != expected) {
      failures.add('$name: expected ${expected.name}, got ${r.tier.name}');
    }
  }
  return failures;
}

/// The table suite each product copy carried, ported.
void _portedTableSuite(CruxProduct product, DateTime now) {
  final envVar = '${product.entitlementCode}_LICENSE_FILE';
  final pro = _grant(product, LicenseTier.pro);

  HeadlessLicenseTierResolver resolver({
    Map<String, LicenseValidation> outcomes = const {},
    Map<String, String> environment = const {},
    PolicyLoadResult Function()? loadPolicy,
    Map<String, String> files = const {},
  }) => HeadlessLicenseTierResolver(
    product: product,
    validator: _TableValidator(outcomes),
    environment: environment,
    loadPolicy: loadPolicy ?? _noPolicy,
    readFile: (path) async {
      final contents = files[path];
      if (contents == null) {
        throw FileSystemException('No such file', path);
      }
      return contents;
    },
    clock: () => now,
  );

  group('${product.displayName} copy, ported', () {
    test('no source anywhere is Open Core, with nothing to say', () async {
      final r = await resolver().resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes, isEmpty);
    });

    test('--license-file is validated and its tier used', () async {
      final r = await resolver(
        outcomes: {
          'ENT-CRED': LicenseAccepted(_grant(product, LicenseTier.enterprise)),
        },
        files: {'/ci/${product.slug}.lic': 'ENT-CRED\n'},
      ).resolve(licenseFilePath: '/ci/${product.slug}.lic');
      expect(r.tier, LicenseTier.enterprise);
      expect(r.notes.single, contains('Enterprise'));
      expect(r.notes.single, contains('/ci/${product.slug}.lic'));
    });

    test('the flag wins over the environment and the policy file', () async {
      final r = await resolver(
        outcomes: {
          'FLAG': LicenseAccepted(_grant(product, LicenseTier.enterprise)),
          'ENV': LicenseAccepted(pro),
        },
        environment: {envVar: '/env.lic'},
        files: {'/flag.lic': 'FLAG', '/env.lic': 'ENV'},
        loadPolicy: () =>
            _policy('{"schema":1,"suite":{"license":{"key":"POLICY"}}}'),
      ).resolve(licenseFilePath: '/flag.lic');
      expect(r.tier, LicenseTier.enterprise);
    });

    test('$envVar is used when no flag is given', () async {
      final r = await resolver(
        outcomes: {'ENV': LicenseAccepted(_grant(product, LicenseTier.edu))},
        environment: {envVar: '/env.lic'},
        files: {'/env.lic': 'ENV'},
      ).resolve();
      expect(r.tier, LicenseTier.edu);
      expect(r.notes.single, contains('($envVar)'));
    });

    test('an inline policy license is used last', () async {
      final r = await resolver(
        outcomes: {'POLICY': LicenseAccepted(pro)},
        loadPolicy: () =>
            _policy('{"schema":1,"suite":{"license":{"key":"POLICY"}}}'),
      ).resolve();
      expect(r.tier, LicenseTier.pro);
      expect(r.notes.single, contains('policy file'));
    });

    test('a policy license file is read from its path', () async {
      final r = await resolver(
        outcomes: {'SHARED': LicenseAccepted(pro)},
        files: {'/share/crux.lic': 'SHARED'},
        loadPolicy: () => _policy(
          '{"schema":1,"suite":{"license":{"file":"/share/crux.lic"}}}',
        ),
      ).resolve();
      expect(r.tier, LicenseTier.pro);
    });

    test('an unreadable policy license file degrades to Open Core with a '
        'note', () async {
      final r = await resolver(
        loadPolicy: () => _policy(
          '{"schema":1,"suite":{"license":{"file":"/offline/crux.lic"}}}',
        ),
      ).resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('cannot read'));
    });

    test('an unreadable --license-file throws', () async {
      expect(
        () => resolver().resolve(licenseFilePath: '/missing.lic'),
        throwsA(
          isA<HeadlessLicenseException>().having(
            (e) => e.message,
            'message',
            contains('/missing.lic'),
          ),
        ),
      );
    });

    test('an unreadable $envVar throws', () async {
      expect(
        () => resolver(environment: {envVar: '/gone.lic'}).resolve(),
        throwsA(isA<HeadlessLicenseException>()),
      );
    });

    test('an empty --license-file throws', () async {
      expect(
        () => resolver(
          files: {'/empty.lic': '  \n'},
        ).resolve(licenseFilePath: '/empty.lic'),
        throwsA(isA<HeadlessLicenseException>()),
      );
    });

    test('a rejected credential runs as Open Core and says why', () async {
      final r = await resolver(
        files: {'/bad.lic': 'TAMPERED'},
        outcomes: {
          'TAMPERED': const LicenseRejected(
            LicenseRejection.untrustedIssuer,
            'no trusted issuer',
          ),
        },
      ).resolve(licenseFilePath: '/bad.lic');
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('untrustedIssuer'));
      expect(r.notes.single, contains('Open Core'));
    });

    // LintCrux's copy used Enterprise here, SimCrux's Pro: both run.
    for (final tier in <LicenseTier>[LicenseTier.enterprise, LicenseTier.pro]) {
      test('an expired ${tier.name} license keeps its tier inside the grace '
          'period', () async {
        final r = await resolver(
          files: {'/l.lic': 'EXPIRED'},
          outcomes: {
            'EXPIRED': LicenseExpired(
              _grant(
                product,
                tier,
                expiry: now.subtract(const Duration(days: 5)),
              ),
            ),
          },
        ).resolve(licenseFilePath: '/l.lic');
        expect(r.tier, tier);
        expect(r.notes.single, contains('grace period ends'));
      });
    }

    // LintCrux's copy expired the licence 120 days back, SimCrux's 90: both
    // are past Pro's 30.
    for (final days in <int>[120, 90]) {
      test('an expired license $days days past expiry is Open Core', () async {
        final r = await resolver(
          files: {'/l.lic': 'EXPIRED'},
          outcomes: {
            'EXPIRED': LicenseExpired(
              _grant(
                product,
                LicenseTier.pro,
                expiry: now.subtract(Duration(days: days)),
              ),
            ),
          },
        ).resolve(licenseFilePath: '/l.lic');
        expect(r.tier, LicenseTier.openCore);
        expect(r.notes.single, contains('past its grace period'));
      });
    }

    test('a refused policy file is reported and ignored', () async {
      final r = await resolver(
        loadPolicy: () => const PolicyLoadResult(
          document: PolicyDocument.absent,
          rejection: PolicyRejection.badSignature,
          sourcePath: '/etc/edacrux/.crux-policy.json',
          detail: 'signature does not verify',
        ),
      ).resolve();
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('badSignature'));
    });

    // From LintCrux's copy only.
    test('a license for another product is not entitled here', () async {
      final r = await resolver(
        files: {'/other.lic': 'OTHER-ONLY'},
        outcomes: {
          'OTHER-ONLY': const LicenseRejected(
            LicenseRejection.productNotEntitled,
            'grant covers another product',
          ),
        },
      ).resolve(licenseFilePath: '/other.lic');
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('productNotEntitled'));
    });

    test(
      'garbage from --license-file is rejected by the real validator',
      () async {
        final r = await HeadlessLicenseTierResolver(
          product: product,
          environment: const {},
          loadPolicy: _noPolicy,
          readFile: (_) async => 'not a license at all',
        ).resolve(licenseFilePath: '/garbage.lic');
        expect(r.tier, LicenseTier.openCore);
        expect(r.notes.single, contains('malformed'));
      },
    );
  });
}

/// The signed machine-file suite each product copy carried, ported. The
/// copies committed credentials minted from seed 7; these are minted from the
/// same seed at run time, for each product.
void _portedSignedSuite(CruxProduct product, DateTime now) {
  group('${product.displayName} copy, ported: a signed machine file, '
      'resolved headless', () {
    late Directory home;
    late Map<String, String> env;
    late TestIssuerKeys keys;
    late String machineFile;
    late String licenseFile;

    setUpAll(() async {
      keys = await TestIssuerKeys.fromSeed(7);
      final codes = <String>[product.entitlementCode, 'TIER_PRO'];
      machineFile = await keys.mintMachineFile(
        machineFilePayload(
          fingerprint: _boundFingerprint,
          entitlements: codes,
          expiry: '2099-01-01T00:00:00.000Z',
        ),
      );
      licenseFile = await keys.mintFile(
        filePayload(entitlements: codes, expiry: '2099-01-01T00:00:00.000Z'),
      );
    });

    setUp(() {
      home = Directory.systemTemp.createTempSync('headless_fp_');
      env = _homeEnv(home);
    });
    tearDown(() => home.deleteSync(recursive: true));

    File legacyFile() =>
        File(legacyInstallFingerprintPath(product.slug, environment: env));

    HeadlessLicenseTierResolver signed(
      String credential, {
      Map<String, String>? environment,
    }) => HeadlessLicenseTierResolver(
      product: product,
      validator: _validator(product, keys),
      environment: environment ?? env,
      loadPolicy: _noPolicy,
      readFile: (_) async => credential,
      clock: () => now,
    );

    test(
      'resolves to its tier on the machine whose shared fingerprint it names',
      () async {
        _record(_sharedFile(env), _boundFingerprint);
        final r = await signed(
          machineFile,
        ).resolve(licenseFilePath: '/ci/machine.lic');
        expect(r.tier, LicenseTier.pro, reason: r.notes.join('\n'));
        expect(r.notes.single, contains('Pro from license file'));
      },
    );

    test(
      'resolves for the fingerprint an earlier release kept in the legacy '
      'file, which is adopted into the shared file when there is none yet',
      () async {
        _record(legacyFile(), _boundFingerprint);
        expect(_sharedFile(env).existsSync(), isFalse);

        final r = await signed(
          machineFile,
        ).resolve(licenseFilePath: '/ci/machine.lic');

        expect(r.tier, LicenseTier.pro, reason: r.notes.join('\n'));
        expect(_sharedFile(env).readAsStringSync().trim(), _boundFingerprint);
        // Left in place for a downgrade.
        expect(legacyFile().readAsStringSync().trim(), _boundFingerprint);
      },
    );

    test('the shared fingerprint wins over the legacy file', () async {
      _record(_sharedFile(env), 'another-machine-fp-0002');
      _record(legacyFile(), _boundFingerprint);

      final r = await signed(
        machineFile,
      ).resolve(licenseFilePath: '/ci/machine.lic');

      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('wrongMachine'));
    });

    test('is refused on a machine with another fingerprint', () async {
      _record(_sharedFile(env), 'another-install-fp-0002');
      final r = await signed(
        machineFile,
      ).resolve(licenseFilePath: '/ci/machine.lic');
      expect(r.tier, LicenseTier.openCore);
      expect(r.notes.single, contains('wrongMachine'));
      expect(r.notes.single, contains('another machine'));
    });

    test(
      'is refused where this machine has no fingerprint and none can be '
      'recorded',
      () async {
        // No home variable at all: there is nowhere to read one from or mint
        // one into.
        final r = await signed(
          machineFile,
          environment: const <String, String>{},
        ).resolve(licenseFilePath: '/ci/machine.lic');
        expect(r.tier, LicenseTier.openCore);
        expect(r.notes.single, contains('wrongMachine'));
      },
    );

    test('mints this machine a fingerprint into the shared file on first use '
        'and keeps it, so a build agent with neither file has an identity to '
        'issue a machine file for', () async {
      expect(_sharedFile(env).existsSync(), isFalse);
      expect(legacyFile().existsSync(), isFalse);
      await signed(machineFile).resolve(licenseFilePath: '/ci/machine.lic');
      final minted = _sharedFile(env).readAsStringSync().trim();
      expect(minted, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));

      await signed(machineFile).resolve(licenseFilePath: '/ci/machine.lic');
      expect(_sharedFile(env).readAsStringSync().trim(), minted);
      expect(legacyFile().existsSync(), isFalse);
    });

    test('a licence file names no machine: it resolves without a fingerprint, '
        'and creates none', () async {
      final r = await signed(
        licenseFile,
      ).resolve(licenseFilePath: '/ci/license.lic');
      expect(r.tier, LicenseTier.pro, reason: r.notes.join('\n'));
      expect(_sharedFile(env).existsSync(), isFalse);
    });
  });
}

LicenseGrant _grant(
  CruxProduct product,
  LicenseTier tier, {
  DateTime? expiry,
}) => LicenseGrant(
  issuerId: 'test',
  tier: tier,
  products: {product},
  expiry: expiry,
);

/// A validator for [product] that trusts only the throwaway issuer [keys].
CruxLicenseValidator _validator(CruxProduct product, TestIssuerKeys keys) =>
    CruxLicenseValidator(
      product: product,
      issuers: <LicenseIssuer>[
        KeygenLicenseIssuer(
          accountId: testAccountId,
          verifyKey: keys.verifyKey,
          policies: testPolicies,
        ),
      ],
    );

/// Every platform's home variable pointed at [home], so the shared and the
/// legacy fingerprint files resolve under it whichever OS runs the test.
Map<String, String> _homeEnv(Directory home) => <String, String>{
  'HOME': home.path,
  'APPDATA': home.path,
  'LOCALAPPDATA': home.path,
  'XDG_DATA_HOME': home.path,
};

File _sharedFile(Map<String, String> env) => File(
  p.join(cruxLicenseDirectory(environment: env), 'install.fingerprint'),
);

void _record(File file, String value) {
  file
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('$value\n');
}

String _day(DateTime at) => at.toUtc().toIso8601String().substring(0, 10);

String _json(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
