// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NoopUpdateCheckService always reports up to date', () async {
    const service = NoopUpdateCheckService();
    expect(await service.checkForUpdate(), isNull);
    expect(await service.checkForUpdate(), isNull);
  });

  test('is an UpdateCheckService and never throws', () {
    const service = NoopUpdateCheckService();
    expect(service, isA<UpdateCheckService>());
    expect(service.checkForUpdate(), completes);
  });
}
