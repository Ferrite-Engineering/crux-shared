// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

void main() {
  group('wildcards match as Python fnmatch does', () {
    // (name, wildcard, Python's fnmatch.fnmatchcase result).
    const cases = [
      ('timing__setup__ws', 'timing__*', true),
      ('timing__setup__ws', 'timing__?etup__ws', true),
      ('a1', 'a[0-9]', true),
      ('ab', 'a[0-9]', false),
      ('ab', 'a[!0-9]', true),
      ('a1', 'a[!0-9]', false),
      ('a[', 'a[', true),
      ('a[b', 'a[b', true),
      ('a.b', 'a.b', true),
      ('axb', 'a.b', false),
      ('a]', 'a[]]', true),
      ('a^', 'a[^]', true),
      ('a!', 'a[!!]', false),
      ('Timing__x', 'timing__*', false),
      ('a\nb', 'a*b', true),
      ('a+b', 'a+b', true),
      ('route__drc_errors__iter:2', '*__iter:*', true),
      ('a-', 'a[-]', true),
    ];
    for (final (name, wildcard, expected) in cases) {
      test('${name.replaceAll('\n', r'\n')} ~ $wildcard', () {
        expect(MetricFilter([wildcard]).matches(name), expected);
      });
    }
  });

  test('allow needs one match and deny overrides it', () {
    final filter = MetricFilter(const ['route__*', '!*__iter:*']);
    expect(filter.matches('route__drc_errors'), isTrue);
    expect(filter.matches('route__drc_errors__iter:3'), isFalse);
    expect(filter.matches('timing__setup__ws'), isFalse);
    expect(MetricFilter(const ['!x']).matches('y'), isFalse);
    expect(
      filter.filter(['route__a', 'x', 'route__b__iter:1']).toList(),
      ['route__a'],
    );
  });

  test('the defaults are upstream compare.py default_filter_set', () {
    expect(MetricFilter.compareDefaultWildcards, hasLength(12));
    expect(MetricFilter.compareDefaults.wildcards.last, '!*__iter:*');
    final f = MetricFilter.compareDefaults;
    expect(f.matches('design__core__area'), isTrue);
    expect(f.matches('design__max_slew_violation__count'), isTrue);
    expect(f.matches('timing__hold_vio__count__corner:a'), isTrue);
    expect(f.matches('timing__setup__wns'), isTrue);
    expect(f.matches('route__drc_errors__iter:2'), isFalse);
    expect(f.matches('design__instance__count'), isFalse);
    expect(MetricFilter.all.matches('anything'), isTrue);
  });

  test('value equality over the wildcards', () {
    expect(MetricFilter(const ['a', '!b']), MetricFilter(const ['a', '!b']));
    expect(
      MetricFilter(const ['a']).hashCode,
      MetricFilter(const ['a']).hashCode,
    );
    expect(MetricFilter(const ['a']), isNot(MetricFilter(const ['b'])));
    expect('${MetricFilter(const ['a'])}', contains('a'));
  });
}
