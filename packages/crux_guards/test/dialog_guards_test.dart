// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

CruxGuardSource _src(String path, String source) =>
    CruxGuardSource(path: path, source: source);

const _guarded = '''
Future<void> openSearch(BuildContext context) {
  return ModalGuard.run(
    'search',
    () => showDialog<void>(context: context, builder: (_) => const Text('x')),
  );
}
''';

const _bare = '''
class Openers {
  static Future<void> show(BuildContext context) {
    // showDialog( in a comment is not a call.
    final label = 'showDialog(';
    return showDialog<void>(context: context, builder: (_) => Text(label));
  }
}
''';

const _guardBeforeNotAround = '''
Future<void> openA(BuildContext context) =>
    ModalGuard.run('a', () => showDialog<void>(context: context, builder: (_) => const Text('a')));
Future<void> openB(BuildContext context) =>
    showModalBottomSheet<void>(context: context, builder: (_) => const Text('b'));
''';

const _form = '''
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key});
  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  final _controller = TextEditingController();
  @override
  Widget build(BuildContext context) => TextField(controller: _controller);
}

Future<void> openRename(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const RenameDialog(),
);

Future<void> openRenameSafely(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const RenameDialog(),
);

Future<void> openViewer(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AboutBox(),
);

Future<void> openForwarded(BuildContext context, Widget dialog) =>
    showDialog<void>(context: context, builder: (_) => dialog);

Future<void> openInline(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const TextField(),
);
''';

void main() {
  group('cruxFindDialogSites', () {
    test('finds calls, not mentions, and names the enclosing member', () {
      final sites = cruxFindDialogSites([
        _src('lib/a.dart', _guarded),
        _src('lib/b.dart', _bare),
      ]);
      expect(sites.map((s) => s.key), [
        'lib/a.dart#openSearch',
        'lib/b.dart#show',
      ]);
      expect(sites.first.guarded, isTrue);
      expect(sites.last.guarded, isFalse);
      expect(sites.last.line, 5);
    });

    test('a guard earlier in the file does not cover a later call', () {
      final sites = cruxFindDialogSites([
        _src('lib/c.dart', _guardBeforeNotAround),
      ]);
      expect(sites, hasLength(2));
      expect(sites.first.guarded, isTrue);
      expect(sites.last.guarded, isFalse);
      expect(sites.last.opener, 'showModalBottomSheet');
    });
  });

  group('cruxAuditModalGuard', () {
    test('an unguarded opener is a finding', () {
      final result = cruxAuditModalGuard(
        sources: [_src('lib/a.dart', _guarded), _src('lib/b.dart', _bare)],
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.path, 'lib/b.dart');
      expect(result.matchesSeen, 2);
      expect(result.filesScanned, 2);
    });

    test('an allowance covers its member and nothing else', () {
      final result = cruxAuditModalGuard(
        sources: [_src('lib/b.dart', _bare)],
        allowances: const [
          CruxModalGuardAllowance(
            file: 'lib/b.dart',
            member: 'show',
            reason: 'Only reached from a control behind its own barrier.',
          ),
        ],
      );
      expect(result.isClean, isTrue, reason: result.describe());
    });

    test('an allowance that matches nothing is a finding', () {
      final result = cruxAuditModalGuard(
        sources: [_src('lib/a.dart', _guarded)],
        allowances: const [
          CruxModalGuardAllowance(
            file: 'lib/a.dart',
            member: 'openSearch',
            reason: 'Stale: the opener is guarded now.',
          ),
        ],
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.detail, contains('matches no unguarded'));
    });
  });

  group('cruxAuditDismissibleFormDialogs', () {
    test('a form reached through its State class must not be dismissible, '
        'inline text fields count, viewers do not', () {
      final result = cruxAuditDismissibleFormDialogs(
        sources: [_src('lib/f.dart', _form)],
      );
      expect(result.findings.map((f) => f.detail.split(' holds').first), [
        'showDialog in openRename',
        'showModalBottomSheet in openInline',
      ]);
      expect(result.findings.last.detail, contains('isDismissible: false'));
      // openRename, openRenameSafely, openInline.
      expect(result.matchesSeen, 3);
    });

    test('a class declared only in classSources is resolved', () {
      final result = cruxAuditDismissibleFormDialogs(
        sources: [
          _src('lib/g.dart', '''
Future<void> openSwitcher(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const SwitcherDialog());
'''),
        ],
        classSources: [
          _src('shared/switcher.dart', '''
class SwitcherDialog extends StatelessWidget {
  const SwitcherDialog({super.key});
  @override
  Widget build(BuildContext context) => const TextField();
}
'''),
        ],
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.path, 'lib/g.dart');
    });

    test('a known form is checked; a stale one is a finding', () {
      final result = cruxAuditDismissibleFormDialogs(
        sources: [_src('lib/f.dart', _form)],
        knownForms: const [
          CruxKnownFormDialog(
            file: 'lib/f.dart',
            member: 'openForwarded',
            reason: 'The builder forwards a Widget parameter.',
          ),
          CruxKnownFormDialog(
            file: 'lib/f.dart',
            member: 'openGone',
            reason: 'Stale.',
          ),
        ],
        allowances: const [
          CruxDismissibleFormAllowance(
            file: 'lib/f.dart',
            member: 'openRename',
            reason: 'Fixture: the text is saved on every keystroke.',
          ),
          CruxDismissibleFormAllowance(
            file: 'lib/f.dart',
            member: 'openViewer',
            reason: 'Stale: not a form.',
          ),
        ],
      );
      final details = result.findings.map((f) => f.detail).toList();
      expect(details, hasLength(4));
      expect(details[0], startsWith('showDialog in openForwarded'));
      expect(details[1], startsWith('showModalBottomSheet in openInline'));
      expect(details[2], contains('known form openGone'));
      expect(details[3], contains('allowance for openViewer'));
    });
  });

  group('cruxAuditPrivateEmptyStates', () {
    const source = '''
class _EmptyState extends StatelessWidget {}
class _ResultsPlaceholder extends StatelessWidget {}
class _EmptySlot extends StatelessWidget {}
class EmptyWorkspaceState extends StatelessWidget {}
class _Row extends StatelessWidget {
  bool get isEmpty => true;
}
// class _EmptyInAComment {}
''';

    test('private Empty / Placeholder classes are findings unless exempt', () {
      final result = cruxAuditPrivateEmptyStates(
        sources: [_src('lib/e.dart', source)],
        exemptions: const [
          CruxEmptyStateExemption(
            file: 'lib/e.dart',
            className: '_EmptySlot',
            reason: 'A grid cell fill, not a panel state.',
          ),
        ],
      );
      expect(result.findings.map((f) => f.detail.split(' ')[1]), [
        '_EmptyState',
        '_ResultsPlaceholder',
      ]);
      expect(result.findings.first.line, 1);
      expect(result.matchesSeen, 3);
    });

    test('includePublic widens the scan; a stale exemption is a finding', () {
      final result = cruxAuditPrivateEmptyStates(
        sources: [_src('lib/e.dart', source)],
        includePublic: true,
        exemptions: const [
          CruxEmptyStateExemption(
            file: 'lib/e.dart',
            className: '_Gone',
            reason: 'Stale.',
          ),
        ],
      );
      expect(result.matchesSeen, 4);
      expect(result.findings, hasLength(5));
      expect(result.findings.last.detail, contains('_Gone'));
    });
  });
}
