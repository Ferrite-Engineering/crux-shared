// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tabs with the same file name show the folder that tells them apart.
///
/// The payload doubles as the tab's path, so a test reads as the list of paths
/// it opens. A payload starting `pathless:` has no path.

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'v': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['v'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

String _base(String path) => path.split(RegExp(r'[\\/]')).last;

String? _pathOf(WorkspaceTab<String> tab) =>
    tab.payload.startsWith('pathless:') ? null : tab.payload;

void main() {
  late Directory tempDir;
  var container = ProviderContainer();
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  late WorkspaceNotifier<String> notifier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_folder_');
    final service = WorkspaceService<String>(
      codec: const _StringCodec(),
      directoryFactory: () async => tempDir,
      logger: (_) {},
    );
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        );
  });

  tearDown(() async {
    container.dispose();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Hydrates the workspace; in the test body, where the fake clock runs it.
  Future<void> hydrate() async {
    container = ProviderContainer();
    await container.read(provider.future);
    notifier = container.read(provider.notifier);
  }

  Future<List<TabId>> open(List<String> payloads) async {
    await hydrate();
    return [
      for (final p in payloads)
        await notifier.openTab(displayName: _base(p), payload: p),
    ];
  }

  Future<void> pump(
    WidgetTester tester, {
    Locale? locale,
    ViewerTabBarStrings strings = const ViewerTabBarStringsEn(),
  }) async {
    final ws = container.read(provider).requireValue;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          home: Scaffold(
            body: Column(
              children: [
                for (final pane in ws.panes)
                  SizedBox(
                    width: 900,
                    child: ViewerTabBar<String>(
                      paneId: pane.id,
                      provider: provider,
                      strings: strings,
                      tabFilePath: _pathOf,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The visible label text of every chip, in tree order.
  List<String> labels(WidgetTester tester) => [
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      if (w.textSpan != null) w.textSpan!.toPlainText(),
  ];

  testWidgets('two tabs with one name in different folders each show their '
      'folder', (tester) async {
    await open(['/w/soc_sampler/simcrux.yaml', '/w/alu_core/simcrux.yaml']);
    await pump(tester);

    expect(
      labels(tester),
      equals([
        'simcrux.yaml \u00B7 soc_sampler',
        'simcrux.yaml \u00B7 alu_core',
      ]),
    );
  });

  testWidgets('the folder is muted, the name is not', (tester) async {
    await open(['/w/soc_sampler/simcrux.yaml', '/w/alu_core/simcrux.yaml']);
    await pump(tester);

    final text = tester.widgetList<Text>(find.byType(Text)).first;
    final root = text.textSpan! as TextSpan;
    final muted = root.children!.single as TextSpan;
    final scheme = Theme.of(
      tester.element(find.byType(Text).first),
    ).colorScheme;
    expect(muted.style?.color, scheme.onSurfaceVariant);
    expect(root.text, 'simcrux.yaml');
  });

  testWidgets(
    'a folder name shared by two of three tabs lengthens only theirs',
    (tester) async {
      await open([
        '/w/a/x/f.yaml',
        '/w/b/x/f.yaml',
        '/w/c/y/f.yaml',
      ]);
      await pump(tester);

      expect(
        labels(tester),
        equals([
          'f.yaml \u00B7 a/x',
          'f.yaml \u00B7 b/x',
          'f.yaml \u00B7 y',
        ]),
      );
    },
  );

  testWidgets('unique names show no folder', (tester) async {
    await open(['/w/a/one.yaml', '/w/b/two.yaml']);
    await pump(tester);

    expect(labels(tester), equals(['one.yaml', 'two.yaml']));
  });

  testWidgets('a tab without a path gets no folder, its namesake does', (
    tester,
  ) async {
    await open(['pathless:/w/a/f.yaml', '/w/b/f.yaml', '/w/c/f.yaml']);
    await pump(tester);

    expect(
      labels(tester),
      equals(['f.yaml', 'f.yaml \u00B7 b', 'f.yaml \u00B7 c']),
    );
  });

  testWidgets('two pathless tabs with one name stay as they are', (
    tester,
  ) async {
    await open(['pathless:/a/f.yaml', 'pathless:/b/f.yaml']);
    await pump(tester);

    expect(labels(tester), equals(['f.yaml', 'f.yaml']));
  });

  testWidgets('the same file open twice has no folder to tell them apart', (
    tester,
  ) async {
    await open(['/w/a/f.yaml', '/w/a/f.yaml']);
    await pump(tester);

    expect(labels(tester), equals(['f.yaml', 'f.yaml']));
  });

  testWidgets('a path that is a directory is read by its parents, not its '
      'last segment', (tester) async {
    // The label is the project name and the path is the project directory.
    await hydrate();
    final a = await notifier.openTab(displayName: 'soc', payload: '/w/x/soc/');
    final b = await notifier.openTab(displayName: 'soc', payload: '/w/y/soc');
    expect(a, isNot(b));
    await pump(tester);

    expect(labels(tester), equals(['soc \u00B7 x', 'soc \u00B7 y']));
  });

  testWidgets('Windows separators are split too', (tester) async {
    await open([r'C:\proj\one\f.yaml', r'C:\proj\two\f.yaml']);
    await pump(tester);

    expect(
      labels(tester),
      equals(['f.yaml \u00B7 one', 'f.yaml \u00B7 two']),
    );
  });

  testWidgets('tabs in different panes count as duplicates', (tester) async {
    final ids = await open(['/w/a/f.yaml', '/w/b/f.yaml', '/w/c/g.yaml']);
    final right = await notifier.splitPaneRight();
    await notifier.moveTabToPane(ids[1], right);
    await pump(tester);

    final ws = container.read(provider).requireValue;
    expect(ws.panes.length, 2);
    expect(
      labels(tester).where((l) => l.startsWith('f.yaml')),
      unorderedEquals(['f.yaml \u00B7 a', 'f.yaml \u00B7 b']),
    );
    expect(labels(tester), contains('g.yaml'));
  });

  testWidgets('closing the namesake takes the folder away, opening one '
      'brings it back', (tester) async {
    final ids = await open(['/w/a/f.yaml', '/w/b/f.yaml']);
    await pump(tester);
    expect(labels(tester), everyElement(contains('\u00B7')));

    await notifier.closeTab(ids[1]);
    await tester.pumpAndSettle();
    expect(labels(tester), equals(['f.yaml']));

    await notifier.openTab(displayName: 'f.yaml', payload: '/w/c/f.yaml');
    await tester.pumpAndSettle();
    expect(
      labels(tester),
      equals(['f.yaml \u00B7 a', 'f.yaml \u00B7 c']),
    );
  });

  testWidgets('the semantics label carries the folder', (tester) async {
    await open(['/w/soc_sampler/simcrux.yaml', '/w/alu_core/simcrux.yaml']);
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      find.bySemanticsLabel('simcrux.yaml, soc_sampler'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('simcrux.yaml, alu_core'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a long folder is ellipsized before the name is', (tester) async {
    await open([
      '/w/${'very_long_folder_name_' * 6}/f.yaml',
      '/w/b/f.yaml',
    ]);
    await pump(tester);

    final text = tester.widgetList<Text>(find.byType(Text)).first;
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    // One run: the end is cut first, and the name leads the run.
    expect((text.textSpan! as TextSpan).text, 'f.yaml');
    final rendered = tester.getSize(find.byWidget(text));
    expect(rendered.width, lessThanOrEqualTo(180));
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('renders CJK names and folders under $locale', (tester) async {
      await open([
        '/w/\u6CE2\u5F62/\u8A2D\u8A08.yaml',
        '/w/\uD30C\uD615/\u8A2D\u8A08.yaml',
      ]);
      await pump(tester, locale: locale);

      expect(
        labels(tester),
        equals([
          '\u8A2D\u8A08.yaml \u00B7 \u6CE2\u5F62',
          '\u8A2D\u8A08.yaml \u00B7 \uD30C\uD615',
        ]),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
