// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_collections/crux_collections.dart';
import 'package:test/test.dart';

void main() {
  group('LruCache', () {
    test('evicts the least recently used entry past maxEntries', () {
      final cache = LruCache<String, int>(maxEntries: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;
      cache['d'] = 4;
      expect(cache.keys, ['b', 'c', 'd']);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.evictionCount, 1);
    });

    test('a read promotes the entry so it survives the next eviction', () {
      final cache = LruCache<String, int>(maxEntries: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;
      expect(cache['a'], 1);
      cache['d'] = 4;
      expect(cache.keys, ['c', 'a', 'd']);
    });

    test('peek reads without promoting', () {
      final cache = LruCache<String, int>(maxEntries: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;
      expect(cache.peek('a'), 1);
      expect(cache.peek('zz'), isNull);
      cache['d'] = 4;
      expect(cache.keys, ['b', 'c', 'd'], reason: 'a was not promoted');
    });

    test('storing under an existing key replaces and promotes it', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        maxEntries: 3,
        onEvict: (key, _) => evicted.add(key),
      );
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;
      cache['a'] = 10;
      expect(cache.keys, ['b', 'c', 'a']);
      expect(cache.peek('a'), 10);
      expect(evicted, isEmpty, reason: 'a replacement is not an eviction');
    });

    test('a cached null is a hit, not a miss', () {
      final cache = LruCache<String, int?>(maxEntries: 4);
      var builds = 0;
      int? build() {
        builds++;
        return null;
      }

      expect(cache.putIfAbsent('unnamed', build), isNull);
      expect(cache.putIfAbsent('unnamed', build), isNull);
      expect(cache.putIfAbsent('unnamed', build), isNull);
      expect(builds, 1, reason: 'null must be remembered as the answer');
      expect(cache.containsKey('unnamed'), isTrue);
      expect(cache.length, 1);
    });

    test('a read of a cached null still promotes it', () {
      final cache = LruCache<String, int?>(maxEntries: 2);
      cache['none'] = null;
      cache['b'] = 2;
      cache.putIfAbsent('none', () => 99);
      cache['c'] = 3;
      expect(cache.keys, ['none', 'c']);
      expect(cache.peek('none'), isNull);
    });

    test('putIfAbsent builds once per key and promotes on a hit', () {
      final cache = LruCache<String, int>(maxEntries: 3);
      var builds = 0;
      int build() => ++builds;
      cache
        ..putIfAbsent('a', build)
        ..putIfAbsent('b', build)
        ..putIfAbsent('c', build)
        ..putIfAbsent('a', build)
        ..putIfAbsent('d', build);
      expect(builds, 4);
      expect(cache.keys, ['c', 'a', 'd']);
    });

    group('weight bound', () {
      LruCache<String, List<int>> lines({int maxEntries = 10, int max = 10}) =>
          LruCache<String, List<int>>(
            maxEntries: maxEntries,
            maxWeight: max,
            weigh: (lines) => lines.length,
          );

      test('evicts by total weight when it binds before the entry count', () {
        final cache = lines();
        cache['a'] = List.filled(4, 0);
        cache['b'] = List.filled(4, 0);
        cache['c'] = List.filled(4, 0);
        expect(cache.keys, ['b', 'c']);
        expect(cache.totalWeight, 8);
      });

      test('keeps the newest entry even when it alone exceeds the bound', () {
        final cache = lines();
        cache['small'] = List.filled(2, 0);
        cache['huge'] = List.filled(500, 0);
        expect(cache.keys, ['huge']);
        expect(cache.totalWeight, 500);
      });

      test('weighs values as they are now, not as they were inserted', () {
        final cache = lines();
        final growing = <int>[];
        cache['grows'] = growing;
        cache['b'] = List.filled(2, 0);
        growing.addAll(List.filled(9, 0));
        expect(cache.totalWeight, 11, reason: 'over, but only on insert');
        cache['c'] = List.filled(1, 0);
        expect(
          cache.keys,
          ['b', 'c'],
          reason: 'the grown entry is the one that weighed the cache over',
        );
      });

      test('the entry bound still applies', () {
        final cache = lines(maxEntries: 2, max: 1000);
        cache['a'] = [1];
        cache['b'] = [2];
        cache['c'] = [3];
        expect(cache.keys, ['b', 'c']);
      });

      test('totalWeight is the entry count without a weigh function', () {
        final cache = LruCache<int, int>(maxEntries: 5);
        cache[1] = 1;
        cache[2] = 2;
        expect(cache.totalWeight, 2);
      });
    });

    group('onEvict', () {
      test('receives each evicted entry after it has left the cache', () {
        late LruCache<String, int> cache;
        final seen = <String>[];
        cache = LruCache<String, int>(
          maxEntries: 1,
          onEvict: (key, value) {
            seen.add('$key=$value');
            expect(cache.containsKey(key), isFalse);
          },
        );
        cache['a'] = 1;
        cache['b'] = 2;
        expect(seen, ['a=1']);
      });

      test('is not called by remove, which hands the value back', () {
        final seen = <String>[];
        final cache = LruCache<String, int>(
          maxEntries: 3,
          onEvict: (key, _) => seen.add(key),
        );
        cache['a'] = 1;
        expect(cache.remove('a'), 1);
        expect(cache.remove('a'), isNull);
        expect(seen, isEmpty);
        expect(cache.evictionCount, 0);
      });

      test('is called for every entry by clear', () {
        final seen = <String>[];
        final cache = LruCache<String, int>(
          maxEntries: 3,
          onEvict: (key, _) => seen.add(key),
        );
        cache['a'] = 1;
        cache['b'] = 2;
        cache.clear();
        expect(cache.isEmpty, isTrue);
        expect(seen, ['a', 'b']);
        expect(cache.evictionCount, 0, reason: 'clear is not an eviction');
      });
    });

    group('isPinned', () {
      test('skips a pinned entry and evicts the next candidate', () {
        final cache = LruCache<String, int>(
          maxEntries: 2,
          isPinned: (key, _) => key == 'live',
        );
        cache['live'] = 1;
        cache['b'] = 2;
        cache['c'] = 3;
        expect(cache.keys, ['live', 'c']);
      });

      test(
        'leaves the cache over its bounds when every candidate is pinned',
        () {
          final cache = LruCache<String, int>(
            maxEntries: 1,
            isPinned: (_, _) => true,
          );
          cache['a'] = 1;
          cache['b'] = 2;
          cache['c'] = 3;
          expect(cache.length, 3);
          expect(cache.evictionCount, 0);
        },
      );

      test('a pin asked at eviction time sees the value as it is now', () {
        final pinned = <String>{'a'};
        final cache = LruCache<String, int>(
          maxEntries: 1,
          isPinned: (key, _) => pinned.contains(key),
        );
        cache['a'] = 1;
        cache['b'] = 2;
        expect(cache.keys, ['a', 'b'], reason: 'a pinned, b newest');
        pinned.clear();
        cache['c'] = 3;
        expect(cache.keys, ['c'], reason: 'unpinned a and then b went');
      });
    });

    test('views and counters', () {
      final cache = LruCache<String, int>(maxEntries: 5);
      expect(cache.isEmpty, isTrue);
      expect(cache.isNotEmpty, isFalse);
      cache['a'] = 1;
      cache['b'] = 2;
      expect(cache.isNotEmpty, isTrue);
      expect(cache.values, [1, 2]);
      expect(
        cache.entries.map((e) => '${e.key}${e.value}'),
        ['a1', 'b2'],
      );
      expect(cache.toString(), 'LruCache(2/5 entries)');
      final weighed = LruCache<String, String>(
        maxEntries: 5,
        maxWeight: 100,
        weigh: (s) => s.length,
      );
      weighed['k'] = 'four';
      expect(weighed.toString(), 'LruCache(1/5 entries, 4/100 weight)');
    });

    test('rejects a bound the cache could never satisfy', () {
      expect(
        () => LruCache<String, int>(maxEntries: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => LruCache<String, int>(maxEntries: 1, maxWeight: 10),
        throwsA(isA<AssertionError>()),
        reason: 'a weight bound needs a weigh function',
      );
      expect(
        () => LruCache<String, int>(
          maxEntries: 1,
          maxWeight: 0,
          weigh: (_) => 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
