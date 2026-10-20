// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const codec = CxpSettingsCodec(prefix: 'netcrux.', defaultPort: 54323);

  test('reads the keys every product has saved since its first release', () {
    expect(codec.enabledKey, 'netcrux.cxpServerEnabled');
    expect(codec.portKey, 'netcrux.cxpServerPort');
    expect(codec.requestAttentionKey, 'netcrux.requestAttentionOnCrossProbe');
    expect(
      codec.broadcastSelectionKey,
      'netcrux.broadcastSelectionOnCrossProbe',
    );
  });

  test('a choice saved by the earlier release is honoured', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'netcrux.cxpServerEnabled': false,
      'netcrux.cxpServerPort': 60001,
      'netcrux.requestAttentionOnCrossProbe': false,
      'netcrux.broadcastSelectionOnCrossProbe': false,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      await codec.load(prefs),
      const CxpSettings(
        enabled: false,
        port: 60001,
        requestAttention: false,
        broadcastSelection: false,
      ),
    );
  });

  test('nothing saved reads as the product defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    expect(await codec.load(prefs), codec.defaults);
    expect(codec.defaults, const CxpSettings(enabled: true, port: 54323));
  });

  test(
    'a wrong-typed value or an out-of-range port reads as its default',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'netcrux.cxpServerEnabled': 'yes',
        'netcrux.cxpServerPort': 70000,
      });
      final prefs = await SharedPreferences.getInstance();
      final loaded = await codec.load(prefs);
      expect(loaded.enabled, isTrue);
      expect(loaded.port, 54323);
    },
  );

  test('save and load round-trip', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    const value = CxpSettings(
      enabled: false,
      port: 50000,
      broadcastSelection: false,
    );
    await codec.save(prefs, value);
    expect(await codec.load(prefs), value);
  });
}
