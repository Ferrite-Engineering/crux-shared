// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Guards the property that makes `crux-shared` open-sourceable.
///
/// A suite-wide audit set out to find Pro-tier capability sitting in the shared
/// packages and found none: every tier-sensitive thing here is a **seam**, not
/// an implementation. `crux_projects` ships `NoopProjectRegistry`. Nothing here
/// would leak a paid capability on the open-core flip.
///
/// That property held **by discipline alone** — `crux_shared_hygiene_test` in
/// each product checks build hygiene (that `analysis_options.yaml` excludes
/// the submodule, that the codegen CI step matches the pubspec), not purity.
/// This is the missing half. It exists so the open-sourcing decision is
/// auditable rather than re-reviewed by hand every time.
///
/// ## The licence validator, and why this guard changed shape
///
/// This file used to assert that `NoopLicenseValidator` was the *only*
/// `LicenseValidator` in the repo, on the reasoning that "a concrete validator
/// in an open repo is not a validator: its source sits beside the key material
/// it checks". Building the licensing system proved that premise false:
/// **there is no key material here to sit beside.** Keygen generates and
/// retains the Ed25519 signing key and it never leaves them; a build carries an
/// account id and a *public* verify key, neither of which is a secret. So the
/// cryptographic validator lives in `crux_license`, Apache 2.0 at the
/// open-core flip.
///
/// So the property worth guarding is not "no validator" — it is **verify,
/// never sign**: no code a product build can reach may be able to make a
/// signature. That is what the first test asserts, and it is a boundary that
/// would actually matter if it were crossed.
///
/// ## What is scanned, and the one signer that is exempt
///
/// `lib/`, `bin/` and `tool/` of every package. `lib/` is what a product
/// compiles; `bin/` is what `dart pub global activate` installs; `tool/` is
/// reachable from `bin/`. The scan used to cover `lib/` alone, and the
/// docstring above it claimed the repository could never sign — while
/// `crux_policy/tool/policy_signer.dart`, a complete Ed25519 signer with
/// keypair derivation, sat one directory over. The placement was right; the
/// claim was not. The claim is now the narrower, true one, and the scan reaches
/// the file.
///
/// That signer, and the one `bin/` entry point that calls it, are the
/// exemptions, named in [_exemptSigners] with their reasons, and an exemption
/// cannot go stale: a test below fails if an exempt file stops matching the
/// signing shapes, because then the entry is excusing nothing and would
/// excuse the next signer added at that path.
///
/// `test/` is out of scope by design. Nothing under it is in any build, and
/// `crux_license/test/support/ed25519_sign.dart` is a signer for exactly that
/// reason — it mints throwaway fixtures with a throwaway seed so that no byte
/// signed by the production key is ever committed.
///
/// ## The Pro-feature vocabulary
///
/// The last test names the features the four products' pricing pages sell at
/// Pro or Enterprise and fails on a public type here that carries one of those
/// names — unless the type is a listed **seam**: the interface, the no-op
/// default, or the mechanism the paid inputs flow through. Every seam is named
/// with its noun, and a seam that stops existing fails the run, so the list
/// records what is here rather than rotting into a standing hole.
///
/// The list is reconciled against the live pricing pages, not against one
/// audit's findings. It would have failed on the persistent project registry
/// that `docs/adr/0005-pro-implementations-leave-crux-shared.md` moved out —
/// the drift ADR 0002 said no guard could see.
///
/// ## What this can and cannot catch
///
/// It is a lexical guard, so it catches the *shapes* a leak takes — a signing
/// capability, a tier comparison that gates behaviour, a Pro feature name in a
/// public symbol. It cannot catch a genuinely novel leak that avoids all three.
/// When it fires, the question to ask is not "how do I silence this" but "is
/// this code the paid capability itself, rather than a seam" — see
/// `docs/adr/0002-pro-only-consumers-of-shared-packages.md` and ADR 0005 at
/// the repo root: tier is a property of the consumer, not of the code, and
/// code that *is* the paid capability belongs with the Pro overlays, not here.
void main() {
  final root = _workspaceRoot();

  test('the workspace layout resolved', () {
    expect(_scannedFiles(root).length, greaterThan(40));
    expect(
      _scannedFiles(root).where((e) => e.kind != 'lib'),
      isNotEmpty,
      reason: 'the scan is not reaching any bin/ or tool/ directory',
    );
  });

  test('no code a product build can reach is able to sign', () {
    // Verification needs a public key; signing needs a private one. Shared
    // code that could sign would mean a licence-minting capability sitting in
    // the repo we intend to open — and, unlike the validator, that really
    // would be indefensible. Every shape below is a way to hold or derive a
    // private key, or to use one.
    final offenders = <String>[];
    for (final entry in _scannedFiles(root)) {
      final relative = p.relative(entry.file.path, from: root);
      if (_exemptSigners.containsKey(_posix(relative))) continue;
      final code = _stripComments(entry.file.readAsStringSync());
      for (final probe in _signingShapes.entries) {
        if (probe.key.hasMatch(code)) {
          offenders.add('$relative — ${probe.value}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Code a product build can reach acquired the ability to SIGN, not '
          'just verify. The licence signing key is held by Keygen and nothing '
          'in this repo should be able to mint a licence; an organization '
          'signs its own policy file with its own key, and that signer ships '
          'in no product.\n${offenders.join('\n')}',
    );
  });

  test('each exempt signer is still a signer, so no exemption is stale', () {
    for (final entry in _exemptSigners.entries) {
      final file = File(p.join(root, entry.key));
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '${entry.key} is exempt from the signing scan but no longer '
            'exists. Drop the entry: a stale exemption excuses the next '
            'signer that lands at that path.',
      );
      final code = _stripComments(file.readAsStringSync());
      expect(
        _signingShapes.keys.any((shape) => shape.hasMatch(code)),
        isTrue,
        reason:
            '${entry.key} is exempt from the signing scan but matches none of '
            'its shapes. Either the file stopped signing (drop the entry) or '
            'the shapes rotted (fix them) — in both cases the scan is '
            'currently proving nothing about this file.',
      );
    }
  });

  test('the validator is configured with public keys only', () {
    // The compiled-in constants are the account id and the verify key, and
    // the plan says in as many words that neither is a secret. Naming them
    // here keeps the previous test from being vacuous: crux_license really
    // does hold key material, and it is really only the public half.
    final issuer = File(
      p.join(
        root,
        'packages',
        'crux_license',
        'lib',
        'src',
        'keygen_issuer.dart',
      ),
    );
    expect(issuer.existsSync(), isTrue);
    final code = issuer.readAsStringSync();
    expect(code, contains('kKeygenVerifyKeyHex'));
    expect(
      code,
      isNot(contains('kKeygenSigningKey')),
      reason: "the private half is Keygen's and never ships",
    );
  });

  test('no shared package gates behaviour on a paid tier', () {
    // The seam pattern is: define the tier vocabulary, default to openCore,
    // let the overlay override. A shared package that *branches* on pro or
    // enterprise has stopped being a seam and started being the feature.
    //
    // Comparisons against `openCore` are fine — that is the default arm.
    final offenders = <String>[];
    final gate = RegExp(
      r'LicenseTier\.(pro|enterprise|edu)\s*(?:==|!=|<=|>=|<|>)|'
      r'(?:==|!=|<=|>=|<|>)\s*LicenseTier\.(pro|enterprise|edu)',
    );
    for (final entry in _scannedFiles(root)) {
      if (entry.package == 'crux_license') continue; // owns the vocabulary
      final code = _stripComments(entry.file.readAsStringSync());
      if (gate.hasMatch(code)) {
        offenders.add(p.relative(entry.file.path, from: root));
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A shared package outside crux_license branches on a paid tier. '
          'Shared code should take a seam (a provider, a builder, a nullable '
          'callback) and let the Pro overlay decide.\n'
          '${offenders.join('\n')}',
    );
  });

  test('no Pro feature vocabulary appears in a shared public symbol', () {
    final declared = _publicTypeNames(root);
    final offenders = <String>[];
    for (final decl in declared) {
      final lower = decl.name.toLowerCase();
      for (final noun in _proFeatureNouns.entries) {
        if (!lower.contains(noun.key.toLowerCase())) continue;
        if (noun.value.contains(decl.name)) continue;
        offenders.add(
          '${p.relative(decl.file.path, from: root)} — ${decl.name} '
          '(matches "${noun.key}")',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A shared package declares a public type named for a Pro or '
          'Enterprise feature. If it is the interface, the no-op default or '
          'the mechanism the paid inputs flow through, list it as a seam '
          'beside its noun with the reason. If it is the feature, it belongs '
          'with the Pro overlays — see '
          'docs/adr/0005-pro-implementations-leave-crux-shared.md.\n'
          '${offenders.join('\n')}',
    );
  });

  test('every listed seam still exists and still carries its noun', () {
    // A seam that stops existing would leave an entry excusing a type that is
    // not there, which is the first step to excusing one that is. And a seam
    // listed under a noun it does not carry is a typo that excuses nothing.
    final declared = _publicTypeNames(root).map((d) => d.name).toSet();
    final problems = <String>[];
    for (final noun in _proFeatureNouns.entries) {
      for (final seam in noun.value) {
        if (!declared.contains(seam)) {
          problems.add('$seam (listed under "${noun.key}") is not declared');
        } else if (!seam.toLowerCase().contains(noun.key.toLowerCase())) {
          problems.add('$seam does not carry "${noun.key}"');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the guard is not vacuous', () {
    // Each assertion above passes trivially if the scan finds nothing. Prove
    // the corpus really is being read and really does contain the seam types
    // the first tests reason about.
    final all = _scannedFiles(
      root,
    ).map((e) => _stripComments(e.file.readAsStringSync())).join('\n');
    expect(
      all,
      contains('NoopLicenseValidator'),
      reason: 'the scan is not reaching crux_license',
    );
    expect(
      all,
      contains('LicenseTier'),
      reason: 'the scan is not reaching the tier vocabulary',
    );
    expect(
      all,
      contains('signPolicyDocument'),
      reason: 'the scan is not reaching crux_policy/bin',
    );
  });
}

/// Every way code can hold, derive or use a private key.
///
/// The first five are `package:cryptography`'s shapes. The last three are what
/// a signer written by hand from RFC 8032 looks like: it declares a keypair
/// type, names a private seed or key, and has a `sign` that returns bytes.
/// The policy signer matched none of the first five, which is how it went
/// unseen even where the scan did reach.
final Map<RegExp, String> _signingShapes = <RegExp, String>{
  RegExp(r'\bnewKeyPair\w*\s*\('): 'generates a keypair',
  RegExp(r'\bSimpleKeyPairData\b'): 'holds private key bytes',
  RegExp(r'\bextractPrivateKeyBytes\b'): 'extracts a private key',
  RegExp(r'\bkeyPair\s*:'): 'passes a keypair to an algorithm',
  RegExp('BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY'): 'embeds a private key',
  RegExp(r'\bclass\s+\w*KeyPair\b'): 'declares a keypair type',
  RegExp(r'\bprivate(?:Seed|Key)\b'): 'names a private key or seed',
  RegExp(r'\b(?:List<int>|Uint8List)\s+sign\s*\('): 'signs bytes',
};

/// Files the signing scan does not apply to, with the reason each one is
/// allowed to sign. Two entries — the signer and the one CLI that calls it —
/// and each is held to still being a signer.
const Map<String, String> _exemptSigners = <String, String>{
  'packages/crux_policy/tool/policy_signer.dart':
      "the `crux-policy sign` subcommand's signer. It signs an organization's "
      "policy file with the organization's own key, supplied on the command "
      'line. Reachable only from bin/, not exported from the package barrel '
      "every product imports, and each product's export-control guard "
      'resolves its real dependency closure and would fail if it reached a '
      'build.',
  'packages/crux_policy/bin/crux_policy.dart':
      'the `crux-policy` CLI, whose `sign` subcommand hands the seed from the '
      'command line to the signer above. Same reasoning, same boundary: a '
      'bin/ entry point is installed by `dart pub global activate`, never '
      'compiled into a product.',
};

/// Features the four products' pricing pages sell at Pro or Enterprise, as
/// the fragment a public type name would carry, each with the seams here that
/// legitimately carry it. Grouped by the page that sells them.
///
/// Absent on purpose: nouns too generic to be a signal (`session` is an app
/// session throughout the suite, `policy` is the open policy mechanism, `cdc`
/// is free in one product and paid in another), and features no page sells —
/// nothing here is sold as single sign-on, for instance.
const Map<String, Set<String>> _proFeatureNouns = <String, Set<String>>{
  // WaveCrux — Pro: decoder packs, Debug Advisor, SVA, the agentic assistant.
  'debugAdvisor': <String>{},
  'svaVisual': <String>{},
  'waveformAssistant': <String>{},
  'translatorPack': <String>{},
  'widgetPack': <String>{},
  'isaPack': <String>{},
  'pseudoInstruction': <String>{},
  // WaveCrux — Enterprise: collaborative live sessions and what rides on them.
  'collab': <String>{},
  'presenter': <String>{},
  'reviewMinutes': <String>{},
  'sharedAnnotation': <String>{},
  'rgmii': <String>{},
  'pcap': <String>{},
  'sessionTemplate': <String>{},
  // NetCrux — Pro and Enterprise.
  'coneOfInfluence': <String>{},
  'crossProbeOriginate': <String>{},
  'structuralDiff': <String>{},
  'resetDomain': <String>{},
  'sourceAnnotation': <String>{},
  'fsmDetection': <String>{},
  'switchingHeatmap': <String>{},
  'symbolLibrary': <String>{},
  'sourceServer': <String>{},
  // LintCrux — Pro: waivers, trends, custom rules, auto-fix, CDC clock trees,
  // and the persistent multi-project registry with its navigation layer.
  'waiver': <String>{},
  'baseline': <String>{},
  'trendStore': <String>{},
  'customRule': <String>{},
  'autoFix': <String>{},
  'clockTree': <String>{},
  // The registry is the paid capability and left (ADR 0005). The interface
  // and the open-core default are the seam it plugs into.
  'projectRegistry': <String>{'ProjectRegistry', 'NoopProjectRegistry'},
  // The switcher and the recents panel render whatever the registry holds —
  // a mechanism whose paid input is the registry (ADR 0005, the heatmap case).
  'projectSwitcher': <String>{'CruxProjectSwitcherDialog'},
  'recentProjects': <String>{'CruxRecentProjectsPanel'},
  // The host-supplied opener callback; the search itself is the overlay's.
  'crossProjectSearch': <String>{'CruxCrossProjectSearchOpener'},
  // LintCrux — Enterprise.
  'teamDatabase': <String>{},
  'orgRollup': <String>{},
  'sharedWaiver': <String>{},
  // SimCrux — Pro and Enterprise.
  'flaky': <String>{},
  'seedSweep': <String>{},
  'retryPolicy': <String>{},
  'parameterization': <String>{},
  'prAnnotation': <String>{},
  'runComparison': <String>{},
  'driverPlugin': <String>{},
  'customDriver': <String>{},
  'distributedExecution': <String>{},
  'retentionPolicy': <String>{},
  'teamDashboard': <String>{},
  'testPlan': <String>{},
  // Suite-wide Enterprise, sold on all four pages.
  //
  // The audit log: the envelope, the sink seam, the no-op default and the
  // append-only JSONL sink are the mechanism; the sink is Noop until an
  // organization's policy file names a path, and the event kinds are each
  // product's own. `CruxAuditRecorder` stamps the envelope;
  // `CruxSharedAuditKinds` names the three kinds that describe shared
  // machinery.
  'audit': <String>{
    'AuditEvent',
    'AuditSeverity',
    'AuditSink',
    'AuditSinkHealth',
    'AuditVerbosity',
    'JsonlAuditSink',
    'NoopAuditSink',
    'CruxAuditRecorder',
    'CruxSharedAuditKinds',
  },
  // Policy locks: the resolver is the open mechanism and the signed policy
  // file is the paid input; the note is what a locked setting renders.
  'policyLock': <String>{'CruxPolicyLockNote'},
  'airgap': <String>{},
  'offlineActivation': <String>{},
  'managedUpdate': <String>{},
  'seatBased': <String>{},
};

/// The directories of a package a product build can reach, and what each
/// one is in the failure text.
const List<String> _scannedDirs = <String>['lib', 'bin', 'tool'];

String _workspaceRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: crux_shared_workspace')) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate the crux-shared workspace root from '
    '${Directory.current.path}',
  );
}

String _posix(String path) => path.replaceAll(r'\', '/');

List<({String package, String kind, File file})> _scannedFiles(String root) {
  final out = <({String package, String kind, File file})>[];
  final packages = Directory(p.join(root, 'packages'));
  for (final entry in packages.listSync()) {
    if (entry is! Directory) continue;
    final package = p.basename(entry.path);
    for (final kind in _scannedDirs) {
      final dir = Directory(p.join(entry.path, kind));
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart')) {
          continue;
        }
        if (p
            .split(p.relative(f.path, from: dir.path))
            .contains('.dart_tool')) {
          continue;
        }
        out.add((package: package, kind: kind, file: f));
      }
    }
  }
  out.sort((a, b) => a.file.path.compareTo(b.file.path));
  return out;
}

/// Every public type declared under a package's `lib/`, with the file that
/// declares it. Public declarations only: a private helper named `_baseline`
/// inside a chart widget is not a capability leak.
List<({String name, File file})> _publicTypeNames(String root) {
  final out = <({String name, File file})>[];
  final decl = RegExp(
    r'^\s*(?:abstract\s+|final\s+|sealed\s+|base\s+|interface\s+|mixin\s+)*'
    r'(?:class|enum|mixin|extension|typedef)\s+([A-Z]\w+)',
    multiLine: true,
  );
  for (final entry in _scannedFiles(root)) {
    if (entry.kind != 'lib') continue;
    final code = _stripComments(entry.file.readAsStringSync());
    for (final m in decl.allMatches(code)) {
      out.add((name: m.group(1)!, file: entry.file));
    }
  }
  return out;
}

/// Blanks comments to spaces, preserving newlines so line numbers survive.
/// String literals are left intact — a leaked capability name baked into a
/// string is still a leak.
String _stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final nl = source.indexOf('\n', i);
      final end = nl == -1 ? source.length : nl;
      for (var k = i; k < end; k++) {
        out.write(' ');
      }
      i = end;
    } else if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final close = source.indexOf('*/', i + 2);
      final end = close == -1 ? source.length : close + 2;
      for (var k = i; k < end; k++) {
        out.write(source[k] == '\n' ? '\n' : ' ');
      }
      i = end;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
