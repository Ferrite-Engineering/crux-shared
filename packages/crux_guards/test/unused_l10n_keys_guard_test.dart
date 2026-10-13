// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

const _arb = '''
{
  "@@locale": "en",
  "menuOpen": "Open",
  "@menuOpen": {"description": "File menu"},
  "menuSave": "Save",
  "dialogTitle": "Settings",
  "snackNotYet": "Not available yet",
  "onlyInComment": "Mentioned",
  "onlyInString": "Quoted"
}
''';

const _lib = '''
// onlyInComment is prose, not a read.
const s = 'onlyInString';
Widget menu(BuildContext context) {
  final l10n = L10N.of(context);
  return Column(children: [Text(l10n.menuOpen), Text(_title(context))]);
}
String _title(BuildContext context) => AppLocalizations.of(context)!.dialogTitle;
String get saveLabel => l10nOf().menuSave;
''';

CruxGuardResult _scan({List<CruxL10nRetention> retained = const []}) =>
    cruxAuditUnusedL10nKeys(
      keys: cruxArbMessageKeys(_arb),
      sources: const [CruxGuardSource(path: 'lib/menu.dart', source: _lib)],
      retained: retained,
      arbPath: 'lib/l10n/app_en.arb',
    );

void main() {
  test('message keys exclude metadata', () {
    expect(cruxArbMessageKeys(_arb), {
      'menuOpen',
      'menuSave',
      'dialogTitle',
      'snackNotYet',
      'onlyInComment',
      'onlyInString',
    });
    expect(() => cruxArbMessageKeys('[]'), throwsFormatException);
  });

  test(
    'a key no code reads is a finding; comments and strings do not read',
    () {
      final result = _scan();
      expect(result.matchesSeen, 3);
      expect(
        result.findings.map((f) => f.detail),
        everyElement(contains('is read by no code')),
      );
      expect(
        result.findings.map((f) => RegExp(r'"(\w+)"').firstMatch(f.detail)![1]),
        ['onlyInComment', 'onlyInString', 'snackNotYet'],
      );
    },
  );

  test('a retained key with a reason is allowed to go unread', () {
    final result = _scan(
      retained: const [
        CruxL10nRetention(key: 'snackNotYet', reason: 'generic, needed again'),
        CruxL10nRetention(key: 'onlyInComment', reason: 'x'),
        CruxL10nRetention(key: 'onlyInString', reason: 'x'),
      ],
    );
    expect(result.isClean, isTrue, reason: result.describe());
  });

  test('a stale retention entry is a finding', () {
    final result = _scan(
      retained: const [
        CruxL10nRetention(key: 'menuOpen', reason: 'read again since'),
        CruxL10nRetention(key: 'gone', reason: 'deleted from the ARB'),
      ],
    );
    final details = result.findings.map((f) => f.detail).join('\n');
    expect(details, contains('"menuOpen" is read by code again'));
    expect(details, contains('"gone" is not in the ARB'));
  });
}
