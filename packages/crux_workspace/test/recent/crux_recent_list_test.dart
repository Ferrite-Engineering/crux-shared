// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A store whose read the test releases by hand, so it can land opens,
/// removals and clears before the stored list arrives.
class _GatedStore implements CruxRecentStore {
  _GatedStore(this.stored);

  final List<String> stored;
  final Completer<void> gate = Completer<void>();
  List<String>? saved;

  @override
  Future<List<String>> load() async {
    await gate.future;
    return stored;
  }

  @override
  Future<void> save(List<String> entries) async => saved = entries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CruxRecentListNotifier', () {
    late _GatedStore store;
    late CruxRecentList list;
    late List<String> removedHook;
    late ProviderContainer container;

    setUp(() {
      store = _GatedStore(<String>['/a.vcd', '/b.vcd', '/sessions/x.json']);
      removedHook = <String>[];
      list = CruxRecentList(
        name: 'testRecent',
        store: (_) => store,
        capacity: 3,
        accepts: (path) => !path.startsWith('/sessions/'),
        onRemoved: removedHook.add,
      );
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    Future<void> release() async {
      store.gate.complete();
      await container.read(list.provider.notifier).restored;
    }

    test('reads the stored list, dropping rejected entries and saving the '
        'cleaned list', () async {
      expect(container.read(list.provider), isEmpty);
      await release();
      expect(container.read(list.provider), ['/a.vcd', '/b.vcd']);
      expect(store.saved, ['/a.vcd', '/b.vcd']);
    });

    test('markOpened moves an entry to the front and caps the list', () async {
      await release();
      final notifier = container.read(list.provider.notifier)
        ..markOpened('/c.vcd')
        ..markOpened('/d.vcd');
      expect(container.read(list.provider), ['/d.vcd', '/c.vcd', '/a.vcd']);
      notifier.markOpened('/a.vcd');
      expect(container.read(list.provider), ['/a.vcd', '/d.vcd', '/c.vcd']);
      expect(store.saved, ['/a.vcd', '/d.vcd', '/c.vcd']);
    });

    test('a rejected entry is never recorded', () async {
      await release();
      container.read(list.provider.notifier).markOpened('/sessions/y.json');
      expect(container.read(list.provider), ['/a.vcd', '/b.vcd']);
    });

    test('an open before the stored list arrives goes in front of it, and '
        'nothing is saved until it has arrived', () async {
      container.read(list.provider.notifier).markOpened('/c.vcd');
      expect(store.saved, isNull);
      await release();
      expect(container.read(list.provider), ['/c.vcd', '/a.vcd', '/b.vcd']);
      expect(store.saved, ['/c.vcd', '/a.vcd', '/b.vcd']);
    });

    test(
      'a removal before the stored list arrives is not undone by it',
      () async {
        container.read(list.provider.notifier).remove('/a.vcd');
        await release();
        expect(container.read(list.provider), ['/b.vcd']);
        expect(removedHook, ['/a.vcd']);
      },
    );

    test(
      'a clear before the stored list arrives discards the stored list',
      () async {
        container.read(list.provider.notifier)
          ..markOpened('/c.vcd')
          ..clear()
          ..markOpened('/d.vcd');
        await release();
        expect(container.read(list.provider), ['/d.vcd']);
        expect(store.saved, ['/d.vcd']);
      },
    );

    test('clear empties and saves the list and reports every entry', () async {
      await release();
      container.read(list.provider.notifier).clear();
      expect(container.read(list.provider), isEmpty);
      expect(store.saved, isEmpty);
      expect(removedHook, ['/a.vcd', '/b.vcd']);
    });

    test('open: a failed or throwing open drops the entry, a good one moves '
        'it to the front', () async {
      await release();
      final notifier = container.read(list.provider.notifier);
      expect(
        await notifier.open('/b.vcd', (_) async => true),
        CruxRecentOpenResult.opened,
      );
      expect(container.read(list.provider), ['/b.vcd', '/a.vcd']);
      expect(
        await notifier.open('/a.vcd', (_) async => false),
        CruxRecentOpenResult.removed,
      );
      expect(container.read(list.provider), ['/b.vcd']);
      expect(
        await notifier.open('/b.vcd', (_) async => throw StateError('gone')),
        CruxRecentOpenResult.removed,
      );
      expect(container.read(list.provider), isEmpty);
    });
  });

  group('CruxPrefsRecentStore', () {
    test('round-trips under the product key and reads a wrong-typed value '
        'as empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'recent_files': <String>['/x.vcd'],
        'broken': 7,
      });
      final prefs = await SharedPreferences.getInstance();
      final store = CruxPrefsRecentStore('recent_files', prefsOverride: prefs);
      expect(await store.load(), ['/x.vcd']);
      await store.save(<String>['/y.vcd', '/x.vcd']);
      expect(prefs.getStringList('recent_files'), ['/y.vcd', '/x.vcd']);
      expect(
        await CruxPrefsRecentStore('broken', prefsOverride: prefs).load(),
        isEmpty,
      );
    });
  });

  test('cruxRecentEntryExists sees files and directories', () async {
    final dir = await Directory.systemTemp.createTemp('crux_recent_exists_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/a.vcd')..writeAsStringSync('x');
    expect(cruxRecentEntryExists(file.path), isTrue);
    expect(cruxRecentEntryExists(dir.path), isTrue);
    expect(cruxRecentEntryExists('${dir.path}/missing.vcd'), isFalse);
  });

  test('strings: every kind in every suite locale, English as fallback', () {
    for (final code in ['en', 'zh', 'ja', 'ko', 'fr']) {
      for (final kind in CruxRecentKind.values) {
        final s = CruxRecentListStrings.forLocale(Locale(code), kind);
        expect(s.heading, isNotEmpty);
        expect(s.clearCommand, isNotEmpty);
        expect(s.removedMissing('a.vcd'), contains('a.vcd'));
        for (final text in [
          s.heading,
          s.empty,
          s.removeTooltip,
          s.missing,
          s.clearCommand,
          s.cleared,
          s.removedMissing('a.vcd'),
        ]) {
          expect(text, isNot(contains('—')), reason: 'no em dash');
        }
      }
    }
    expect(
      CruxRecentListStrings.forLocale(
        const Locale('fr'),
        CruxRecentKind.files,
      ).clearCommand,
      'Clear Recent Files',
    );
  });
}
