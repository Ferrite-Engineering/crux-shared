// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-rolled implementation, standing in for a product-side fake. Proves
/// the interface is implementable with nothing but the barrel import.
class _AlwaysAvailable implements UpdateCheckService {
  @override
  Future<UpdateInfo?> checkForUpdate() async =>
      const UpdateInfo(version: '9.9.9');
}

void main() {
  group('UpdateCheckService', () {
    test('an implementation may resolve to an UpdateInfo', () async {
      expect((await _AlwaysAvailable().checkForUpdate())!.version, '9.9.9');
    });
  });

  group('UpdateCheckException', () {
    test('carries a diagnostic reason and an optional cause', () {
      final cause = StateError('boom');
      final e = UpdateCheckException('network', cause);
      expect(e.reason, 'network');
      expect(e.cause, same(cause));
    });

    test('the cause is optional', () {
      const e = UpdateCheckException('parse');
      expect(e.cause, isNull);
    });

    test('toString exposes the reason but never the cause', () {
      final e = UpdateCheckException('network', StateError('secret host'));
      expect(e.toString(), 'UpdateCheckException(network)');
      expect(e.toString(), isNot(contains('secret host')));
    });

    test('is an Exception, not an Error', () {
      expect(const UpdateCheckException('parse'), isA<Exception>());
    });
  });
}
