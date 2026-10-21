// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A set of shell-style wildcards selecting metric names, as upstream
/// LibreLane's `Filter`: a name is selected when it matches at least one
/// allow wildcard and no deny wildcard. A wildcard starting with `!` denies.
///
/// Wildcards follow Python's `fnmatch` on a POSIX host: `*` matches any run
/// of characters, `?` one character, `[abc]` and `[a-z]` a set, `[!abc]` its
/// complement, and matching is case-sensitive.
@immutable
class MetricFilter {
  /// A filter of [wildcards].
  MetricFilter(this.wildcards)
    : _allow = [
        for (final w in wildcards)
          if (!w.startsWith('!')) _compile(w),
      ],
      _deny = [
        for (final w in wildcards)
          if (w.startsWith('!')) _compile(w.substring(1)),
      ];

  /// Selects every metric: upstream `MetricDiff.from_metrics`' default.
  static final MetricFilter all = MetricFilter(const ['*']);

  /// The wildcards upstream `compare.py` uses when given none
  /// (`default_filter_set`), the set its `compare` command applies by
  /// default.
  static const List<String> compareDefaultWildcards = [
    'design__*__area',
    'design__max_*',
    'design__lvs_error__count',
    'antenna__violating*',
    'clock__*',
    'ir__*',
    'power__*',
    'timing__*_vio__*',
    'timing*wns*',
    'timing*tns*',
    '*error*',
    '!*__iter:*',
  ];

  /// [compareDefaultWildcards] as a filter.
  static final MetricFilter compareDefaults = MetricFilter(
    compareDefaultWildcards,
  );

  /// The wildcards, as given.
  final List<String> wildcards;

  final List<RegExp> _allow;
  final List<RegExp> _deny;

  /// Whether [name] is selected.
  bool matches(String name) =>
      _allow.any((r) => r.hasMatch(name)) &&
      !_deny.any((r) => r.hasMatch(name));

  /// The selected names of [names], in order.
  Iterable<String> filter(Iterable<String> names) => names.where(matches);

  /// Python's `fnmatch.translate`, for the subset of the grammar it defines.
  static RegExp _compile(String pattern) {
    final out = StringBuffer('^');
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      i++;
      if (c == '*') {
        out.write('.*');
      } else if (c == '?') {
        out.write('.');
      } else if (c == '[') {
        var j = i;
        if (j < pattern.length && pattern[j] == '!') j++;
        if (j < pattern.length && pattern[j] == ']') j++;
        while (j < pattern.length && pattern[j] != ']') {
          j++;
        }
        if (j >= pattern.length) {
          out.write(r'\[');
        } else {
          // A `]` first in the set is a member; a JavaScript-style class
          // needs it escaped, where Python's does not.
          var body = pattern
              .substring(i, j)
              .replaceAll(r'\', r'\\')
              .replaceAll(']', r'\]');
          i = j + 1;
          if (body.startsWith('!')) {
            body = '^${body.substring(1)}';
          } else if (body.startsWith('^')) {
            body = '\\$body';
          }
          out.write('[$body]');
        }
      } else {
        out.write(RegExp.escape(c));
      }
    }
    out.write(r'$');
    return RegExp(out.toString(), dotAll: true);
  }

  @override
  bool operator ==(Object other) =>
      other is MetricFilter &&
      other.wildcards.length == wildcards.length &&
      other.wildcards.indexed.every((e) => wildcards[e.$1] == e.$2);

  @override
  int get hashCode => Object.hashAll(wildcards);

  @override
  String toString() => 'MetricFilter($wildcards)';
}
