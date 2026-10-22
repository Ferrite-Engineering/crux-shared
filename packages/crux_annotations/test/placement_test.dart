// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxCalloutPlacement persistence', () {
    test('defaults write nothing and remove stale keys', () {
      final record = <String, Object?>{
        'id': 'n1',
        'labelDx': 4.0,
        'labelDy': 9.0,
        'collapsed': true,
      };
      const CruxCalloutPlacement().writeInto(record);
      expect(record, <String, Object?>{'id': 'n1'});
      expect(const CruxCalloutPlacement().isDefault, isTrue);
    });

    test('non-defaults use the keys WaveCrux documents already carry', () {
      final record = <String, Object?>{'id': 'n1'};
      const CruxCalloutPlacement(
        labelDx: 12.5,
        labelDy: -48,
        collapsed: true,
      ).writeInto(record);
      expect(
        jsonEncode(record),
        '{"id":"n1","labelDx":12.5,"labelDy":-48.0,"collapsed":true}',
      );
    });

    test('round-trips', () {
      const placement = CruxCalloutPlacement(
        labelDx: -20,
        labelDy: 7,
        collapsed: true,
      );
      final record = <String, Object?>{};
      placement.writeInto(record);
      final decoded = CruxCalloutPlacement.fromJson(
        jsonDecode(jsonEncode(record)) as Map<String, Object?>,
      );
      expect(decoded, placement);
      expect(decoded.hashCode, placement.hashCode);
    });

    test('a record without the fields reads as the default placement', () {
      expect(
        CruxCalloutPlacement.fromJson(const <String, Object?>{'id': 'x'}),
        const CruxCalloutPlacement(),
      );
    });

    test('malformed values read as defaults and never throw', () {
      final placement = CruxCalloutPlacement.fromJson(const <String, Object?>{
        'labelDx': 'left',
        'labelDy': double.nan,
        'collapsed': 'yes',
      });
      expect(placement, const CruxCalloutPlacement());
    });

    test('integer offsets read as doubles', () {
      final placement = CruxCalloutPlacement.fromJson(const <String, Object?>{
        'labelDx': 3,
        'labelDy': -10,
      });
      expect(placement.labelDx, 3.0);
      expect(placement.labelDy, -10.0);
    });
  });

  test('nudging moves the label and keeps the fold', () {
    const placement = CruxCalloutPlacement(collapsed: true);
    final moved = placement.nudged(5, -6);
    expect(moved.labelDx, 5);
    expect(moved.labelDy, CruxCalloutPlacement.defaultLabelDy - 6);
    expect(moved.collapsed, isTrue);
    expect(placement.copyWith(collapsed: false).collapsed, isFalse);
    expect(moved.toString(), contains('collapsed'));
  });
}
