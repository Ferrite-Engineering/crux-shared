// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The Riverpod bindings that turn a policy file into behaviour.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('crux_binding_'));
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer containerFor(Map<String, Object?> policy) {
    final container = ProviderContainer(
      overrides: [
        cruxPolicyProvider.overrideWithValue(
          PolicyLoadResult(
            document: PolicyDocument.parse(jsonEncode(policy)),
          ),
        ),
        // What a Pro overlay spreads. Without it the managed-licence binding is
        // its default `false`, which is correct: open core is never governed by
        // one, and the binding only exists once a product asks for it.
        ...cruxPolicyOverrides(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the production loader has a key source — the guard', () {
    // The audit finding, in one line: `Provider((ref) => const
    // PolicyLoader().load())` with `trustedPublicKey` never bound, in every
    // product, so a signed file was refused on every machine. The fix reads
    // the key from beside the well-known policy path, which makes the DEFAULT
    // construction the production configuration — and this pins that the
    // binding still IS the default construction. A `trustedPublicKey:` here
    // would ship a key Ferrite chose; a `publicKeyPath:` or `wellKnownPath:`
    // would point every product somewhere other than the administrator-only
    // directory; an `environment:` would blind it to CRUX_POLICY.
    test('binds no key in code', () {
      expect(cruxPolicyLoader.trustedPublicKey, isNull);
    });

    test('reads the key from beside the well-known policy path', () {
      expect(cruxPolicyLoader.publicKeyPath, isNull);
      expect(cruxPolicyLoader.wellKnownPath, isNull);
      expect(cruxPolicyLoader.environment, isNull);
      expect(
        cruxPolicyLoader.effectivePublicKeyPath,
        PolicyLoader.defaultPublicKeyPath(),
      );
      expect(
        p.dirname(cruxPolicyLoader.effectivePublicKeyPath),
        p.dirname(PolicyLoader.defaultWellKnownPath()),
        reason: 'the key lives beside the policy, in the admin-only directory',
      );
      expect(
        p.basename(cruxPolicyLoader.effectivePublicKeyPath),
        kPolicyPublicKeyFileName,
      );
    });

    test('the provider runs that loader and nothing else', () {
      // Read through a real container, against this machine's real
      // well-known path. What it finds there is the machine's business and is
      // not asserted; that the provider's answer is the named loader's answer
      // — same discovery, same key status, same verdict — is.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final viaProvider = c.read(cruxPolicyProvider);
      final direct = cruxPolicyLoader.load();
      expect(viaProvider.discovery, direct.discovery);
      expect(viaProvider.keyStatus, direct.keyStatus);
      expect(viaProvider.rejection, direct.rejection);
      expect(viaProvider.signed, direct.signed);
      expect(viaProvider.sourcePath, direct.sourcePath);
    });
  });

  group('the audit sink is off until an administrator turns it on', () {
    test('no policy at all', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(cruxAuditSinkProvider), isA<NoopAuditSink>());
    });

    test('a policy with no audit key', () {
      final c = containerFor({'schema': 1, 'suite': <String, Object?>{}});
      expect(c.read(cruxAuditSinkProvider), isA<NoopAuditSink>());
    });

    test('an audit key with no path — we invent no location', () {
      final c = containerFor({
        'schema': 1,
        'suite': {
          'audit': {'verbosity': 'verbose'},
        },
      });
      expect(c.read(cruxAuditSinkProvider), isA<NoopAuditSink>());
    });
  });

  group('a configured path writes JSONL there', () {
    test('and honours the verbosity', () async {
      final path = p.join(dir.path, 'audit.jsonl');
      final c = containerFor({
        'schema': 1,
        'suite': {
          'audit': {'path': path, 'verbosity': 'verbose'},
        },
      });
      final sink = c.read(cruxAuditSinkProvider);
      await sink.record(
        AuditEvent(
          timestamp: DateTime.utc(2026, 8, 21),
          product: 'lintcrux',
          kind: 'waiver.created',
          severity: AuditSeverity.debug,
        ),
      );
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), contains('waiver.created'));
    });

    test('a MISSPELLED verbosity falls back to normal, never to off', () {
      // The one direction this must never fail in: an administrator's typo in
      // a verbosity level must not silently turn auditing off.
      final path = p.join(dir.path, 'audit.jsonl');
      final c = containerFor({
        'schema': 1,
        'suite': {
          'audit': {'path': path, 'verbosity': 'noisy'},
        },
      });
      final sink = c.read(cruxAuditSinkProvider) as JsonlAuditSink;
      expect(sink.verbosity, AuditVerbosity.normal);
    });

    test('the locked object form is unwrapped', () {
      final path = p.join(dir.path, 'audit.jsonl');
      final c = containerFor({
        'schema': 1,
        'suite': {
          'audit': {
            'value': {'path': path},
            'locked': true,
          },
        },
      });
      expect(c.read(cruxAuditSinkProvider), isA<JsonlAuditSink>());
    });
  });

  group('the managed-licence binding', () {
    test('false with no policy licence', () {
      final c = containerFor({'schema': 1, 'suite': <String, Object?>{}});
      expect(c.read(licenseManagedByOrganizationProvider), isFalse);
    });

    test('true when the policy carries one', () {
      final c = containerFor({
        'schema': 1,
        'suite': {
          'license': {'key': 'key/abc.def'},
        },
      });
      expect(c.read(licenseManagedByOrganizationProvider), isTrue);
    });
  });

  group('reporting the policy load — spec §9.2', () {
    /// A recorder over a capturing sink, so what reached the audit file is
    /// inspectable rather than inferred.
    (CruxAuditRecorder, List<AuditEvent>) recorder() {
      final events = <AuditEvent>[];
      return (
        CruxAuditRecorder(sink: _CapturingSink(events), productId: 'wavecrux'),
        events,
      );
    }

    test('no file at all reports nothing', () {
      expect(
        PolicyLoadReport.of(
          const PolicyLoadResult(document: PolicyDocument.absent),
        ),
        isNull,
      );
    });

    test('a loaded file records policy.loaded to the SINK', () async {
      final (rec, events) = recorder();
      final log = <String>[];

      final report = reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse('{"schema":1}'),
          sourcePath: '/etc/edacrux/.crux-policy.json',
          discovery: PolicyDiscovery.wellKnownPath,
          signed: true,
        ),
        recorder: rec,
        onDiagnostic: log.add,
      );
      await pumpEventQueue();

      expect(report!.destination, PolicyReportDestination.auditSink);
      expect(events.single.kind, CruxSharedAuditKinds.policyLoaded);
      expect(events.single.severity, AuditSeverity.info);
      expect(events.single.payload['discovery'], 'wellKnownPath');
      expect(events.single.payload['signed'], isTrue);
      // Nothing on the process log: the sink took it.
      expect(log, isEmpty);
    });

    test('a REFUSED file goes to the process log, not the sink', () async {
      final (rec, events) = recorder();
      final log = <String>[];

      final report = reportPolicyLoad(
        result: const PolicyLoadResult(
          document: PolicyDocument.absent,
          rejection: PolicyRejection.badSignature,
          sourcePath: '/etc/edacrux/.crux-policy.json',
          discovery: PolicyDiscovery.wellKnownPath,
          signed: true,
          detail: 'signature does not verify against the configured key',
        ),
        recorder: rec,
        onDiagnostic: log.add,
      );
      await pumpEventQueue();

      expect(report!.destination, PolicyReportDestination.processLog);
      expect(report.severity, AuditSeverity.warning);
      // The sink saw nothing — and could not have: a refused file yields an
      // absent document, so the configured sink is a NoopAuditSink.
      expect(events, isEmpty);
      expect(log.single, contains('policy.rejected'));
      expect(log.single, contains('reason=badSignature'));
    });

    test('the key state rides along, because it decides the fix', () {
      // `reason=noPublicKey key=none` is "install the key";
      // `reason=noPublicKey key=malformed` is "fix the file you installed".
      // Same reason, different afternoon.
      for (final status in PolicyKeyStatus.values) {
        final report = PolicyLoadReport.of(
          PolicyLoadResult(
            document: PolicyDocument.absent,
            rejection: PolicyRejection.noPublicKey,
            discovery: PolicyDiscovery.environmentVariable,
            signed: true,
            keyStatus: status,
          ),
        )!;
        expect(report.payload['key'], status.name);
        expect(report.line, contains('key=${status.name}'));
        expect(report.line, contains('reason=noPublicKey'));
      }
      // And on the honoured side, so an audit file records whether the file
      // that configured it was verified against an installed key.
      final loaded = PolicyLoadReport.of(
        PolicyLoadResult(
          document: PolicyDocument.parse('{"schema":1}'),
          discovery: PolicyDiscovery.wellKnownPath,
          signed: true,
          keyStatus: PolicyKeyStatus.configured,
        ),
      )!;
      expect(loaded.payload['key'], 'configured');
    });

    test('no report carries the file path', () {
      for (final result in <PolicyLoadResult>[
        const PolicyLoadResult(
          document: PolicyDocument.absent,
          rejection: PolicyRejection.untrustedUnsigned,
          sourcePath: '/Users/martin/secret_project/.crux-policy.json',
          discovery: PolicyDiscovery.environmentVariable,
        ),
        PolicyLoadResult(
          document: PolicyDocument.parse('{"schema":1}'),
          sourcePath: '/Users/martin/secret_project/.crux-policy.json',
          discovery: PolicyDiscovery.environmentVariable,
          signed: true,
        ),
      ]) {
        final report = PolicyLoadReport.of(result)!;
        // CRUX_POLICY can point at a home directory, and this line is read by
        // whoever runs the organization's log shipper.
        expect(report.line, isNot(contains('martin')));
        expect(report.line, isNot(contains('secret_project')));
      }
    });

    // --- L14: keys the build registers and ignores -------------------
    test('a key this build ignores is named at startup', () {
      final (rec, _) = recorder();
      final log = <String>[];
      reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse(
            '{"schema":1,"products":{"lintcrux":'
            '{"mandatoryEngines":["verilator"],"ciGateThreshold":10}}}',
          ),
          discovery: PolicyDiscovery.environmentVariable,
        ),
        recorder: rec,
        productId: 'lintcrux',
        onDiagnostic: log.add,
      );
      final line = log.firstWhere((l) => l.contains('keysNotHonoured'));
      // The dead key is named; the one the product acts on is not.
      expect(line, contains('mandatoryEngines'));
      expect(line, isNot(contains('ciGateThreshold')));
    });

    test('an unrecognised key is NOT named — forward compatibility', () {
      // A newer file read by an older build carries keys this release has
      // never heard of, and the schema says clients ignore those by design.
      // Naming them would make every forward-compatible file noisy at launch.
      final (rec, _) = recorder();
      final log = <String>[];
      reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse(
            '{"schema":1,"products":{"lintcrux":{"fromTheFuture":1}}}',
          ),
          discovery: PolicyDiscovery.environmentVariable,
        ),
        recorder: rec,
        productId: 'lintcrux',
        onDiagnostic: log.add,
      );
      expect(log.where((l) => l.contains('keysNotHonoured')), isEmpty);
    });

    test('an unhonoured SUITE key is named, with or without productId', () {
      // The suite block had no honoured column, so a correctly spelled
      // `suite.filePathRestrictions` produced no word at startup and no
      // restriction. Suite keys mean the same thing to every product, so the
      // report does not wait for a product id to name them.
      for (final productId in <String?>[null, 'lintcrux']) {
        final (rec, _) = recorder();
        final log = <String>[];
        reportPolicyLoad(
          result: PolicyLoadResult(
            document: PolicyDocument.parse(
              '{"schema":1,"suite":{"telemetry":"deny","remoteApis":{},'
              '"filePathRestrictions":{"deny":["/x/**"]}}}',
            ),
            discovery: PolicyDiscovery.environmentVariable,
          ),
          recorder: rec,
          productId: productId,
          onDiagnostic: log.add,
        );
        final line = log.singleWhere((l) => l.contains('keysNotHonoured'));
        expect(line, contains('scope=suite'), reason: '$productId');
        // Sorted, and only the dead ones: `telemetry` is honoured.
        expect(
          line,
          contains('keys=filePathRestrictions,remoteApis '),
          reason: '$productId',
        );
      }
    });

    test('every suite key the registry marks unhonoured is named', () {
      final dead = kSuiteKeys.entries.where((e) => !e.value).map((e) => e.key);
      expect(dead, isNotEmpty, reason: 'nothing to prove');
      final (rec, _) = recorder();
      final log = <String>[];
      reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse(
            jsonEncode({
              'schema': 1,
              'suite': {
                for (final k in kSuiteKeys.keys) k: <String, Object?>{},
              },
            }),
          ),
          discovery: PolicyDiscovery.environmentVariable,
        ),
        recorder: rec,
        onDiagnostic: log.add,
      );
      final line = log.singleWhere((l) => l.contains('scope=suite'));
      expect(line, contains('keys=${(dead.toList()..sort()).join(",")} '));
    });

    test('a file with only honoured suite keys names nothing', () {
      final (rec, _) = recorder();
      final log = <String>[];
      reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse(
            '{"schema":1,"suite":{"telemetry":"deny","updateChannel":"stable",'
            '"audit":{"verbosity":"off"},"fromTheFuture":1}}',
          ),
          discovery: PolicyDiscovery.environmentVariable,
        ),
        recorder: rec,
        productId: 'wavecrux',
        onDiagnostic: log.add,
      );
      // `fromTheFuture` is unrecognised, which is forward compatibility, not
      // a dead key.
      expect(log.where((l) => l.contains('keysNotHonoured')), isEmpty);
    });

    test('without productId no product key is reported', () {
      final (rec, _) = recorder();
      final log = <String>[];
      reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse(
            '{"schema":1,"products":{"lintcrux":{"mandatoryEngines":[]}}}',
          ),
          discovery: PolicyDiscovery.environmentVariable,
        ),
        recorder: rec,
        onDiagnostic: log.add,
      );
      expect(log.where((l) => l.contains('keysNotHonoured')), isEmpty);
    });
  });
}

/// Keeps every event, so a test can assert what reached the sink.
class _CapturingSink implements AuditSink {
  _CapturingSink(this.events);

  final List<AuditEvent> events;

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  @override
  Future<void> close() async {}
}
