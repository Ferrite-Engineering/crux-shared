// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInner implements UpdateCheckService {
  _FakeInner(this._result);
  _FakeInner.throwing(this._error) : _result = null;

  final UpdateInfo? _result;

  /// Deliberately typed: `UpdateCheckService`'s contract admits exactly one
  /// failure, so a fake that could throw anything else would be testing a
  /// scenario production cannot produce.
  UpdateCheckException? _error;
  int calls = 0;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    calls++;
    final error = _error;
    if (error != null) throw error;
    return _result;
  }
}

void main() {
  test('offers what the policy allows', () async {
    final service = PolicyConstrainedUpdateCheckService(
      inner: _FakeInner(const UpdateInfo(version: '2.0.0')),
      policy: const UpdatePolicy(channel: UpdateChannelPolicy.stable),
    );
    expect((await service.checkForUpdate())!.version, '2.0.0');
  });

  test('withholds what the policy does not', () async {
    final service = PolicyConstrainedUpdateCheckService(
      inner: _FakeInner(const UpdateInfo(version: '2.0.0', channel: 'beta')),
      policy: const UpdatePolicy(channel: UpdateChannelPolicy.stable),
    );
    expect(await service.checkForUpdate(), isNull);
  });

  test('still fetches when it will withhold', () async {
    // Load-bearing: the inner service records the manifest's `server_time` on
    // every successful fetch, and that observation is what keeps the beta
    // clock honest. A constraint that skipped the fetch would hand every
    // pinned seat a way to stop it.
    final inner = _FakeInner(
      const UpdateInfo(version: '2.0.0', channel: 'beta'),
    );
    final service = PolicyConstrainedUpdateCheckService(
      inner: inner,
      policy: const UpdatePolicy(channel: UpdateChannelPolicy.stable),
    );
    await service.checkForUpdate();
    expect(inner.calls, 1);
  });

  test('passes "no update" straight through', () async {
    final service = PolicyConstrainedUpdateCheckService(
      inner: _FakeInner(null),
      policy: const UpdatePolicy(channel: UpdateChannelPolicy.stable),
    );
    expect(await service.checkForUpdate(), isNull);
  });

  test(
    'lets the typed failure through rather than reporting current',
    () async {
      // Converting a network outage into "no update" would tell the user they
      // are up to date when nobody checked.
      final service = PolicyConstrainedUpdateCheckService(
        inner: _FakeInner.throwing(const UpdateCheckException('network')),
        policy: const UpdatePolicy(channel: UpdateChannelPolicy.stable),
      );
      await expectLater(
        service.checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
    },
  );

  test('an absent policy changes nothing', () async {
    final service = PolicyConstrainedUpdateCheckService(
      inner: _FakeInner(const UpdateInfo(version: '2.0.0', channel: 'nightly')),
      policy: UpdatePolicy.absent,
    );
    expect((await service.checkForUpdate())!.version, '2.0.0');
  });
}
