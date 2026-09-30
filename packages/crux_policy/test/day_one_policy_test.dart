// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';
import 'package:test/test.dart';

/// The three keys that must resolve BEFORE a licence exists.
///
/// The first-launch telemetry disclosure fires before any key has been entered,
/// so the tier is unknown at that instant by construction. A design that
/// resolves a tier and then decides is wrong — and would LOOK like it works,
/// because in development a licence is always already there.
void main() {
  DayOnePolicy of(String json) => DayOnePolicy.of(PolicyDocument.parse(json));

  group('absent behaves as if the seam did not exist', () {
    test('no file', () {
      expect(DayOnePolicy.absent.telemetry, PolicyTelemetryDecision.absent);
      expect(DayOnePolicy.absent.license, isNull);
      expect(DayOnePolicy.absent.updateChannel, isNull);
    });

    test('a file with none of the three keys', () {
      final policy = of('{"schema":1,"suite":{"theme":"x"}}');
      expect(policy.telemetry, PolicyTelemetryDecision.absent);
      expect(policy.license, isNull);
      expect(policy.updateChannel, isNull);
    });
  });

  group('telemetry', () {
    test('deny and allow are read', () {
      expect(
        of('{"schema":1,"suite":{"telemetry":"deny"}}').telemetry,
        PolicyTelemetryDecision.deny,
      );
      expect(
        of('{"schema":1,"suite":{"telemetry":"allow"}}').telemetry,
        PolicyTelemetryDecision.allow,
      );
    });

    test('the locked object form works too', () {
      expect(
        of('''
          {"schema":1,"suite":{"telemetry":{"value":"deny","locked":true}}}
        ''').telemetry,
        PolicyTelemetryDecision.deny,
      );
    });

    test(
      'anything unrecognised is absent, never a guess and never a throw',
      () {
        for (final raw in <String>[
          '"maybe"',
          '"DENY"',
          '42',
          'null',
          '{}',
          '[]',
        ]) {
          expect(
            of('{"schema":1,"suite":{"telemetry":$raw}}').telemetry,
            PolicyTelemetryDecision.absent,
            reason: raw,
          );
        }
      },
    );
  });

  group('license', () {
    test('an inline credential', () {
      final l = of('''
        {"schema":1,"suite":{"license":{"key":"key/abc.def"}}}
      ''').license;
      expect(l!.kind, PolicyLicenseKind.inline);
      expect(l.value, 'key/abc.def');
    });

    test('a path on the org share', () {
      final l = of('''
        {"schema":1,"suite":{"license":{"file":"/opt/example/crux.lic"}}}
      ''').license;
      expect(l!.kind, PolicyLicenseKind.file);
      expect(l.value, '/opt/example/crux.lic');
    });

    test(
      'BOTH is invalid — guessing which was meant is worse than ignoring',
      () {
        expect(
          of('''
          {"schema":1,"suite":{"license":{"key":"k","file":"/f"}}}
        ''').license,
          isNull,
        );
      },
    );

    test('empty or malformed is ignored', () {
      for (final raw in <String>[
        '{"key":"   "}',
        '{"file":""}',
        '{}',
        '"a bare string"',
        '42',
      ]) {
        expect(
          of('{"schema":1,"suite":{"license":$raw}}').license,
          isNull,
          reason: raw,
        );
      }
    });
  });

  group('updateChannel', () {
    test('the three values', () {
      expect(
        of('{"schema":1,"suite":{"updateChannel":"stable"}}').updateChannel,
        PolicyUpdateChannel.stable,
      );
      expect(
        of('{"schema":1,"suite":{"updateChannel":"beta"}}').updateChannel,
        PolicyUpdateChannel.beta,
      );
      expect(
        of('''
          {"schema":1,"suite":{"updateChannel":"pinned","pinnedVersion":"1.0.0"}}
        ''').pinnedVersion,
        '1.0.0',
      );
    });

    test('an unknown channel is null, not an error', () {
      expect(
        of('{"schema":1,"suite":{"updateChannel":"weekly"}}').updateChannel,
        isNull,
      );
    });
  });

  group('it resolves with NO licence and NO tier anywhere in reach', () {
    test('a full Enterprise deployment file resolves all three', () {
      // The launch-day case: an IT department has deployed this and no engineer
      // has opened the licence panel, because they must never need to.
      final policy = of('''
      {
        "schema": 1,
        "org": "Example Semiconductor",
        "suite": {
          "telemetry": "deny",
          "license": {"file": "/opt/example/crux-enterprise.lic"},
          "updateChannel": {"value": "pinned", "locked": true},
          "pinnedVersion": "1.0.0",
          "manifestUrl": "https://mirror.example.internal/manifest.json"
        }
      }
      ''');
      expect(policy.telemetry, PolicyTelemetryDecision.deny);
      expect(policy.license!.kind, PolicyLicenseKind.file);
      expect(policy.updateChannel, PolicyUpdateChannel.pinned);
      expect(policy.pinnedVersion, '1.0.0');
      expect(policy.manifestUrl, isNotNull);
    });

    test('a file from a future schema still yields the three', () {
      final policy = of('''
      {
        "schema": 99,
        "suite": {
          "telemetry": "deny",
          "somethingNobodyHasBuiltYet": {"value": 1, "locked": true}
        }
      }
      ''');
      expect(policy.telemetry, PolicyTelemetryDecision.deny);
    });

    test('never throws, for any input at all', () {
      for (final input in <String>[
        '',
        'null',
        '[]',
        '{"schema":1,"suite":null}',
        '{"schema":1,"suite":{"telemetry":{"value":{"nested":true}}}}',
        '{"schema":1,"suite":{"license":[]}}',
      ]) {
        expect(() => of(input), returnsNormally, reason: input);
      }
    });
  });
}
