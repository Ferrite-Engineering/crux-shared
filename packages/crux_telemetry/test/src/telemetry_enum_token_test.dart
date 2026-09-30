// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `Enum` → telemetry-token bridge.
///
/// The ingestion Worker's property-value class has no capitals, so a Dart
/// enum's `lowerCamelCase` name cannot be sent as-is; it is dropped, silently,
/// leaving the event with one fewer dimension than the catalog claims.
///
/// Each product asserts its **own** instrumented enums against the value class
/// (that is a catalog question, and the catalog is per-product). What is
/// asserted here is the transformation itself.
enum _Shapes {
  plain,
  twoWords,
  ieee754Single,
  fixedPointQ,
  htmlParser,
  parseHTMLDoc,
  lxt2,
}

void main() {
  final valueClass = RegExp(r'^[a-z0-9_]{1,64}$');

  test('splits camel humps and digit-adjacent capitals', () {
    expect(telemetryEnumToken(_Shapes.plain), 'plain');
    expect(telemetryEnumToken(_Shapes.twoWords), 'two_words');
    expect(telemetryEnumToken(_Shapes.ieee754Single), 'ieee754_single');
    expect(telemetryEnumToken(_Shapes.fixedPointQ), 'fixed_point_q');
    expect(telemetryEnumToken(_Shapes.htmlParser), 'html_parser');
  });

  test('breaks an acronym run at the reader"s word boundary', () {
    // `parseHTMLDoc` splits before `Doc`, not mid-acronym.
    expect(telemetryEnumToken(_Shapes.parseHTMLDoc), 'parse_html_doc');
  });

  test('leaves an already-lowercase name alone', () {
    expect(telemetryEnumToken(_Shapes.lxt2), 'lxt2');
  });

  test('every token passes the Worker property-value class', () {
    for (final value in _Shapes.values) {
      expect(
        telemetryEnumToken(value),
        matches(valueClass),
        reason: '${value.runtimeType}.${value.name} would be dropped',
      );
    }
  });

  test('tokens stay distinct within an enum', () {
    // Snake-casing is many-to-one in principle; two constants collapsing onto
    // one token would silently merge two rows in the dataset.
    final tokens = _Shapes.values.map(telemetryEnumToken).toList();
    expect(tokens.toSet(), hasLength(tokens.length));
  });
}
