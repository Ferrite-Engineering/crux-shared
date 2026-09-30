// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseBadgeStringsEn', () {
    test('returns English labels for every tier surface', () {
      const strings = LicenseBadgeStringsEn();

      expect(strings.tierBadgePro, 'PRO');
      expect(strings.tierBadgeProSemantic, 'Pro tier feature');
      expect(strings.tierBadgeEnterprise, 'ENT');
      expect(strings.tierBadgeEnterpriseSemantic, 'Enterprise tier feature');
      expect(strings.tierBadgeEdu, 'EDU');
      expect(strings.tierBadgeEduSemantic, 'Educational license');
    });
  });
}
