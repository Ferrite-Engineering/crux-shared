// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxCalloutGeometry.isCollapsed', () {
    bool collapsed({
      bool isEditing = false,
      bool folded = false,
      bool hasText = true,
      bool alwaysDot = false,
      int expandedSoFar = 0,
    }) => CruxCalloutGeometry.isCollapsed(
      isEditing: isEditing,
      collapsed: folded,
      hasText: hasText,
      alwaysDot: alwaysDot,
      expandedSoFar: expandedSoFar,
    );

    test('a note with text, unfolded and uncrowded, is a balloon', () {
      expect(collapsed(), isFalse);
    });

    test('folded, empty, dot-only or crowded notes are dots', () {
      expect(collapsed(folded: true), isTrue);
      expect(collapsed(hasText: false), isTrue);
      expect(collapsed(alwaysDot: true), isTrue);
      expect(collapsed(expandedSoFar: kCruxCalloutMaxExpanded), isTrue);
      expect(collapsed(expandedSoFar: kCruxCalloutMaxExpanded - 1), isFalse);
    });

    test('the note being edited is always a balloon', () {
      expect(
        collapsed(
          isEditing: true,
          folded: true,
          hasText: false,
          alwaysDot: true,
          expandedSoFar: 99,
        ),
        isFalse,
      );
    });
  });

  test('the label is offset from the anchor and kept off the top edge', () {
    expect(
      CruxCalloutGeometry.labelOrigin(
        const Offset(100, 200),
        labelDx: 10,
        labelDy: -32,
      ),
      const Offset(110, 168),
    );
    expect(
      CruxCalloutGeometry.labelOrigin(
        const Offset(100, 10),
        labelDx: 0,
        labelDy: -32,
      ),
      const Offset(100, kCruxCalloutTopInset),
    );
  });

  test('the leader meets a dot at its centre and a balloon mid first line', () {
    const origin = Offset(40, 50);
    expect(CruxCalloutGeometry.leaderEnd(origin, collapsed: true), origin);
    expect(
      CruxCalloutGeometry.leaderEnd(origin, collapsed: false),
      const Offset(40 + kCruxCalloutBalloonWidth / 2, 66),
    );
  });

  test('three levels of detail', () {
    expect(CruxCalloutDetail.values, hasLength(3));
  });
}
