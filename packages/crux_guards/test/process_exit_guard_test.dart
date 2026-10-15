// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

CruxGuardResult _audit(
  String source, {
  List<CruxProcessExitExemption> exemptions =
      const <CruxProcessExitExemption>[],
}) => cruxAuditProcessExit(
  sources: [CruxGuardSource(path: 'lib/a.dart', source: source)],
  exemptions: exemptions,
);

void main() {
  group('flags', () {
    test('a menu Quit handler that calls exit(0)', () {
      // The shape every product shipped: the Quit item and the quit shortcut
      // ended the process directly, so the session marker was never removed.
      final result = _audit('''
import 'dart:io' show exit;

void onAction(String action) {
  if (action == 'quit') {
    exit(0);
  }
}
''');
      expect(result.isClean, isFalse);
      expect(result.matchesSeen, 1);
      expect(result.findings.single.line, 5);
      expect(result.findings.single.detail, contains('onAction'));
      expect(result.findings.single.detail, contains('cruxExit'));
    });

    test('a switch case and a closure inside a field initializer', () {
      final result = _audit('''
import 'dart:io';

void Function() betaExpiryExitApp = () => exit(0);

class Shortcuts {
  void handle(int action) {
    switch (action) {
      case 0:
        exit(0);
    }
  }
}
''');
      expect(
        result.findings.map((f) => f.detail.split(',').first),
        ['in betaExpiryExitApp', 'in handle'],
      );
    });

    test('a tear-off handed on as the exit function', () {
      final result = _audit('''
import 'dart:io' show exit, stdout;

void run({void Function(int code) exitProcess = exit}) {}
final provider = Provider((ref) => exit);
''');
      expect(result.matchesSeen, 2);
    });

    test('a prefixed call and a prefixed tear-off', () {
      final result = _audit('''
import 'dart:io' as io;

void quit() => io.exit(0);
final exitWith = io.exit;
''');
      expect(result.matchesSeen, 2);
    });

    test("a part file, through its library's import", () {
      final result = cruxAuditProcessExit(
        sources: const [
          CruxGuardSource(
            path: 'lib/screens/viewer.dart',
            source: '''
import 'dart:io' show exit;

part 'viewer_shortcuts.dart';
''',
          ),
          CruxGuardSource(
            path: 'lib/screens/viewer_shortcuts.dart',
            source: '''
part of 'viewer.dart';

void handle(int action) {
  if (action == 0) exit(0);
}
''',
          ),
        ],
      );
      expect(result.findings.single.path, 'lib/screens/viewer_shortcuts.dart');
      expect(result.findings.single.line, 4);
    });

    test('a hide list that leaves exit visible', () {
      final result = _audit('''
import 'dart:io' hide stdout;

void quit() => exit(1);
''');
      expect(result.matchesSeen, 1);
    });
  });

  group('does not flag', () {
    test('a file that cannot see dart:io exit', () {
      final result = _audit('''
import 'dart:io' show File;
import 'dart:io' hide exit;

void quit(Process p) => p.exit(0);
''');
      expect(result.isClean, isTrue);
      expect(result.matchesSeen, 0);
      expect(result.filesScanned, 1);
    });

    test('cruxExit, comments, strings and named arguments', () {
      final result = _audit('''
import 'dart:io';

/// Calls [exit] eventually; see `exit(0)`.
void quit() {
  // exit(0);
  print('Show this help and exit.');
  configure(exit: true);
  cruxExit(0);
}
''');
      expect(result.isClean, isTrue, reason: result.describe());
      expect(result.matchesSeen, 0);
    });

    test('a member access on some other object', () {
      final result = _audit('''
import 'dart:io';

void quit(Session s) {
  s.exit(0);
  s.exit;
  s..exit(0);
  final code = s.handlers.exit;
}
''');
      expect(result.isClean, isTrue, reason: result.describe());
    });

    test('a local, a parameter, a member or a top-level declaration named '
        'exit', () {
      final result = _audit('''
import 'dart:io';

void a(void Function(int) exit) => exit(0);

void b() {
  final exit = pickExit();
  exit(0);
}

class C {
  void exit(int code) {}
  void d() => exit(0);
}

void e() {
  for (final exit in exits) {
    exit(0);
  }
}
''');
      expect(result.isClean, isTrue, reason: result.describe());
    });
  });

  group('exemptions', () {
    const source = '''
import 'dart:io';

Future<void> main(List<String> args) async {
  exit(await run(args));
}
''';

    test('an exemption covers its member', () {
      final result = _audit(
        source,
        exemptions: const [
          CruxProcessExitExemption(
            file: 'lib/a.dart',
            member: 'main',
            reason: 'pure-Dart entry point; never starts the detector',
          ),
        ],
      );
      expect(result.isClean, isTrue, reason: result.describe());
      expect(result.matchesSeen, 1);
    });

    test('an exemption that matches nothing is a finding', () {
      final result = _audit(
        'void main() {}',
        exemptions: const [
          CruxProcessExitExemption(
            file: 'lib/a.dart',
            member: 'main',
            reason: 'stale',
          ),
        ],
      );
      expect(result.isClean, isFalse);
      expect(result.findings.single.detail, contains('remove it'));
    });
  });
}
