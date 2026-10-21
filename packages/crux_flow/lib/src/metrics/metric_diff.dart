// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_flow/src/metrics/exact_decimal.dart';
import 'package:crux_flow/src/metrics/metric_definition.dart';
import 'package:crux_flow/src/metrics/metric_filter.dart';
import 'package:crux_flow/src/metrics/metric_key.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:meta/meta.dart';

/// How much of a comparison to list, as upstream LibreLane's
/// `TableVerbosity`: each level lists everything the one before it does.
enum MetricDiffVerbosity {
  /// Changes to critical metrics only.
  critical,

  /// Those, and changes for the worse.
  worse,

  /// Those, and every other change.
  changed,

  /// Every compared metric, changed or not.
  all,
}

/// The group a compared metric falls in, in listing order.
enum MetricChangeClass {
  /// A critical metric whose value differs.
  critical,

  /// A change for the worse.
  worse,

  /// Any other change.
  changed,

  /// No change.
  unchanged,
}

/// One metric compared between a reference run and a new one, following
/// upstream LibreLane's `Metric.compare`.
@immutable
class MetricComparison {
  const MetricComparison._({
    required this.key,
    required this.gold,
    required this.current,
    required this.delta,
    required this.deltaPercent,
    required this.better,
    required this.critical,
    required this.changed,
    required this.formattedGold,
    required this.formattedCurrent,
    required this.formattedDelta,
  });

  /// The metric, as parsed from its name.
  final MetricKey key;

  /// The metric's name, rebuilt from [key]: upstream's `modified_name`.
  String get metricName => key.format();

  /// The reference value, after being converted to the new value's type the
  /// way upstream converts it (a decimal reference against an integer is
  /// truncated).
  final Object? gold;

  /// The new value.
  final Object? current;

  /// `current - gold`, or null unless both are finite numbers.
  final num? delta;

  /// [delta] as a percentage of [gold]; null when [delta] is null, or when
  /// [gold] is zero and [current] is not.
  final num? deltaPercent;

  /// Whether the change is an improvement by the definition's direction.
  /// An unchanged value counts as better, as upstream counts it. Null when
  /// the metric has no direction or the values are not numbers.
  final bool? better;

  /// Whether this is a critical metric whose value differs.
  final bool critical;

  /// Whether the value differs.
  final bool changed;

  /// [gold] as upstream prints it.
  final String formattedGold;

  /// [current] as upstream prints it.
  final String formattedCurrent;

  /// The delta as upstream prints it: the difference, then the percentage
  /// in brackets, or `N/A`.
  final String formattedDelta;

  /// The group this comparison is listed in.
  MetricChangeClass get changeClass {
    if (critical) return MetricChangeClass.critical;
    if (better == false) return MetricChangeClass.worse;
    if (changed) return MetricChangeClass.changed;
    return MetricChangeClass.unchanged;
  }

  @override
  bool operator ==(Object other) =>
      other is MetricComparison &&
      other.key == key &&
      other.formattedGold == formattedGold &&
      other.formattedCurrent == formattedCurrent &&
      other.formattedDelta == formattedDelta &&
      other.better == better &&
      other.critical == critical &&
      other.changed == changed;

  @override
  int get hashCode => Object.hash(
    key,
    formattedGold,
    formattedCurrent,
    formattedDelta,
    better,
    critical,
    changed,
  );

  @override
  String toString() =>
      'MetricComparison($metricName $formattedGold -> $formattedCurrent)';
}

/// Counts over a [MetricDiff], as upstream's `MetricStatistics`.
@immutable
class MetricDiffStatistics {
  /// Creates statistics.
  const MetricDiffStatistics({
    required this.better,
    required this.worse,
    required this.critical,
    required this.unchanged,
  });

  /// Changed values that are improvements.
  final int better;

  /// Changed values that are regressions.
  final int worse;

  /// Critical metrics whose value differs.
  final int critical;

  /// Values that did not change.
  final int unchanged;

  @override
  bool operator ==(Object other) =>
      other is MetricDiffStatistics &&
      other.better == better &&
      other.worse == worse &&
      other.critical == critical &&
      other.unchanged == unchanged;

  @override
  int get hashCode => Object.hash(better, worse, critical, unchanged);

  @override
  String toString() =>
      'MetricDiffStatistics(better $better, worse $worse, '
      'critical $critical, unchanged $unchanged)';
}

/// The comparison of two runs' metrics, with upstream LibreLane
/// `compare.py` semantics.
///
/// Every metric present in both runs, selected by the filter, and defined
/// in the table is compared; the rest are ignored, as upstream ignores them.
/// Arithmetic is decimal, as upstream's is, so deltas print the digits a
/// person expects rather than binary rounding noise.
@immutable
class MetricDiff {
  const MetricDiff._(this.comparisons);

  /// Compares [current] against [gold].
  ///
  /// [significantFigures] is upstream's option of that name, which sets the
  /// digits printed after the decimal point.
  factory MetricDiff.fromMetrics(
    Map<String, Object?> gold,
    Map<String, Object?> current, {
    MetricDefinitionTable? table,
    MetricFilter? filter,
    int significantFigures = 4,
  }) {
    final definitions = table ?? librelaneMetricsV1;
    final selected = filter ?? MetricFilter.all;
    final names = current.keys.toList()..sort();
    final comparisons = <MetricComparison>[];
    for (final name in selected.filter(names)) {
      if (!gold.containsKey(name)) continue;
      final key = MetricKey.tryParse(name);
      if (key == null) continue;
      final definition = definitions[key.base];
      if (definition == null) continue;
      final rhs = _Value.of(current[name]);
      final lhs = _Value.of(gold[name]).convertedTo(rhs);
      comparisons.add(_compare(definition, key, lhs, rhs, significantFigures));
    }
    return MetricDiff._(List.unmodifiable(comparisons));
  }

  /// Every comparison, in metric-name order.
  final List<MetricComparison> comparisons;

  /// The counts upstream reports.
  MetricDiffStatistics get statistics {
    var better = 0;
    var worse = 0;
    var critical = 0;
    var unchanged = 0;
    for (final c in comparisons) {
      if (!c.changed) {
        unchanged++;
      } else if (c.better != null) {
        if (c.better!) {
          better++;
        } else {
          worse++;
        }
      }
      if (c.critical) critical++;
    }
    return MetricDiffStatistics(
      better: better,
      worse: worse,
      critical: critical,
      unchanged: unchanged,
    );
  }

  /// The comparisons [verbosity] lists, in upstream's table order: sorted by
  /// `corner` modifier and then base name, then grouped critical, worse,
  /// changed and unchanged.
  List<MetricComparison> listed(MetricDiffVerbosity verbosity) {
    final indexed = comparisons.indexed.toList()
      ..sort((a, b) {
        final byCorner = (a.$2.key.modifier('corner') ?? '').compareTo(
          b.$2.key.modifier('corner') ?? '',
        );
        if (byCorner != 0) return byCorner;
        final byBase = a.$2.key.base.compareTo(b.$2.key.base);
        if (byBase != 0) return byBase;
        return a.$1.compareTo(b.$1);
      });
    final sorted = [for (final e in indexed) e.$2];
    final shown = switch (verbosity) {
      MetricDiffVerbosity.critical => const {MetricChangeClass.critical},
      MetricDiffVerbosity.worse => const {
        MetricChangeClass.critical,
        MetricChangeClass.worse,
      },
      MetricDiffVerbosity.changed => const {
        MetricChangeClass.critical,
        MetricChangeClass.worse,
        MetricChangeClass.changed,
      },
      MetricDiffVerbosity.all => MetricChangeClass.values.toSet(),
    };
    return [
      for (final group in MetricChangeClass.values)
        if (shown.contains(group))
          ...sorted.where((c) => c.changeClass == group),
    ];
  }

  /// The Markdown table upstream's `compare` command prints for
  /// [verbosity], byte for byte, or an empty string when nothing is listed.
  String renderMarkdown(MetricDiffVerbosity verbosity) {
    final rows = listed(verbosity);
    if (rows.isEmpty) return '';
    final out = StringBuffer()
      ..write('\n')
      ..write(
        '| ${'Metric'.padRight(70)} | ${'Before'.padRight(10)} | '
        '${'After'.padRight(10)} | ${'Delta'.padRight(20)} |\n',
      )
      ..write(
        '| ${'-'.padRight(70)} | ${'-'.padRight(10)} | '
        '${'-'.padRight(10)} | ${'-'.padRight(20)} |\n',
      );
    for (final row in rows) {
      var mark = '';
      if (row.better != null) mark = row.better! ? ' ⭕' : ' ❗';
      if (row.critical && row.changed) mark = ' ‼️';
      out.write(
        '| ${row.metricName.padRight(70)} | '
        '${row.formattedGold.padRight(10)} | '
        '${row.formattedCurrent.padRight(10)} | '
        '${'${row.formattedDelta}$mark'.padRight(20)} |\n',
      );
    }
    return out.toString();
  }
}

/// A value as upstream holds it after `json.load(parse_float=Decimal)`: an
/// integer, a decimal, or anything else.
sealed class _Value {
  const _Value();

  factory _Value.of(Object? raw) => switch (raw) {
    final int i => _Int(i),
    final double d when d.isFinite => _Decimal(ExactDecimal.fromJsonDouble(d)),
    _ => _Other(raw),
  };

  /// Upstream's `type(rhs)(lhs)` when the two types differ: a decimal
  /// against an integer is truncated, an integer against a decimal widened,
  /// and anything against a string or a boolean converted to one. Other
  /// mismatches raise upstream; they are left as they are here.
  _Value convertedTo(_Value rhs) {
    final self = this;
    return switch (rhs) {
      _Int() when self is _Decimal => _Int(self.value.truncateToInt()),
      _Decimal() when self is _Int => _Decimal(
        ExactDecimal.fromInt(self.value),
      ),
      _Other(raw: String()) when self is! _Other || self.raw is! String =>
        _Other(_text),
      _Other(raw: bool()) when self is! _Other || self.raw is! bool => _Other(
        _truthy,
      ),
      _ => self,
    };
  }

  String get _text;

  bool get _truthy;

  /// Upstream's `gold == new` after [convertedTo], which leaves an integer
  /// and a decimal never facing each other.
  bool sameAs(_Value other) => switch ((this, other)) {
    (final _Int a, final _Int b) => a.value == b.value,
    (final _Decimal a, final _Decimal b) => a.value.compareTo(b.value) == 0,
    (final _Other a, final _Other b) => _deepEqual(a.raw, b.raw),
    _ => false,
  };

  /// The value as upstream's `format_values` prints it.
  String formatted(int places);

  /// The value handed back to callers.
  Object? get public;
}

final class _Int extends _Value {
  const _Int(this.value);

  final int value;

  @override
  String get _text => '$value';

  @override
  bool get _truthy => value != 0;

  @override
  String formatted(int places) => '$value';

  @override
  Object get public => value;
}

final class _Decimal extends _Value {
  const _Decimal(this.value);

  final ExactDecimal value;

  @override
  String get _text => value.toDouble().toString();

  @override
  bool get _truthy => !value.isZero;

  @override
  String formatted(int places) => value.toFixed(places);

  @override
  Object get public => value.toDouble();
}

final class _Other extends _Value {
  const _Other(this.raw);

  final Object? raw;

  @override
  String get _text => _python(raw);

  @override
  bool get _truthy => _isTruthy(raw);

  @override
  String formatted(int places) => _python(raw);

  @override
  Object? get public => raw;
}

bool _isTruthy(Object? raw) => switch (raw) {
  null => false,
  final bool b => b,
  final num n => n != 0,
  final String s => s.isNotEmpty,
  final List<Object?> l => l.isNotEmpty,
  final Map<Object?, Object?> m => m.isNotEmpty,
  _ => true,
};

bool _deepEqual(Object? a, Object? b) => deepEquals(a, b);

/// Python's `str()` of a decoded JSON value, near enough for a value that
/// is not a number: a list or object prints as JSON.
String _python(Object? raw) => switch (raw) {
  null => 'None',
  true => 'True',
  false => 'False',
  final String s => s,
  final double d when d.isNaN => 'nan',
  final double d when d.isInfinite => d.isNegative ? '-inf' : 'inf',
  _ => jsonEncode(raw, toEncodable: (o) => '$o'),
};

MetricComparison _compare(
  MetricDefinition definition,
  MetricKey key,
  _Value gold,
  _Value current,
  int places,
) {
  final differs = !gold.sameAs(current);
  final critical = definition.critical && differs;
  num? delta;
  num? deltaPercent;
  bool? better;
  var deltaText = 'N/A';
  var deltaIsNonZero = false;

  switch ((gold, current)) {
    case (_Int(value: final g), _Int(value: final n)):
      final d = n - g;
      delta = d;
      deltaIsNonZero = d != 0;
      deltaText = '$d';
      ExactDecimal? pct;
      if (g == 0) {
        if (n == 0) pct = ExactDecimal.fromInt(0);
      } else {
        // Upstream divides two Python ints: true division in binary floating
        // point, then Decimal() of that float, exactly.
        pct = ExactDecimal.fromDoubleExact((d / g) * 100);
        if (pct.isZero) pct = ExactDecimal.fromInt(0);
      }
      if (pct != null) {
        deltaPercent = pct.toDouble();
        deltaText = '$deltaText (${_percent(pct, places)}%)';
      }
      better = _better(definition, d.sign);
    case (_Decimal(value: final g), _Decimal(value: final n)):
      final d = n - g;
      delta = d.toDouble();
      deltaIsNonZero = !d.isZero;
      deltaText = d.toFixed(places);
      ExactDecimal? pct;
      if (g.isZero) {
        if (n.isZero) pct = ExactDecimal.fromInt(0);
      } else {
        pct = d.dividedBy(g).timesInt(100);
        if (pct.isZero) pct = ExactDecimal.fromInt(0);
      }
      if (pct != null) {
        deltaPercent = pct.toDouble();
        deltaText = '$deltaText (${_percent(pct, places)}%)';
      }
      better = _better(definition, d.isZero ? 0 : (d.isNegative ? -1 : 1));
    default:
      // Not two numbers. Upstream raises for a metric that has a direction;
      // the comparison is kept here without a delta instead.
      break;
  }

  return MetricComparison._(
    key: key,
    gold: gold.public,
    current: current.public,
    delta: delta,
    deltaPercent: deltaPercent,
    better: better,
    critical: critical,
    changed: deltaIsNonZero || differs,
    formattedGold: gold.formatted(places),
    formattedCurrent: current.formatted(places),
    formattedDelta: deltaText,
  );
}

bool? _better(MetricDefinition definition, int deltaSign) =>
    switch (definition.higherIsBetter) {
      null => null,
      true => deltaSign >= 0,
      false => deltaSign <= 0,
    };

String _percent(ExactDecimal pct, int places) {
  final text = pct.toFixed(places);
  return pct.compareTo(ExactDecimal.fromInt(0)) > 0 ? '+$text' : text;
}
