// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

const _source = '''
// colorScheme.outline in a comment is prose.
const note = 'scheme.outline in a string is text';
Widget a(ColorScheme scheme) => Text('x', style: TextStyle(color: scheme.outline));
Widget b(ThemeData theme) => DecoratedBox(
  decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outline)),
);
final v = scheme.outlineVariant;
final i = Icons.help_outline;
final n = maybe?.outline;
''';

CruxGuardResult _scan(List<CruxOutlineExemption> exemptions) =>
    cruxAuditOutlineText(
      sources: const [CruxGuardSource(path: 'lib/a.dart', source: _source)],
      exemptions: exemptions,
    );

const _border = CruxOutlineExemption(
  file: 'lib/a.dart',
  line: 5,
  expectedTrimmed:
      'decoration: BoxDecoration(border: Border.all(color: '
      'theme.colorScheme.outline)),',
  reason: 'a border',
);

void main() {
  test('every member access is seen, and nothing in prose or another name', () {
    final result = _scan(const []);
    expect(result.matchesSeen, 3);
    expect(result.findings.map((f) => f.line), [3, 5, 9]);
    expect(result.filesScanned, 1);
  });

  test('a pinned exemption clears exactly its line', () {
    final result = _scan(const [_border]);
    expect(result.findings.map((f) => f.line), [3, 9]);
    expect(result.findings.first.detail, contains('onSurfaceVariant'));
  });

  test('an exemption that matches nothing is a finding', () {
    const moved = CruxOutlineExemption(
      file: 'lib/a.dart',
      line: 6,
      expectedTrimmed: 'color: theme.colorScheme.outline,',
      reason: 'a border, before the file moved',
    );
    final result = _scan(const [moved]);
    expect(
      result.findings.where((f) => f.detail.contains('matches no')),
      hasLength(1),
    );
  });

  test('clean means matches seen equals exemptions, exactly', () {
    final clean = cruxAuditOutlineText(
      sources: const [
        CruxGuardSource(
          path: 'lib/b.dart',
          source: 'final c = Border.all(color: scheme.outline);\n',
        ),
      ],
      exemptions: const [
        CruxOutlineExemption(
          file: 'lib/b.dart',
          line: 1,
          expectedTrimmed: 'final c = Border.all(color: scheme.outline);',
          reason: 'a border',
        ),
      ],
    );
    expect(clean.isClean, isTrue, reason: clean.describe());
    expect(clean.matchesSeen, 1);
  });
}
