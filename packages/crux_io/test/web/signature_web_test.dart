// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'dart:math';

import 'package:crux_io/crux_io.dart';
import 'package:test/test.dart';

import '../signature_vectors.dart';

/// Signatures in a browser, where an `int` is a 53-bit double: the limb
/// arithmetic exists so a web build computes exactly what the VM does, and
/// this is the one place that is executed.
///
/// Runs only under `dart test -p chrome test/web`, which CI invokes as its own
/// step.
void main() {
  test('every shipped signature, as on the VM', () {
    for (final (i, (row, expected)) in shippedSignatures.indexed) {
      expect(
        CruxSignature.compute([row[0], row[1]], shippedText(i)),
        expected,
        reason: 'shipped case $i',
      );
    }
  });

  test('agrees with a BigInt oracle over the whole code-unit space', () {
    final random = Random(0x5EB);
    for (var i = 0; i < 300; i++) {
      final input = String.fromCharCodes([
        for (var j = random.nextInt(48); j > 0; j--) random.nextInt(0x10000),
      ]);
      expect(
        cruxFnv1a64(input),
        referenceFnv1a64(input),
        reason: 'iteration $i',
      );
    }
  });
}
