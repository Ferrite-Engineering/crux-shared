// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the shipped copy spells "license" the way every product does', () {
    const s = CruxEulaStrings();
    final lines = <String>[
      s.title,
      s.subtitle,
      s.acceptCheckboxLabel,
      s.acceptButton,
      s.declineButton,
      s.openOnline,
      s.openSourceNote,
      s.updatedNotice,
      s.documentLabel,
    ];
    for (final line in lines) {
      expect(line.toLowerCase(), isNot(contains('licence')), reason: line);
    }
    expect(s.openSourceNote, contains('open-source license.'));
  });
}
