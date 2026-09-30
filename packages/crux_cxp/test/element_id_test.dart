// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

void main() {
  group('ElementId', () {
    test('round-trips through fromJson/toJson for every kind', () {
      for (final kind in ElementKind.values) {
        final original = ElementId(kind: kind, path: 'top.${kind.name}.path');
        final json = original.toJson();
        final recovered = ElementId.fromJson(json);
        expect(recovered, equals(original));
        expect(recovered.kind, kind);
        expect(recovered.path, 'top.${kind.name}.path');
      }
    });

    test('equality is value-based on kind and path', () {
      const a = ElementId(kind: ElementKind.signal, path: 'top.alu.sum[31:0]');
      const b = ElementId(kind: ElementKind.signal, path: 'top.alu.sum[31:0]');
      const c = ElementId(kind: ElementKind.signal, path: 'top.alu.sum');
      const d = ElementId(kind: ElementKind.net, path: 'top.alu.sum[31:0]');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes kind and path', () {
      const id = ElementId(kind: ElementKind.signal, path: 'top.x');
      expect(id.toString(), contains('signal'));
      expect(id.toString(), contains('top.x'));
    });

    test('fromJson throws on missing kind', () {
      expect(
        () => ElementId.fromJson(const <String, Object?>{'path': 'x'}),
        throwsFormatException,
      );
    });

    test('fromJson throws on missing path', () {
      expect(
        () => ElementId.fromJson(const <String, Object?>{'kind': 'signal'}),
        throwsFormatException,
      );
    });

    test('fromJson throws on an empty kind', () {
      expect(
        () => ElementId.fromJson(const <String, Object?>{
          'kind': '',
          'path': 'x',
        }),
        throwsFormatException,
      );
    });
  });

  // ElementKind is an OPEN wire type. A closed enum would have made
  // every future product-defined kind a decode failure at every peer built
  // before it — the opposite of what CxpMessageKind next door already does.
  group('ElementKind is open', () {
    test('an unknown kind decodes instead of throwing', () {
      final id = ElementId.fromJson(const <String, Object?>{
        'kind': 'coverage_bin',
        'path': 'top.cov.b0',
      });
      expect(id.kind.name, 'coverage_bin');
      expect(id.kind.known, isNull);
      expect(id.kind.isKnown, isFalse);
      expect(id.path, 'top.cov.b0');
    });

    test('an unknown kind round-trips back onto the wire unchanged', () {
      const wire = <String, Object?>{
        'kind': 'coverage_bin',
        'path': 'top.cov.b0',
      };
      // Forwarding a reference a peer cannot interpret must not corrupt
      // or drop it — that is the whole point of opening the type.
      expect(ElementId.fromJson(wire).toJson(), wire);
    });

    test('known kinds keep their exact pre-existing wire encoding', () {
      // Wire compatibility with the closed-enum serialization: every
      // value that existed before still encodes to the identical string.
      expect(
        ElementKind.values.map((k) => k.name).toList(),
        <String>[
          'signal',
          'scope',
          'instance',
          'net',
          'port',
          'marker',
          'rule',
          'test',
          'breakpoint',
          'source',
        ],
      );
      for (final kind in ElementKind.values) {
        final id = ElementId(kind: kind, path: 'p');
        expect(ElementId.fromJson(id.toJson()), id);
        expect(id.toJson()['kind'], kind.name);
      }
    });

    test('a known kind parsed from the wire is the canonical constant', () {
      expect(
        identical(ElementKind('signal'), ElementKind.signal),
        isTrue,
        reason: 'known names must not mint duplicate instances',
      );
    });

    test('equality and hashing are by wire name', () {
      expect(ElementKind('coverage_bin'), ElementKind('coverage_bin'));
      expect(
        ElementKind('coverage_bin').hashCode,
        ElementKind('coverage_bin').hashCode,
      );
      expect(ElementKind('coverage_bin'), isNot(ElementKind.signal));
      // So an unknown kind is usable as a Set member / Map key, which is
      // what CxpSubscription.elementKinds relies on.
      expect(
        <ElementKind>{
          ElementKind('coverage_bin'),
          ElementKind('coverage_bin'),
        },
        hasLength(1),
      );
    });

    test('every KnownElementKind has a matching ElementKind constant', () {
      // Guards the two declarations against drifting apart.
      expect(
        ElementKind.values.map((k) => k.known).toSet(),
        KnownElementKind.values.toSet(),
      );
      for (final kind in ElementKind.values) {
        expect(kind.known!.name, kind.name);
      }
    });

    test('internal code can still switch exhaustively via known', () {
      String describe(ElementKind kind) => switch (kind.known) {
        KnownElementKind.signal => 'signal',
        KnownElementKind.scope => 'scope',
        KnownElementKind.instance => 'instance',
        KnownElementKind.net => 'net',
        KnownElementKind.port => 'port',
        KnownElementKind.marker => 'marker',
        KnownElementKind.rule => 'rule',
        KnownElementKind.test => 'test',
        KnownElementKind.breakpoint => 'breakpoint',
        KnownElementKind.source => 'source',
        null => 'unknown',
      };
      expect(describe(ElementKind.signal), 'signal');
      expect(describe(ElementKind('coverage_bin')), 'unknown');
    });
  });
}
