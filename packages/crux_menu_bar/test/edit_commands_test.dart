// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _A { undo, redo, about, settings, quit }

const _appActions = CruxAppMenuActions<_A>(
  about: _A.about,
  settings: _A.settings,
  quit: _A.quit,
);

const _plain = 'Handshake stalls after req rises';

/// The macOS Edit menu's Cut, Copy, Paste and Select All, shared.
///
/// A shipped macOS build beeped on Cmd+C over a selection outside a text field
/// because the Edit menu had no item claiming the key. These tests cover what a
/// widget test can reach of that path: the menu offers the four commands on
/// their chords, and choosing one (which is what AppKit does with a key
/// equivalent the framework left alone) acts without depending on the key
/// having found its way to the focused widget.
Widget _host({
  required TargetPlatform platform,
  CruxEditCommands? editCommands = const CruxEditCommands(
    cutLabel: 'Cut',
    copyLabel: 'Copy',
    pasteLabel: 'Paste',
    selectAllLabel: 'Select All',
  ),
  Map<ActionCategory, List<List<_A>>> layout = const {
    ActionCategory.edit: [
      [_A.undo, _A.redo],
    ],
  },
  Widget body = const SizedBox.shrink(),
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: CruxDesktopMenuBar<_A>(
    layout: layout,
    appActions: _appActions,
    categoryLabel: (c) => c.name,
    categoryAcceleratorLabel: (c) => '&${c.name}',
    windowMenuLabel: 'Window',
    labelOf: (a) => a.name,
    shortcutOf: (_) => null,
    isVisible: (_) => true,
    isEnabled: (_) => true,
    onAction: (_) {},
    logo: const SizedBox.shrink(),
    editCommands: editCommands,
    child: Scaffold(body: body),
  ),
);

PlatformMenu? _editMenu(WidgetTester tester) => tester
    .widget<PlatformMenuBar>(find.byType(PlatformMenuBar))
    .menus
    .whereType<PlatformMenu>()
    .where((m) => m.label == 'edit')
    .firstOrNull;

/// The Edit menu's children with `---` at each group boundary.
List<String> _editItems(WidgetTester tester) {
  final out = <String>[];
  for (final child in _editMenu(tester)!.menus) {
    if (child is PlatformMenuItemGroup) {
      if (out.isNotEmpty) out.add('---');
      out.addAll(child.members.map((m) => m.label));
    } else {
      out.add(child.label);
    }
  }
  return out;
}

/// The four command items, in order.
List<PlatformMenuItem> _commandItems(WidgetTester tester) =>
    (_editMenu(tester)!.menus.first as PlatformMenuItemGroup).members;

/// Records what the app writes to the clipboard, and answers reads with
/// [onPaste].
List<String> _captureClipboard(WidgetTester tester, {String onPaste = ''}) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': onPaste};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// A selectable note that reports to the registry, a focus target outside it
/// and a text field.
Widget _body(FocusNode other, TextEditingController field, Object owner) =>
    Column(
      children: [
        SizedBox(
          width: 400,
          child: SelectionArea(
            onSelectionChanged: (content) => CruxEditSelectionRegistry.instance
                .report(owner, content?.plainText),
            child: const Text(_plain),
          ),
        ),
        Focus(focusNode: other, child: const SizedBox(width: 10, height: 10)),
        SizedBox(width: 200, child: TextField(controller: field)),
      ],
    );

void main() {
  setUp(CruxEditSelectionRegistry.instance.debugReset);

  group('the macOS Edit menu', () {
    testWidgets('leads with Cut, Copy, Paste and Select All on Cmd+X, C, V and '
        'A, in a group of their own', (tester) async {
      await tester.pumpWidget(_host(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();

      expect(_editItems(tester), [
        'Cut',
        'Copy',
        'Paste',
        'Select All',
        '---',
        'undo',
        'redo',
      ]);
      const keys = [
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyA,
      ];
      final items = _commandItems(tester);
      for (var i = 0; i < 4; i++) {
        final chord = items[i].shortcut! as SingleActivator;
        expect(chord.trigger, keys[i]);
        expect(chord.meta, isTrue);
        expect(chord.shift || chord.alt || chord.control, isFalse);
      }
    });

    testWidgets('every one is enabled: a greyed item does not claim its key, '
        'and the key beeps', (tester) async {
      await tester.pumpWidget(_host(platform: TargetPlatform.macOS));
      await tester.pumpAndSettle();
      for (final item in _commandItems(tester)) {
        expect(item.onSelected, isNotNull, reason: item.label);
      }
    });

    testWidgets('with several product groups the commands lead and each '
        'group stays separate', (tester) async {
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          layout: const {
            ActionCategory.edit: [
              [_A.undo],
              [_A.redo],
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(_editItems(tester), [
        'Cut',
        'Copy',
        'Paste',
        'Select All',
        '---',
        'undo',
        '---',
        'redo',
      ]);
    });

    testWidgets('a layout with no Edit entries still gets an Edit menu '
        'holding the four', (tester) async {
      await tester.pumpWidget(
        _host(platform: TargetPlatform.macOS, layout: const {}),
      );
      await tester.pumpAndSettle();
      expect(_editItems(tester), ['Cut', 'Copy', 'Paste', 'Select All']);
    });

    testWidgets('left out by default: no Edit entries, no Edit menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          editCommands: null,
          layout: const {},
        ),
      );
      await tester.pumpAndSettle();
      expect(_editMenu(tester), isNull);
    });

    testWidgets('left out by default: the product Edit items are unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(platform: TargetPlatform.macOS, editCommands: null),
      );
      await tester.pumpAndSettle();
      expect(_editItems(tester), ['undo', 'redo']);
    });

    testWidgets('Copy copies the selection of a reporting area with focus on '
        'it', (tester) async {
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      final owner = Object();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, owner),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      Focus.of(
        tester.element(find.textContaining('Handshake', findRichText: true)),
      ).requestFocus();
      await tester.pump();

      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_plain]);
    });

    testWidgets('Copy still copies a selection on screen when nothing in the '
        'focus chain answers to it', (tester) async {
      // The beep: a highlighted selection and a key press that found no
      // handler. The area keeps its selection while the window is inactive;
      // with focus then somewhere that does not copy, only the menu's own
      // routing reaches it.
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      final owner = Object();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, owner),
        ),
      );
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(find.textContaining('Handshake', findRichText: true)),
      ).requestFocus();
      await tester.pump();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      other.requestFocus();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(other.hasPrimaryFocus, isTrue);

      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_plain]);
    });

    testWidgets('the per-app copyFallback is used when the registry is '
        'empty', (tester) async {
      final copied = _captureClipboard(tester);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          editCommands: CruxEditCommands(
            cutLabel: 'Cut',
            copyLabel: 'Copy',
            pasteLabel: 'Paste',
            selectAllLabel: 'Select All',
            copyFallback: () => 'from the app',
          ),
        ),
      );
      await tester.pumpAndSettle();
      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, ['from the app']);
    });

    testWidgets('Copy with nothing selected copies nothing and does not '
        'throw', (tester) async {
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      final owner = Object();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, owner),
        ),
      );
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pump();
      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selection that cleared is not copied later', (tester) async {
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      final owner = Object();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, owner),
        ),
      );
      await tester.pumpAndSettle();
      Focus.of(
        tester.element(find.textContaining('Handshake', findRichText: true)),
      ).requestFocus();
      await tester.pump();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      expect(CruxEditSelectionRegistry.instance.text, _plain);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // Focus leaves the area: it clears its selection.
      other.requestFocus();
      await tester.pump();
      expect(CruxEditSelectionRegistry.instance.text, isNull);
      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, isEmpty);
    });

    testWidgets('Cut, Copy, Paste and Select All act on a focused text '
        'field', (tester) async {
      final copied = _captureClipboard(tester, onPaste: 'pasted');
      final other = FocusNode();
      final field = TextEditingController(text: 'abc def');
      final owner = Object();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, owner),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final items = _commandItems(tester);

      items[3].onSelected!(); // Select All
      await tester.pump();
      expect(
        field.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );

      items[1].onSelected!(); // Copy
      await tester.pump();
      expect(copied, ['abc def']);

      items[0].onSelected!(); // Cut
      await tester.pump();
      expect(field.text, isEmpty);
      expect(copied, ['abc def', 'abc def']);

      items[2].onSelected!(); // Paste
      await tester.pump();
      expect(field.text, 'pasted');
    });
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('on $platform the menu does not carry them: the keys work in '
        'the focused widget and a menu button would take its focus', (
      tester,
    ) async {
      await tester.pumpWidget(_host(platform: platform));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformMenuBar), findsNothing);
      final bar = tester.widget<MenuBar>(find.byType(MenuBar));
      final labels = <String>[];
      void visit(Widget w) {
        if (w is SubmenuButton) {
          w.menuChildren.forEach(visit);
        } else if (w is MenuItemButton && w.child is Text) {
          labels.add((w.child! as Text).data ?? '');
        }
      }

      bar.children.forEach(visit);
      // Settings and Quit fold into File here; nothing else is added.
      expect(labels, ['settings', 'quit', 'undo', 'redo']);
    });
  }

  group('performCruxEditCommand', () {
    testWidgets('reports a command nothing could take', (tester) async {
      _captureClipboard(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      for (final command in CruxEditCommand.values) {
        expect(performCruxEditCommand(command), isFalse, reason: '$command');
      }
    });

    test('the latest selection to report is the one copied', () {
      final registry = CruxEditSelectionRegistry.instance;
      final a = Object();
      final b = Object();
      registry
        ..report(a, 'first')
        ..report(b, 'second');
      expect(registry.text, 'second');
      registry.report(b, null);
      expect(registry.text, 'first');
      registry.forget(a);
      expect(registry.text, isNull);
    });
  });
}
