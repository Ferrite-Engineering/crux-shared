// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/crux_guards.dart';
import 'package:test/test.dart';

CruxGuardResult _scan(
  String source, {
  List<CruxRefAfterAwaitExemption> exemptions = const [],
}) => cruxAuditRefAfterAwait(
  sources: [CruxGuardSource(path: 'lib/app.dart', source: source)],
  exemptions: exemptions,
);

void main() {
  test('a ConsumerState method reading ref after an await is flagged', () {
    final result = _scan('''
class _AppState extends ConsumerState<App> {
  Future<void> _handleOpenProject() async {
    final path = await pickFile();
    ref.read(projectProvider.notifier).open(path);
  }
}
''');
    expect(result.findings, hasLength(1));
    expect(result.findings.single.line, 4);
    expect(result.findings.single.detail, contains('_handleOpenProject'));
  });

  test('a mounted check between the await and the use clears it', () {
    for (final check in [
      'if (!mounted) return;',
      'if (!context.mounted) return;',
      'if (!ref.mounted) return;',
    ]) {
      final result = _scan('''
class _AppState extends ConsumerState<App> {
  Future<void> _open() async {
    final path = await pickFile();
    $check
    ref.read(projectProvider.notifier).open(path);
  }
}
''');
      expect(result.isClean, isTrue, reason: '$check\n${result.describe()}');
    }
  });

  test(
    'ref read before the await, or inside the awaited expression, is fine',
    () {
      final result = _scan('''
class _AppState extends ConsumerState<App> {
  Future<void> _open() async {
    final notifier = ref.read(projectProvider.notifier);
    final store = await ref.read(storeProvider.future);
    notifier.open(store);
  }
}
''');
      expect(result.isClean, isTrue, reason: result.describe());
    },
  );

  test('a function taking a WidgetRef is in scope too, closures included', () {
    final result = _scan('''
Future<void> saveSessionAs(WidgetRef ref, String path) async {
  await writeSession(path);
  ref.invalidate(sessionProvider);
}
void wire(WidgetRef ref) {
  button.onPressed = () async {
    await Future<void>.delayed(Duration.zero);
    ref.read(flagProvider.notifier).state = false;
  };
}
''');
    expect(result.findings.map((f) => f.line), [3, 8]);
  });

  test(
    'outside a ConsumerState and without a WidgetRef, nothing is checked',
    () {
      final result = _scan('''
class Store {
  Future<void> load(Ref ref) async {
    await Future<void>.delayed(Duration.zero);
    ref.read(x);
  }
}
''');
      expect(result.isClean, isTrue);
      expect(result.matchesSeen, 0);
    },
  );

  test('an await in a branch that returns does not precede the use', () {
    final result = _scan('''
class _AppState extends ConsumerState<App> {
  Future<void> _onChanged(String? next) async {
    if (next == null) {
      await showSaveDialog();
      return;
    }
    ref.read(presetsProvider.notifier).activate(next);
  }
  Future<void> _fallsThrough(bool x) async {
    if (x) {
      await showSaveDialog();
    }
    ref.read(presetsProvider.notifier).reset();
  }
}
''');
    expect(result.findings.map((f) => f.line), [13]);
  });

  test('an argument label or another object member is not ref', () {
    final result = _scan('''
class _AppState extends ConsumerState<App> {
  Future<void> _open() async {
    await pickFile();
    build(ref: null);
    widget.ref.toString();
  }
}
''');
    expect(result.isClean, isTrue, reason: result.describe());
  });

  test('an exemption names a file and function, and goes stale', () {
    const source = '''
class _AppState extends ConsumerState<App> {
  Future<void> _open() async {
    await pickFile();
    ref.read(x);
  }
}
''';
    const exemption = CruxRefAfterAwaitExemption(
      file: 'lib/app.dart',
      function: '_open',
      reason: 'the container outlives the widget',
    );
    expect(_scan(source, exemptions: const [exemption]).isClean, isTrue);
    final stale = _scan(
      'class A {}',
      exemptions: const [exemption],
    );
    expect(stale.findings.single.detail, contains('matches no use'));
  });
}
