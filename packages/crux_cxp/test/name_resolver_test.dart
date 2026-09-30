// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

void main() {
  group('NoopNameResolver', () {
    test('maps every kind/local to null', () {
      const r = NoopNameResolver();
      for (final kind in ElementKind.values) {
        expect(r.toCanonical(kind: kind, local: 'x'), isNull);
      }
      expect(
        r.toLocal(const ElementId(kind: ElementKind.signal, path: 'x')),
        isNull,
      );
    });
  });

  group('IdentityNameResolver', () {
    test('toCanonical wraps the local string in the requested kind', () {
      const r = IdentityNameResolver();
      final id = r.toCanonical(kind: ElementKind.signal, local: 'top.a');
      expect(id, isNotNull);
      expect(id!.kind, ElementKind.signal);
      expect(id.path, 'top.a');
    });

    test('toLocal returns the canonical path verbatim', () {
      const r = IdentityNameResolver();
      const id = ElementId(kind: ElementKind.signal, path: 'top.a.b');
      expect(r.toLocal(id), 'top.a.b');
    });
  });

  group('PeerIdentity', () {
    test('round-trips through fromJson/toJson', () {
      const id = PeerIdentity(
        peerId: 'wavecrux-1',
        productName: 'wavecrux',
        productVersion: '1.2.3',
        capabilities: {'wavecrux.signal_value', 'cxp.v1'},
      );
      final recovered = PeerIdentity.fromJson(id.toJson());
      expect(recovered, equals(id));
    });

    test('fromJson rejects missing required fields', () {
      expect(
        () => PeerIdentity.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
    });
  });
}
