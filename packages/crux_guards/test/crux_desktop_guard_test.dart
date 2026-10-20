// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

CruxGuardSource _src(String path, String source) =>
    CruxGuardSource(path: path, source: source);

/// The pattern ids found in [source], in order.
List<String> _ids(String source) => [
  for (final site in cruxFindDesktopSites([_src('lib/a.dart', source)]))
    site.pattern.id,
];

const _phone = '''
Widget phone(BuildContext context) {
  // crux-desktop: phone-only, the phone layout keeps Material 3
  final toggle = Switch(value: true, onChanged: null);
  final other = Switch(value: false, onChanged: null);
  return Column(children: [toggle, other]);
}

// crux-desktop: phone-only: the phone sheet keeps the overflow icon
Widget phoneMenu() => const Icon(Icons.more_vert);

class Pane {
  /// Opens the pane's dialog.
  // crux-desktop: phone-only, the phone pane keeps Material dialogs
  @override
  Future<void> open(BuildContext c) async {
    await showDialog<void>(context: c, builder: (_) => const AlertDialog());
  }

  @override
  // crux-desktop: phone-only, between the annotation and the member
  Widget build(BuildContext c) => const SnackBar(content: Text('x'));

  Widget desktop() => const SimpleDialog();
}
''';

const _threeDialogs = '''
Future<void> a(BuildContext c) => showDialog(context: c, builder: b);
Future<void> b(BuildContext c) => showDialog(context: c, builder: b);
Future<void> c(BuildContext c) => showDialog(context: c, builder: b);
// crux-desktop: phone-only, the phone flow keeps it
Future<void> d(BuildContext c) => showDialog(context: c, builder: b);
''';

void main() {
  group('cruxFindDesktopSites', () {
    test('showDialog: bare and generic; not showCruxDialog, '
        'showGeneralDialog or a method on an object', () {
      expect(
        _ids('''
void f(BuildContext c) {
  showDialog(context: c, builder: b);
  showDialog<bool>(context: c, builder: b);
  showCruxDialog<bool>(context: c, builder: b);
  showGeneralDialog(context: c, pageBuilder: p);
  helper.showDialog(c);
}
'''),
        ['showDialog', 'showDialog'],
      );
    });

    const constructors = {
      'AlertDialog': CruxDesktopPattern.alertDialog,
      'SimpleDialog': CruxDesktopPattern.simpleDialog,
      'SnackBar': CruxDesktopPattern.snackBar,
      'Switch': CruxDesktopPattern.materialSwitch,
      'SwitchListTile': CruxDesktopPattern.switchListTile,
      'CheckboxListTile': CruxDesktopPattern.checkboxListTile,
    };
    for (final MapEntry(key: type, value: pattern) in constructors.entries) {
      test('$type: bare, const, new, and through an import prefix', () {
        expect(
          _ids('''
final all = [
  $type(),
  const $type(),
  new $type(),
  m.$type(),
  const m.$type(),
];
'''),
          List.filled(5, pattern.id),
        );
      });
    }

    test('adaptive constructors: Switch.adaptive is its own pattern, the '
        'list tiles and AlertDialog count as their base', () {
      expect(
        _ids('''
final all = [
  Switch.adaptive(),
  const Switch.adaptive(),
  m.Switch.adaptive(),
  const m.Switch.adaptive(),
  SwitchListTile.adaptive(),
  const CheckboxListTile.adaptive(),
  AlertDialog.adaptive(),
];
'''),
        [
          ...List.filled(4, 'Switch.adaptive'),
          'SwitchListTile',
          'CheckboxListTile',
          'AlertDialog',
        ],
      );
    });

    test('showSnackBar on any target, cascades included', () {
      expect(
        _ids('''
void f(BuildContext c, ScaffoldMessengerState messenger) {
  ScaffoldMessenger.of(c).showSnackBar(x);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(y);
  m.ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: z));
}
'''),
        ['showSnackBar', 'showSnackBar', 'showSnackBar', 'SnackBar'],
      );
    });

    test('Icons.more_vert and its variants, prefixed too; not more_horiz', () {
      expect(
        _ids('''
final icons = [
  Icons.more_vert,
  Icons.more_vert_outlined,
  Icons.more_vert_rounded,
  Icons.more_vert_sharp,
  m.Icons.more_vert,
  Icons.more_vert.codePoint,
  Icons.more_horiz,
  Icons.more_horiz_rounded,
];
'''),
        List.filled(6, 'Icons.more_vert'),
      );
    });

    test('lookalikes, comments, doc references and strings are not sites', () {
      expect(
        _ids('''
/// Replaces [AlertDialog], [Switch] and [Icons.more_vert].
class Lookalikes {
  // showDialog( AlertDialog( Switch( Icons.more_vert in a comment.
  final label = 'showDialog( AlertDialog( SnackBar( Icons.more_vert';
  AlertDialog? dialog;
  Switch? toggle;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? controller;

  Widget build() => Column(children: [
    CupertinoSwitch(value: true, onChanged: null),
    const CupertinoSwitch(value: true, onChanged: null),
    SnackBarAction(label: 'x', onPressed: () {}),
    const SwitchTheme(data: SwitchThemeData(), child: SizedBox()),
    CheckboxTheme(data: CheckboxThemeData(), child: SizedBox()),
    const Icon(Icons.more_horiz),
    showCruxDialog(context: c, builder: b),
  ]);

  void animate() => SnackBar.createAnimationController(vsync: v);
}
'''),
        isEmpty,
      );
    });

    test('names the line of the pattern', () {
      final sites = cruxFindDesktopSites([
        _src('lib/a.dart', '''
void f(BuildContext c) {
  final a = 1;
  ScaffoldMessenger.of(c)
      .showSnackBar(x);
}
'''),
      ]);
      expect(sites.single.line, 4);
      expect(sites.single.path, 'lib/a.dart');
    });

    test('a phone-only marker covers its statement or member, not its '
        'neighbour', () {
      final sites = cruxFindDesktopSites([_src('lib/phone.dart', _phone)]);
      expect(
        [for (final s in sites) '${s.pattern.id}:${s.phoneOnly}'],
        [
          'Switch:true',
          'Switch:false',
          'Icons.more_vert:true',
          'showDialog:true',
          'AlertDialog:true',
          'SnackBar:true',
          'SimpleDialog:false',
        ],
      );
    });

    test('a marker on the first line of the file is seen', () {
      final sites = cruxFindDesktopSites([
        _src(
          'lib/a.dart',
          '// crux-desktop: phone-only, the phone shell keeps it\n'
              'final s = Switch(value: true, onChanged: null);\n',
        ),
      ]);
      expect(sites.single.phoneOnly, isTrue);
    });
  });

  group('cruxAuditCruxDesktop', () {
    test('a phone-only site is exempt; its neighbour is a finding naming the '
        'replacement and the marker', () {
      final result = cruxAuditCruxDesktop(
        sources: [_src('lib/phone.dart', _phone)],
      );
      expect(result.findings, hasLength(2), reason: result.describe());
      final first = result.findings.first;
      expect(first.line, 4);
      expect(first.detail, startsWith('Switch is a raw Material pattern'));
      expect(first.detail, contains('CruxSwitch'));
      expect(first.detail, contains('// crux-desktop: phone-only, <why>'));
      expect(result.findings.last.detail, contains('CruxDialog'));
      expect(result.matchesSeen, 7);
      expect(result.filesScanned, 1);
    });

    test('a marker without a reason is a finding and covers nothing', () {
      final result = cruxAuditCruxDesktop(
        sources: [
          _src('lib/a.dart', '''
// crux-desktop: phone-only
final a = Switch(value: true, onChanged: null);
// crux-desktop: phone-only,
final b = Switch(value: true, onChanged: null);
'''),
        ],
      );
      final details = result.findings.map((f) => f.detail).toList();
      expect(details, hasLength(4));
      expect(details[0], startsWith('Switch is a raw Material pattern'));
      expect(details[1], startsWith('Switch is a raw Material pattern'));
      expect(details[2], contains('has no reason'));
      expect(result.findings[2].line, 1);
      expect(details[3], contains('has no reason'));
      expect(result.findings[3].line, 3);
    });

    test('a marker that covers no site is a finding; a class-level marker '
        'does not cover its members', () {
      final result = cruxAuditCruxDesktop(
        sources: [
          _src('lib/a.dart', '''
// crux-desktop: phone-only, stale: the switch below moved
final unrelated = 1;
final s = Switch(value: true, onChanged: null);

// crux-desktop: phone-only, a marker on a class covers nothing
class Pane {
  Widget build() => const Icon(Icons.more_vert);
}
'''),
        ],
      );
      final details = result.findings.map((f) => f.detail).toList();
      expect(details, hasLength(4), reason: result.describe());
      expect(details[0], startsWith('Switch is a raw'));
      expect(details[1], startsWith('Icons.more_vert is a raw'));
      expect(details[1], contains('CruxOverflowMenu (Icons.more_horiz)'));
      expect(details[2], contains('covers no Crux Desktop site'));
      expect(result.findings[2].line, 1);
      expect(details[3], contains('covers no Crux Desktop site'));
      expect(result.findings[3].line, 5);
    });

    CruxDesktopAllowance allow(String file, int count) => CruxDesktopAllowance(
      file: file,
      pattern: CruxDesktopPattern.showDialog,
      count: count,
      reason: 'moves onto showCruxDialog with the rest',
    );

    test('an exact count is clean; phone-only sites are not counted', () {
      final result = cruxAuditCruxDesktop(
        sources: [_src('lib/a.dart', _threeDialogs)],
        allowances: [allow('lib/a.dart', 3)],
      );
      expect(result.isClean, isTrue, reason: result.describe());
      expect(result.matchesSeen, 4);
    });

    test('a site over the count is one finding per extra site', () {
      final result = cruxAuditCruxDesktop(
        sources: [_src('lib/a.dart', _threeDialogs)],
        allowances: [allow('lib/a.dart', 1)],
      );
      expect(result.findings.map((f) => f.line), [2, 3]);
      expect(result.findings.first.detail, contains('allows 1'));
      expect(result.findings.first.detail, contains('has 3'));
      expect(result.findings.first.detail, contains('showCruxDialog'));
      expect(
        result.findings.first.detail,
        contains('crux-desktop: phone-only'),
      );
    });

    test('a count above the sites says what to lower it to', () {
      final result = cruxAuditCruxDesktop(
        sources: [_src('lib/a.dart', _threeDialogs)],
        allowances: [allow('lib/a.dart', 5)],
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.line, 0);
      expect(result.findings.single.detail, contains('lower the count to 3'));
    });

    test('an allowance with no site, and a duplicate allowance, are '
        'findings', () {
      final result = cruxAuditCruxDesktop(
        sources: [
          _src('lib/a.dart', _threeDialogs),
          _src('lib/b.dart', 'final x = 1;'),
        ],
        allowances: [
          allow('lib/a.dart', 3),
          allow('lib/a.dart', 3),
          allow('lib/b.dart', 1),
        ],
      );
      final details = result.findings.map((f) => f.detail).toList();
      expect(details, hasLength(2), reason: result.describe());
      expect(details[0], contains('a second allowance for showDialog'));
      expect(result.findings[1].path, 'lib/b.dart');
      expect(details[1], contains('matches no site'));
      expect(details[1], contains('remove the entry'));
      expect(result.filesScanned, 2);
    });

    test('an allowance absorbs only its own pattern', () {
      final result = cruxAuditCruxDesktop(
        sources: [
          _src('lib/a.dart', '''
final a = showDialog(context: c, builder: (_) => AlertDialog());
'''),
        ],
        allowances: [allow('lib/a.dart', 1)],
      );
      expect(result.findings.single.detail, startsWith('AlertDialog is a raw'));
    });
  });

  group('allow-list text', () {
    test('cruxFormatDesktopAllowList round-trips through '
        'cruxParseDesktopAllowList', () {
      final sites = cruxFindDesktopSites([
        _src('lib/z.dart', _threeDialogs),
        _src('lib/phone.dart', _phone),
      ]);
      final text = cruxFormatDesktopAllowList(
        sites,
        reason: 'seeded; migrates with the Crux Desktop layer',
      );
      expect(
        text,
        'lib/phone.dart | SimpleDialog | 1 | seeded; migrates with the Crux '
        'Desktop layer\n'
        'lib/phone.dart | Switch | 1 | seeded; migrates with the Crux '
        'Desktop layer\n'
        'lib/z.dart | showDialog | 3 | seeded; migrates with the Crux '
        'Desktop layer\n',
      );
      final parsed = cruxParseDesktopAllowList(text);
      expect(parsed.map((a) => a.toString()), text.trim().split('\n'));
      final result = cruxAuditCruxDesktop(
        sources: [
          _src('lib/z.dart', _threeDialogs),
          _src('lib/phone.dart', _phone),
        ],
        allowances: parsed,
      );
      expect(result.isClean, isTrue, reason: result.describe());
    });

    test('comments and blank lines are skipped; a reason may hold a bar', () {
      final parsed = cruxParseDesktopAllowList('''
# Shrinks to empty.

lib/a.dart | Icons.more_vert | 2 | the toolbar | the status bar
  lib/b.dart|Switch.adaptive|1|settings page\r
''');
      expect(parsed, hasLength(2));
      expect(parsed[0].pattern, CruxDesktopPattern.moreVert);
      expect(parsed[0].count, 2);
      expect(parsed[0].reason, 'the toolbar | the status bar');
      expect(parsed[1].file, 'lib/b.dart');
      expect(parsed[1].pattern, CruxDesktopPattern.switchAdaptive);
      expect(parsed[1].reason, 'settings page');
    });

    final malformed = {
      'too few fields': 'lib/a.dart | showDialog | 2',
      'an empty file': ' | showDialog | 2 | why',
      'an unknown pattern': 'lib/a.dart | showModalBottomSheet | 2 | why',
      'a count of 0': 'lib/a.dart | showDialog | 0 | why',
      'a count that is not a number': 'lib/a.dart | showDialog | two | why',
      'an empty reason': 'lib/a.dart | showDialog | 1 |   ',
      'a duplicate file and pattern':
          'lib/a.dart | showDialog | 1 | why\n'
          'lib/a.dart | showDialog | 2 | again',
    };
    for (final MapEntry(key: what, value: body) in malformed.entries) {
      test('$what is a FormatException naming the line', () {
        expect(
          () => cruxParseDesktopAllowList('# header\n$body\n'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(
                what == 'a duplicate file and pattern' ? 'line 3' : 'line 2',
              ),
            ),
          ),
        );
      });
    }

    test('fromId knows every id and nothing else', () {
      for (final pattern in CruxDesktopPattern.values) {
        expect(CruxDesktopPattern.fromId(pattern.id), pattern);
      }
      expect(CruxDesktopPattern.fromId('showCruxDialog'), isNull);
    });

    test('an empty or multi-line seed reason is rejected', () {
      expect(
        () => cruxFormatDesktopAllowList(const [], reason: ' '),
        throwsArgumentError,
      );
      expect(
        () => cruxFormatDesktopAllowList(const [], reason: 'a\nb'),
        throwsArgumentError,
      );
      expect(cruxFormatDesktopAllowList(const [], reason: 'why'), isEmpty);
    });
  });
}
