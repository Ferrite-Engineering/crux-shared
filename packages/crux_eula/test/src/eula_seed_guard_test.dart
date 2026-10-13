// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula_guards.dart';
import 'package:flutter_test/flutter_test.dart';

List<CruxEulaSeedFinding> _scan(
  String source, {
  Set<String> bootCalls = const {'bootstrap'},
  Set<String> seedCalls = const {'seedEulaAcceptance'},
}) => cruxAuditEulaSeededBoots(
  sources: [
    CruxEulaGuardSource(path: 'integration_test/x_test.dart', source: source),
  ],
  bootCalls: bootCalls,
  seedCalls: seedCalls,
);

void main() {
  test('a boot with the seed before it, in the same test, is green', () {
    expect(
      _scan('''
void main() {
  testWidgets('opens', (tester) async {
    await seedEulaAcceptance();
    await bootstrap(args: ['a.vcd']);
  });
}
'''),
      isEmpty,
    );
  });

  test('removing the seed makes it red, naming the file and line', () {
    final findings = _scan('''
void main() {
  testWidgets('opens', (tester) async {
    await bootstrap(args: ['a.vcd']);
  });
}
''');
    expect(findings, hasLength(1));
    expect(findings.single.path, 'integration_test/x_test.dart');
    expect(findings.single.line, 3);
    expect(findings.single.toString(), contains('acceptEula: false'));
  });

  test('a seed in a sibling test does not cover this one', () {
    final findings = _scan('''
void main() {
  testWidgets('first', (tester) async {
    await seedEulaAcceptance();
    await bootstrap();
  });
  testWidgets('second', (tester) async {
    await bootstrap();
  });
}
''');
    expect(findings.map((f) => f.line), [7]);
  });

  test('a helper that seeds behind its own acceptEula flag is green', () {
    // The boot helpers' shape: the seed sits in an `if` that only a test of
    // the agreement turns off, and the boot call comes after it.
    expect(
      _scan('''
Future<void> bootApp(WidgetTester tester, {bool acceptEula = true}) async {
  if (acceptEula) {
    await seedEulaAcceptance();
  }
  await bootstrap(args: const []);
}
'''),
      isEmpty,
    );
  });

  test('a seed in setUp covers every test after it', () {
    expect(
      _scan('''
void main() {
  setUp(() async {
    await seedEulaAcceptance();
  });
  testWidgets('a', (tester) async {
    await bootstrap();
  });
}
'''),
      isEmpty,
    );
  });

  test('the key itself counts as a seed', () {
    expect(
      _scan('''
Future<void> boot() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kCruxEulaAcceptedVersionKey, kCruxEulaVersion);
  await bootstrap();
}
'''),
      isEmpty,
    );
  });

  test('acceptEula: false is the agreement under test, and not flagged', () {
    expect(
      _scan(
        '''
testWidgets('shows the agreement', (tester) async {
  await bootApp(tester, acceptEula: false);
});
''',
        bootCalls: {'bootApp'},
      ),
      isEmpty,
    );
  });

  test('a product names its own non-seeding boot helper and seed helper', () {
    const source = '''
testWidgets('a', (tester) async {
  await seedFirstLaunchAnswers();
  await launchBare(tester);
});
testWidgets('b', (tester) async {
  await launchBare(tester);
});
''';
    expect(_scan(source), isEmpty, reason: 'launchBare is not a boot yet');
    final findings = _scan(
      source,
      bootCalls: {'launchBare'},
      seedCalls: {'seedFirstLaunchAnswers'},
    );
    expect(findings.map((f) => f.line), [6]);
  });

  test('prose and declarations are neither boots nor seeds', () {
    final findings = _scan('''
// Calls bootstrap() after seedEulaAcceptance().
const String note = 'await bootstrap();';
Future<void> bootstrap({List<String> args = const []}) async {}
testWidgets('a', (tester) async {
  /* seedEulaAcceptance(); */
  await bootstrap();
});
''');
    expect(findings.map((f) => f.line), [6]);
  });
}
