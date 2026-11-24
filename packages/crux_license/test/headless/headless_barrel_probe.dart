// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Headless probe for the Flutter-free `crux_license_headless.dart` barrel.
//
// NOT a test file (no `_test.dart` suffix, so `flutter test` ignores it). A
// plain Dart entry point that `test/headless_license_tier_closure_test.dart`
// runs on the standalone Dart VM, which has no `dart:ui`: if Flutter reaches
// the resolver's import closure (through `crux_license` or `crux_policy`),
// this program fails to load, as a product's `dart build cli` would.
//
// It resolves for real: the licence-file environment variable names this
// very file, which the real file reader reads and the production validator
// refuses as malformed, so the default reader, validator and beta flag are
// all exercised. The policy loader is the one injected collaborator, so the
// probe never depends on a policy file on the machine that runs it.
import 'dart:io';

import 'package:crux_license/crux_license_core.dart';
import 'package:crux_license/crux_license_headless.dart';
import 'package:crux_policy/crux_policy.dart';

Future<void> main(List<String> args) async {
  final self = args.single;
  final resolver = HeadlessLicenseTierResolver(
    product: CruxProduct.waveCrux,
    environment: <String, String>{
      HeadlessLicenseTierResolver.licenseFileEnvVarFor(CruxProduct.waveCrux):
          self,
    },
    loadPolicy: () => const PolicyLoadResult(document: PolicyDocument.absent),
  );
  final resolution = await resolver.resolve();
  final malformed = resolution.notes.any((n) => n.contains('malformed'));
  stdout.writeln(
    <String>[
      'env=${resolver.envVar}',
      'tier=${resolution.tier.name}',
      'malformed=$malformed',
      'beta=$kBetaPeriod',
      'admits=${resolution.admits(LicenseTier.pro)}',
    ].join(' '),
  );
}
