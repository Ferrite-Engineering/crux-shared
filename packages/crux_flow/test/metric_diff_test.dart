// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

// A hand-built pair over metrics from upstream's library.py. The expected
// rows follow upstream compare.py's rules read from its source
// (`Metric.compare`, `MetricComparisonResult.format_values`,
// `MetricDiff.render_md`), and every decimal string was checked with
// Python's own `decimal` module, the arithmetic upstream runs on.
const _gold = <String, Object?>{
  'design__instance__count': 100,
  'design__instance__area': 1234.5,
  'timing__setup__ws__corner:nom_tt': 0.25,
  'timing__setup__ws__corner:max_ss': -0.1,
  'timing__setup_vio__count': 0,
  'route__drc_errors': 0,
  'power__total': 0.0012,
  'design__instance__utilization': 0.4,
  'magic__drc_error__count': 3,
  'unknown__metric': 5,
  'design__die__area': 2500,
  'ir__drop__worst': 0.05,
  'antenna__violating__nets': 2,
};

const _new = <String, Object?>{
  'design__instance__count': 110,
  'design__instance__area': 1234.5,
  'timing__setup__ws__corner:nom_tt': 0.2,
  'timing__setup__ws__corner:max_ss': -0.15,
  'timing__setup_vio__count': 2,
  'route__drc_errors': 0,
  'power__total': 0.0013,
  'design__instance__utilization': 0.5,
  'magic__drc_error__count': 3,
  'unknown__metric': 7,
  'design__die__area': 2500.0,
  'ir__drop__worst': 0,
  'clock__skew__worst_hold': 0.3,
};

/// One table row, as `render_md` lays it out with Python's `:<N` padding.
String _row(String name, String before, String after, String delta) =>
    '| ${name.padRight(70)} | ${before.padRight(10)} | '
    '${after.padRight(10)} | ${delta.padRight(20)} |\n';

final String _header =
    '\n${_row('Metric', 'Before', 'After', 'Delta')}'
    '${_row('-', '-', '-', '-')}';

final List<String> _critical = [
  _row('timing__setup_vio__count', '0', '2', '2 ‼️'),
];

final List<String> _worse = [
  _row('design__instance__count', '100', '110', '10 (+10.0000%) ❗'),
  _row('power__total', '0.0012', '0.0013', '0.0001 (+8.3333%) ❗'),
  _row(
    'timing__setup__ws__corner:max_ss',
    '-0.1000',
    '-0.1500',
    '-0.0500 (+50.0000%) ❗',
  ),
  _row(
    'timing__setup__ws__corner:nom_tt',
    '0.2500',
    '0.2000',
    '-0.0500 (-20.0000%) ❗',
  ),
];

final List<String> _changed = [
  _row(
    'design__instance__utilization',
    '0.4000',
    '0.5000',
    '0.1000 (+25.0000%) ⭕',
  ),
];

final List<String> _unchanged = [
  _row('design__die__area', '2500.0000', '2500.0000', '0.0000 (0.0000%) ⭕'),
  _row(
    'design__instance__area',
    '1234.5000',
    '1234.5000',
    '0.0000 (0.0000%) ⭕',
  ),
  _row('ir__drop__worst', '0', '0', '0 (0.0000%) ⭕'),
  _row('magic__drc_error__count', '3', '3', '0 (0.0000%) ⭕'),
  _row('route__drc_errors', '0', '0', '0 (0.0000%) ⭕'),
];

void main() {
  final diff = MetricDiff.fromMetrics(_gold, _new);

  test('compares only metrics in both runs and in the table', () {
    expect(diff.comparisons.map((c) => c.metricName), [
      'design__die__area',
      'design__instance__area',
      'design__instance__count',
      'design__instance__utilization',
      'ir__drop__worst',
      'magic__drc_error__count',
      'power__total',
      'route__drc_errors',
      'timing__setup__ws__corner:max_ss',
      'timing__setup__ws__corner:nom_tt',
      'timing__setup_vio__count',
    ]);
  });

  test('renders each verbosity as compare.py does', () {
    expect(
      diff.renderMarkdown(MetricDiffVerbosity.critical),
      _header + _critical.join(),
    );
    expect(
      diff.renderMarkdown(MetricDiffVerbosity.worse),
      _header + [..._critical, ..._worse].join(),
    );
    expect(
      diff.renderMarkdown(MetricDiffVerbosity.changed),
      _header + [..._critical, ..._worse, ..._changed].join(),
    );
    expect(
      diff.renderMarkdown(MetricDiffVerbosity.all),
      _header + [..._critical, ..._worse, ..._changed, ..._unchanged].join(),
    );
  });

  test('statistics', () {
    expect(
      diff.statistics,
      const MetricDiffStatistics(
        better: 1,
        worse: 5,
        critical: 1,
        unchanged: 5,
      ),
    );
    expect(diff.statistics.hashCode, diff.statistics.hashCode);
    expect('${diff.statistics}', contains('worse 5'));
  });

  test('per-row values', () {
    MetricComparison row(String name) =>
        diff.comparisons.singleWhere((c) => c.metricName == name);

    final count = row('design__instance__count');
    expect(count.gold, 100);
    expect(count.current, 110);
    expect(count.delta, 10);
    expect(count.deltaPercent, closeTo(10, 1e-9));
    expect(count.better, isFalse);
    expect(count.changeClass, MetricChangeClass.worse);

    final vio = row('timing__setup_vio__count');
    expect(vio.critical, isTrue);
    expect(vio.deltaPercent, isNull, reason: 'gold is zero, new is not');
    expect(vio.changeClass, MetricChangeClass.critical);

    // An integer reference against a decimal is widened.
    final die = row('design__die__area');
    expect(die.gold, 2500.0);
    expect(die.changed, isFalse);
    expect(die.changeClass, MetricChangeClass.unchanged);

    // A decimal reference against an integer is truncated, as upstream's
    // `int(Decimal)` truncates.
    final drop = row('ir__drop__worst');
    expect(drop.gold, 0);
    expect(drop.changed, isFalse);

    // An unchanged value counts as better.
    expect(row('route__drc_errors').better, isTrue);
    expect(
      row('timing__setup__ws__corner:max_ss').key.modifier('corner'),
      'max_ss',
    );
    expect('$count', contains('design__instance__count'));
    expect(count, row('design__instance__count'));
    expect(count.hashCode, row('design__instance__count').hashCode);
  });

  test('listing order: corner, then base, then group', () {
    expect(
      diff.listed(MetricDiffVerbosity.all).map((c) => c.metricName).toList(),
      [
        'timing__setup_vio__count',
        'design__instance__count',
        'power__total',
        'timing__setup__ws__corner:max_ss',
        'timing__setup__ws__corner:nom_tt',
        'design__instance__utilization',
        'design__die__area',
        'design__instance__area',
        'ir__drop__worst',
        'magic__drc_error__count',
        'route__drc_errors',
      ],
    );
  });

  test('nothing listed renders as an empty string', () {
    final same = MetricDiff.fromMetrics(_gold, _gold);
    expect(same.renderMarkdown(MetricDiffVerbosity.changed), '');
    expect(same.listed(MetricDiffVerbosity.critical), isEmpty);
    expect(same.statistics.unchanged, same.comparisons.length);
  });

  test("the compare command's default filter", () {
    final filtered = MetricDiff.fromMetrics(
      _gold,
      _new,
      filter: MetricFilter.compareDefaults,
    );
    expect(filtered.comparisons.map((c) => c.metricName), [
      'design__die__area',
      'design__instance__area',
      'ir__drop__worst',
      'magic__drc_error__count',
      'power__total',
      'route__drc_errors',
      'timing__setup_vio__count',
    ]);
  });

  test('significant figures set the printed decimals', () {
    final two = MetricDiff.fromMetrics(
      const {'power__total': 0.0012},
      const {'power__total': 0.0013},
      significantFigures: 2,
    );
    expect(two.comparisons.single.formattedGold, '0.00');
    expect(two.comparisons.single.formattedDelta, '0.00 (+8.33%)');
  });

  test('values that are not numbers compare without a delta', () {
    final odd = MetricDiff.fromMetrics(
      const {
        'power__total': 'n/a',
        'design__die__area': null,
        'ir__drop__avg': 1,
      },
      const {
        'power__total': 'n/a',
        'design__die__area': 4,
        'ir__drop__avg': 'x',
      },
    );
    final byName = {for (final c in odd.comparisons) c.metricName: c};
    expect(byName['power__total']!.formattedDelta, 'N/A');
    expect(byName['power__total']!.changed, isFalse);
    expect(byName['power__total']!.better, isNull);
    expect(byName['design__die__area']!.formattedGold, 'None');
    expect(byName['design__die__area']!.changed, isTrue);
    // An integer against a string is converted to its text.
    expect(byName['ir__drop__avg']!.formattedGold, '1');
    expect(byName['ir__drop__avg']!.changed, isTrue);
  });

  test('a zero reference and zero new value is a zero percentage', () {
    final zeros = MetricDiff.fromMetrics(
      const {'power__total': 0.0, 'design__instance__count': 5},
      const {'power__total': 0.0, 'design__instance__count': 5},
    );
    expect(
      zeros.comparisons.map((c) => c.formattedDelta),
      ['0 (0.0000%)', '0.0000 (0.0000%)'],
    );
  });

  test('a decimal change from zero has no percentage', () {
    final fromZero = MetricDiff.fromMetrics(
      const {'power__total': 0.0},
      const {'power__total': 0.5},
    );
    expect(fromZero.comparisons.single.formattedDelta, '0.5000');
    expect(fromZero.comparisons.single.deltaPercent, isNull);
  });

  test('booleans convert by truthiness against a boolean', () {
    final flags = MetricDiff.fromMetrics(
      const {'power__total': 1},
      const {'power__total': true},
    );
    expect(flags.comparisons.single.formattedGold, 'True');
    expect(flags.comparisons.single.changed, isFalse);
  });

  test("other values convert to the new value's type", () {
    final conv = MetricDiff.fromMetrics(
      const {
        'power__total': 0.5,
        'design__die__area': 0.0,
        'ir__drop__avg': null,
        'design__core__area': [1, 2],
        'ir__drop__worst': double.infinity,
        'design__instance__count': '',
        'design__instance__area': <Object?>[],
        'antenna__violating__nets': <String, Object?>{},
        'antenna__violating__pins': double.nan,
      },
      const {
        'power__total': 'x',
        'design__die__area': true,
        'ir__drop__avg': 'y',
        'design__core__area': [1, 2],
        'ir__drop__worst': false,
        'design__instance__count': true,
        'design__instance__area': true,
        'antenna__violating__nets': false,
        'antenna__violating__pins': 'z',
      },
    );
    final byName = {for (final c in conv.comparisons) c.metricName: c};
    expect(byName['power__total']!.formattedGold, '0.5');
    expect(byName['design__die__area']!.formattedGold, 'False');
    expect(byName['design__die__area']!.changed, isTrue);
    expect(byName['ir__drop__avg']!.formattedGold, 'None');
    expect(byName['design__core__area']!.formattedGold, '[1,2]');
    expect(byName['design__core__area']!.changed, isFalse);
    expect(byName['ir__drop__worst']!.formattedGold, 'True');
    expect(byName['design__instance__count']!.formattedGold, 'False');
    expect(byName['design__instance__area']!.formattedGold, 'False');
    expect(byName['antenna__violating__nets']!.formattedGold, 'False');
    expect(byName['antenna__violating__nets']!.changed, isFalse);
    expect(byName['antenna__violating__pins']!.formattedGold, 'nan');
  });

  test('rows of one base and corner keep their name order', () {
    final tie = MetricDiff.fromMetrics(
      const {
        'power__total__corner:a__vt:y': 2,
        'power__total__corner:a__vt:x': 1,
      },
      const {
        'power__total__corner:a__vt:y': 2,
        'power__total__corner:a__vt:x': 1,
      },
    );
    expect(
      tie.listed(MetricDiffVerbosity.all).map((c) => c.metricName),
      ['power__total__corner:a__vt:x', 'power__total__corner:a__vt:y'],
    );
  });
}
