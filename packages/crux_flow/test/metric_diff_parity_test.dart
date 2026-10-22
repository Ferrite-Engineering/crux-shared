// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

const _root = 'test/fixtures/metric_diff';

/// Each capture set: its directory, the pair it compares and the filter
/// upstream's `compare` was given (`-f`).
final _sets = <(String, String, MetricFilter)>[
  ('handbuilt', 'handbuilt', MetricFilter.all),
  ('handbuilt_default', 'handbuilt', MetricFilter.compareDefaults),
];

Map<String, Object?> _metrics(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

void main() {
  test('the captures come from a verified LibreLane release', () {
    expect(File('$_root/VERSION').readAsStringSync().trim(), '3.0.16');
  });

  for (final (name, pair, filter) in _sets) {
    group(name, () {
      for (final verbosity in MetricDiffVerbosity.values) {
        test('${verbosity.name}: byte for byte upstream compare output', () {
          final capture = File('$_root/$name/compare_py.${verbosity.name}.md');
          expect(
            capture.existsSync(),
            isTrue,
            reason: '${capture.path} missing',
          );
          final diff = MetricDiff.fromMetrics(
            _metrics('$_root/$pair/gold.metrics.json'),
            _metrics('$_root/$pair/new.metrics.json'),
            filter: filter,
          );
          // `print` adds the trailing newline.
          expect(
            '${diff.renderMarkdown(verbosity)}\n',
            capture.readAsStringSync(),
          );
        });
      }
    });
  }
}
