// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';
import 'package:test/test.dart';

/// Precedence, invalid values, and the version-skew contract.
void main() {
  PolicyResolver resolverFor(String json, {String productId = 'lintcrux'}) =>
      PolicyResolver(
        document: PolicyDocument.parse(json),
        productId: productId,
      );

  String? asString(Object? raw) => raw is String ? raw : null;
  int? asInt(Object? raw) => raw is int ? raw : null;
  String? asChannel(Object? raw) =>
      raw is String && const {'stable', 'beta', 'pinned'}.contains(raw)
      ? raw
      : null;

  group('precedence — locked > default > user > built-in', () {
    test('a locked value beats the user setting', () {
      final r = resolverFor('''
        {"schema":1,"suite":{"theme":{"value":"org-dark","locked":true}}}
      ''');
      final v = r.suiteValue<String>(
        'theme',
        parse: asString,
        builtIn: 'light',
        userSetting: 'solarized',
      );
      expect(v.value, 'org-dark');
      expect(v.source, PolicySource.policyLocked);
      expect(v.locked, isTrue);
    });

    test('a policy DEFAULT loses to the user setting', () {
      // The bare form, and the object form with locked:false, both mean "the
      // organization suggests this; the user may still change it".
      for (final json in <String>[
        '{"schema":1,"suite":{"theme":"org-dark"}}',
        '{"schema":1,"suite":{"theme":{"value":"org-dark","locked":false}}}',
      ]) {
        final v = resolverFor(json).suiteValue<String>(
          'theme',
          parse: asString,
          builtIn: 'light',
          userSetting: 'solarized',
        );
        expect(v.value, 'solarized', reason: json);
        expect(v.source, PolicySource.userSetting, reason: json);
      }
    });

    test('a policy default wins when the user has set nothing', () {
      final v = resolverFor(
        '{"schema":1,"suite":{"theme":"org-dark"}}',
      ).suiteValue<String>('theme', parse: asString, builtIn: 'light');
      expect(v.value, 'org-dark');
      expect(v.source, PolicySource.policyDefault);
    });

    test('the built-in default is the floor', () {
      final v = resolverFor('{"schema":1}').suiteValue<String>(
        'theme',
        parse: asString,
        builtIn: 'light',
      );
      expect(v.value, 'light');
      expect(v.source, PolicySource.builtIn);
      expect(v.locked, isFalse);
    });
  });

  group('an invalid value is skipped and REPORTED, never fatal', () {
    test('a locked-but-invalid key falls back to the USER setting', () {
      // Not to a lock. Inventing a value nobody wrote and presenting it as the
      // organization's decision would be worse than ignoring the key.
      final r = resolverFor('''
        {"schema":1,"suite":{"updateChannel":{"value":"weekly","locked":true}}}
      ''');
      final v = r.suiteValue<String>(
        'updateChannel',
        parse: asChannel,
        builtIn: 'stable',
        userSetting: 'beta',
      );
      expect(v.value, 'beta');
      expect(v.source, PolicySource.userSetting);
      expect(v.locked, isFalse);
      expect(r.diagnostics.map((d) => d.key), contains('suite.updateChannel'));
    });

    test('one bad key does not discard the others', () {
      final r = resolverFor('''
        {"schema":1,"suite":{"updateChannel":"weekly","theme":"org-dark"}}
      ''');
      expect(
        r
            .suiteValue<String>(
              'updateChannel',
              parse: asChannel,
              builtIn: 'stable',
            )
            .source,
        PolicySource.builtIn,
      );
      expect(
        r.suiteValue<String>('theme', parse: asString, builtIn: 'light').value,
        'org-dark',
      );
    });

    test('the wrong TYPE is invalid, not coerced', () {
      final r = resolverFor('{"schema":1,"suite":{"theme":{"nope":1}}}');
      final v = r.suiteValue<String>(
        'theme',
        parse: asString,
        builtIn: 'light',
      );
      expect(v.source, PolicySource.builtIn);
      expect(r.diagnostics, isNotEmpty);
    });

    test('a non-boolean "locked" is invalid', () {
      final r = resolverFor(
        '{"schema":1,"suite":{"theme":{"value":"x","locked":"yes"}}}',
      );
      expect(
        r.suiteValue<String>('theme', parse: asString, builtIn: 'light').source,
        PolicySource.builtIn,
      );
      expect(r.diagnostics, isNotEmpty);
    });

    test('a silently-ignored lock is exactly what must NOT happen', () {
      final r = resolverFor(
        '{"schema":1,"suite":{"theme":{"value":42,"locked":true}}}',
      )..suiteValue<String>('theme', parse: asString, builtIn: 'light');
      expect(
        r.diagnostics.single.reason,
        contains('not valid'),
        reason:
            'an administrator believes that lock is in force; the skip has to '
            'be reportable',
      );
    });
  });

  group('per-product namespaces', () {
    test('this product reads its own keys', () {
      final v = resolverFor('''
        {"schema":1,"products":{"lintcrux":{"ciGateThreshold":0}}}
      ''').productValue<int>('ciGateThreshold', parse: asInt, builtIn: 10);
      expect(v.value, 0);
      expect(v.source, PolicySource.policyDefault);
    });

    test("another product's keys are ignored SILENTLY", () {
      // One file serves a mixed fleet. A WaveCrux install meeting SimCrux keys
      // is the normal case, not a misconfiguration, so it must not warn.
      final r = resolverFor('''
        {"schema":1,"products":{"simcrux":{"ciGateThreshold":0}}}
      ''');
      final v = r.productValue<int>(
        'ciGateThreshold',
        parse: asInt,
        builtIn: 10,
      );
      expect(v.value, 10);
      expect(v.source, PolicySource.builtIn);
      expect(r.diagnostics, isEmpty, reason: 'not warned about, not an error');
    });
  });

  group('version skew — the whole additive-only story', () {
    // Proven, not assumed. This is what lets a five-year-old client and a
    // current policy file coexist.
    const future = '''
    {
      "schema": 99,
      "org": "Example",
      "unknownTopLevel": {"anything": true},
      "suite": {
        "theme": {"value": "org-dark", "locked": true},
        "keyFromTheFuture": {"value": 1, "locked": true},
        "anotherOne": ["a", "list", "we", "do", "not", "know"]
      },
      "products": {
        "lintcrux": {"ciGateThreshold": 0, "futureProductKey": "x"},
        "productThatDoesNotExist": {"whatever": 1}
      }
    }
    ''';

    test('a file from a future schema still resolves the known keys', () {
      final r = resolverFor(future);
      expect(
        r.suiteValue<String>('theme', parse: asString, builtIn: 'light').value,
        'org-dark',
      );
      expect(
        r.productValue<int>('ciGateThreshold', parse: asInt, builtIn: 10).value,
        0,
      );
    });

    test('a higher schema number is NOT a reason to refuse the file', () {
      // The schema number exists for the CLI's diagnostics, not the client's
      // gatekeeping. A client that refuses a newer file has reintroduced
      // exactly the coupling this design removes.
      expect(PolicyDocument.parse(future).isPresent, isTrue);
    });

    test('unknown keys produce no diagnostics — they are simply ignored', () {
      final r = resolverFor(future)
        ..suiteValue<String>('theme', parse: asString, builtIn: 'light');
      expect(r.diagnostics, isEmpty);
    });
  });

  group('parsing is total', () {
    test('no input throws', () {
      for (final input in <String>[
        '',
        '   ',
        'null',
        '[]',
        '"a string"',
        '42',
        '{',
        '{"schema": "one"}',
        '{"schema": 1, "suite": []}',
        '{"schema": 1, "products": "nope"}',
        '{"schema": 1, "products": {"lintcrux": 5}}',
      ]) {
        expect(
          () => PolicyDocument.parse(input),
          returnsNormally,
          reason: 'input: $input',
        );
      }
    });

    test('a missing schema is reported', () {
      final doc = PolicyDocument.parse('{"suite":{}}');
      expect(doc.diagnostics.map((d) => d.key), contains('schema'));
    });

    test('absent behaves exactly as if the seam did not exist', () {
      const doc = PolicyDocument.absent;
      expect(doc.isPresent, isFalse);
      expect(doc.suite, isEmpty);
      expect(doc.products, isEmpty);
      final r = PolicyResolver(document: doc, productId: 'lintcrux');
      final v = r.suiteValue<String>(
        'theme',
        parse: asString,
        builtIn: 'light',
        userSetting: 'solarized',
      );
      expect(v.value, 'solarized');
      expect(v.source, PolicySource.userSetting);
    });
  });
}
