// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The core entry point is what domain models and headless builds import, so
/// nothing it reaches may import `dart:ui` or Flutter.
void main() {
  test('the core entry point reaches no dart:ui or Flutter import', () {
    final lib = Directory('lib');
    final pending = <String>['crux_annotations_core.dart'];
    final seen = <String>{};
    final offenders = <String>[];
    final directive = RegExp(
      "^(?:import|export) '([^']+)';",
      multiLine: true,
    );
    while (pending.isNotEmpty) {
      final relative = pending.removeLast();
      if (!seen.add(relative)) continue;
      final source = File('${lib.path}/$relative').readAsStringSync();
      final dir = relative.contains('/')
          ? relative.substring(0, relative.lastIndexOf('/'))
          : '';
      for (final match in directive.allMatches(source)) {
        final uri = match.group(1)!;
        if (uri == 'dart:ui' || uri.startsWith('package:flutter/')) {
          offenders.add('$relative -> $uri');
        } else if (uri.startsWith('package:crux_annotations/')) {
          pending.add(uri.substring('package:crux_annotations/'.length));
        } else if (!uri.contains(':')) {
          pending.add(dir.isEmpty ? uri : '$dir/$uri');
        }
      }
    }
    expect(offenders, isEmpty);
    expect(seen, contains('src/status.dart'));
  });

  test('the core names resolve without a binding', () {
    expect(
      cruxAnnotationStatusOf(
        anchoredToElement: true,
        existsInFile: true,
        isDisplayed: true,
      ),
      CruxAnnotationStatus.resolved,
    );
    expect(const CruxCalloutPlacement().isDefault, isTrue);
    expect(kCruxAnnotationWitnessKey, 'witness');
  });
}
