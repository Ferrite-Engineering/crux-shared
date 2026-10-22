// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cruxAnnotationStatusOf', () {
    test('an anchor on no single element is unanchored, whatever else', () {
      expect(
        cruxAnnotationStatusOf(
          anchoredToElement: false,
          existsInFile: false,
          isDisplayed: false,
          witnessMatches: false,
        ),
        CruxAnnotationStatus.unanchoredToRow,
      );
    });

    test('a missing element outranks a hidden one', () {
      expect(
        cruxAnnotationStatusOf(
          anchoredToElement: true,
          existsInFile: false,
          isDisplayed: false,
        ),
        CruxAnnotationStatus.unresolved,
      );
    });

    test('a hidden element outranks drift', () {
      expect(
        cruxAnnotationStatusOf(
          anchoredToElement: true,
          existsInFile: true,
          isDisplayed: false,
          witnessMatches: false,
        ),
        CruxAnnotationStatus.orphaned,
      );
    });

    test('a displayed element that disagrees with its witness is drifted', () {
      expect(
        cruxAnnotationStatusOf(
          anchoredToElement: true,
          existsInFile: true,
          isDisplayed: true,
          witnessMatches: false,
        ),
        CruxAnnotationStatus.drifted,
      );
    });

    test('agreement, or nothing to compare, is resolved', () {
      for (final matches in <bool?>[true, null]) {
        expect(
          cruxAnnotationStatusOf(
            anchoredToElement: true,
            existsInFile: true,
            isDisplayed: true,
            witnessMatches: matches,
          ),
          CruxAnnotationStatus.resolved,
          reason: 'witnessMatches: $matches',
        );
      }
    });
  });

  test('only orphaned and unresolved notes are left off the canvas', () {
    expect(
      <CruxAnnotationStatus, bool>{
        for (final s in CruxAnnotationStatus.values) s: s.isDrawable,
      },
      <CruxAnnotationStatus, bool>{
        CruxAnnotationStatus.resolved: true,
        CruxAnnotationStatus.drifted: true,
        CruxAnnotationStatus.orphaned: false,
        CruxAnnotationStatus.unresolved: false,
        CruxAnnotationStatus.unanchoredToRow: true,
      },
    );
  });

  test('the value names stay the ones the persisted exports use', () {
    expect(CruxAnnotationStatus.values.map((s) => s.name), <String>[
      'resolved',
      'drifted',
      'orphaned',
      'unresolved',
      'unanchoredToRow',
    ]);
  });

  group('cruxGroupByStatus', () {
    test('partitions in input order, unknown status counting as displayed', () {
      final statuses = <String, CruxAnnotationStatus?>{
        'a': CruxAnnotationStatus.resolved,
        'b': CruxAnnotationStatus.orphaned,
        'c': CruxAnnotationStatus.unresolved,
        'd': CruxAnnotationStatus.drifted,
        'e': null,
        'f': CruxAnnotationStatus.orphaned,
        'g': CruxAnnotationStatus.unanchoredToRow,
      };
      final groups = cruxGroupByStatus(statuses.keys, (k) => statuses[k]);
      expect(groups.displayed, <String>['a', 'd', 'e', 'g']);
      expect(groups.orphaned, <String>['b', 'f']);
      expect(groups.unresolved, <String>['c']);
      expect(groups.isEmpty, isFalse);
    });

    test('an empty input is empty', () {
      expect(cruxGroupByStatus(<int>[], (_) => null).isEmpty, isTrue);
    });
  });

  test('the drift colour is the amber both products already use', () {
    expect(kCruxAnnotationDriftedColor.toARGB32(), 0xFFE8A33D);
  });
}
