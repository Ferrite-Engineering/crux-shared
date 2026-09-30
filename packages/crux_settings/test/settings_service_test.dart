// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A trivial typed settings value used to verify `SettingsService<T>`'s
/// generic plumbing. Only one int field; the field-level concerns are
/// covered in detail by the CoreSettingsCodec tests.
@immutable
class _Counter {
  const _Counter(this.value);
  final int value;

  @override
  bool operator ==(Object other) => other is _Counter && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class _CounterCodec implements SettingsCodec<_Counter> {
  const _CounterCodec();

  @override
  Future<_Counter> load(SharedPreferences prefs) async {
    return _Counter(prefs.getInt('counter') ?? 0);
  }

  @override
  Future<void> save(SharedPreferences prefs, _Counter settings) async {
    await prefs.setInt('counter', settings.value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService<T>', () {
    test('delegates load to the supplied codec', () async {
      SharedPreferences.setMockInitialValues({'counter': 42});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService<_Counter>(
        const _CounterCodec(),
        prefsOverride: prefs,
      );
      expect(await service.load(), const _Counter(42));
    });

    test('delegates save to the supplied codec', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService<_Counter>(
        const _CounterCodec(),
        prefsOverride: prefs,
      );
      await service.save(const _Counter(7));
      expect(prefs.getInt('counter'), 7);
    });

    test('save + load round-trips through the codec', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService<_Counter>(
        const _CounterCodec(),
        prefsOverride: prefs,
      );
      await service.save(const _Counter(13));
      expect(await service.load(), const _Counter(13));
    });

    test(
      'falls back to SharedPreferences.getInstance() when no override given',
      () async {
        SharedPreferences.setMockInitialValues({'counter': 99});
        const service = SettingsService<_Counter>(_CounterCodec());
        expect(await service.load(), const _Counter(99));
      },
    );
  });

  group('SettingsService<CoreSettings>', () {
    test('round-trips a CoreSettings through the production codec', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService<CoreSettings>(
        const CoreSettingsCodec(),
        prefsOverride: prefs,
      );
      final original = const CoreSettings.defaults().copyWith(
        themeMode: AppThemeMode.light,
        locale: 'ja',
      );
      await service.save(original);
      final loaded = await service.load();
      expect(loaded, equals(original));
    });
  });
}
