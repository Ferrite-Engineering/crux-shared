// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults satisfy the suite 44 dp touch-target floor', () {
    const metrics = CruxUpdateBannerMetrics();
    expect(metrics.touchTarget, greaterThanOrEqualTo(44));
    expect(metrics.iconSize, greaterThan(0));
    expect(metrics.bodyFontSize, greaterThan(0));
  });

  test('copyWith replaces only the named fields', () {
    const base = CruxUpdateBannerMetrics();
    final copy = base.copyWith(touchTarget: 56);
    expect(copy.touchTarget, 56);
    expect(copy.iconSize, base.iconSize);
    expect(copy.bodyFontSize, base.bodyFontSize);
    expect(base.copyWith(), base);
  });

  test('value equality', () {
    expect(
      const CruxUpdateBannerMetrics(),
      const CruxUpdateBannerMetrics(),
    );
    expect(
      const CruxUpdateBannerMetrics().hashCode,
      const CruxUpdateBannerMetrics().hashCode,
    );
    expect(
      const CruxUpdateBannerMetrics(touchTarget: 56),
      isNot(const CruxUpdateBannerMetrics()),
    );
  });

  test('toString names every dimension', () {
    const metrics = CruxUpdateBannerMetrics(
      touchTarget: 56,
      iconSize: 24,
      bodyFontSize: 16,
    );
    expect(metrics.toString(), contains('56'));
    expect(metrics.toString(), contains('24'));
    expect(metrics.toString(), contains('16'));
  });
}
