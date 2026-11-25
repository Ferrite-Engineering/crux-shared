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

const _note = 'Handshake stalls after req rises';
const _appSelection = '200 ns  top.req\nreq rises';

/// The macOS Edit menu's Cut, Copy, Paste and Select All, shared.
///
/// A shipped macOS build beeped on Cmd+C over a selection outside a text field
/// because the Edit menu had no item claiming the key. These tests cover what a
/// widget test can reach of that path: the menu offers the four commands on
/// their chords, enabled by what they would do, and choosing one (which is what
/// AppKit does with a key equivalent the framework left alone) acts without
/// depending on the key having found its way to the focused widget.
///
/// [appSelection] stands in for an app's own selection, as its `copyFallback`
/// would report it; the host rebuilds when it changes, as an app's does.
Widget _host({
  required TargetPlatform platform,
  bool withCommands = true,
  ValueNotifier<String?>? appSelection,
  Map<ActionCategory, List<List<_A>>> layout = const {
    ActionCategory.edit: [
      [_A.undo, _A.redo],
    ],
  },
  Widget body = const SizedBox.shrink(),
}) {
  final selection = appSelection ?? ValueNotifier<String?>(null);
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: ValueListenableBuilder<String?>(
      valueListenable: selection,
      builder: (context, _, _) => CruxDesktopMenuBar<_A>(
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
        editCommands: withCommands
            ? CruxEditCommands(
                cutLabel: 'Cut',
                copyLabel: 'Copy',
                pasteLabel: 'Paste',
                selectAllLabel: 'Select All',
                copyFallback: () => selection.value,
              )
            : null,
        child: Scaffold(body: body),
      ),
    ),
  );
}

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

/// The four command items, in order. Read afresh at each step: the menu is
/// rebuilt as the selection changes, and a greyed item has no callback.
List<PlatformMenuItem> _commandItems(WidgetTester tester) =>
    (_editMenu(tester)!.menus.first as PlatformMenuItemGroup).members;

/// Whether each of Cut, Copy, Paste and Select All is enabled, in order.
List<bool> _enabled(WidgetTester tester) => [
  for (final item in _commandItems(tester)) item.onSelected != null,
];

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
            child: const Text(_note),
          ),
        ),
        Focus(focusNode: other, child: const SizedBox(width: 10, height: 10)),
        SizedBox(width: 200, child: TextField(controller: field)),
      ],
    );

/// Gives the note keyboard focus, as a click on it does.
Future<void> _focusNote(WidgetTester tester) async {
  Focus.of(
    tester.element(find.textContaining('Handshake', findRichText: true)),
  ).requestFocus();
  await tester.pump();
}

void _selectNote(WidgetTester tester) => tester
    .state<SelectableRegionState>(find.byType(SelectableRegion))
    .selectAll();

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
          withCommands: false,
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
        _host(platform: TargetPlatform.macOS, withCommands: false),
      );
      await tester.pumpAndSettle();
      expect(_editItems(tester), ['undo', 'redo']);
    });

    testWidgets('with nothing to act on every one is greyed, so its key falls '
        'through to the alert sound', (tester) async {
      final pane = FocusNode(debugLabel: 'Pane');
      addTearDown(pane.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: Focus(focusNode: pane, child: const SizedBox(width: 10)),
        ),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      expect(_enabled(tester), [false, false, false, false]);
    });

    testWidgets('each item enables and greys as focus, text selection and the '
        'app selection change', (tester) async {
      final other = FocusNode(debugLabel: 'Pane');
      final field = TextEditingController(text: 'abc def');
      final app = ValueNotifier<String?>(null);
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: app,
          body: _body(other, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pump();
      //                         Cut    Copy   Paste  Select All
      expect(_enabled(tester), [false, false, false, false]);

      // The app has a selection: Copy, and only Copy.
      app.value = _appSelection;
      await tester.pump();
      expect(_enabled(tester), [false, true, false, false]);

      // Into a text field with nothing selected: the field owns Copy and has
      // nothing to copy; Paste and Select All apply.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      expect(_enabled(tester), [false, false, true, true]);

      // A selection in the field: Cut and Copy too.
      field.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      expect(_enabled(tester), [true, true, true, true]);

      // The selection collapses again.
      field.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(_enabled(tester), [false, false, true, true]);

      // A selectable note focused, nothing selected in it: Select All, and
      // Copy for the app's selection. No Cut or Paste: it is not editable.
      await _focusNote(tester);
      expect(_enabled(tester), [false, true, false, true]);

      // The app's selection cleared: Copy greys.
      app.value = null;
      await tester.pump();
      expect(_enabled(tester), [false, false, false, true]);

      // Text selected in the note: Copy again.
      _selectNote(tester);
      await tester.pump();
      await tester.pump();
      expect(_enabled(tester), [false, true, false, true]);
    });

    testWidgets('a password field never offers Cut or Copy', (tester) async {
      final field = TextEditingController(text: 'secret');
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: ValueNotifier<String?>('a note'),
          body: SizedBox(
            width: 200,
            child: TextField(controller: field, obscureText: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await tester.pump();
      expect(_enabled(tester), [false, false, true, true]);
    });

    testWidgets('Copy copies the selection of a reporting area with focus on '
        'it', (tester) async {
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      _selectNote(tester);
      await tester.pump();
      await _focusNote(tester);

      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_note]);
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
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await _focusNote(tester);
      _selectNote(tester);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      other.requestFocus();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(other.hasPrimaryFocus, isTrue);

      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_note]);
    });

    testWidgets('Copy with nothing selected is greyed, copies nothing and does '
        'not throw', (tester) async {
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pump();
      expect(_commandItems(tester)[1].onSelected, isNull);
      expect(performCruxEditCommand(CruxEditCommand.copy), isFalse);
      await tester.pump();
      expect(copied, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selection that cleared is not copied later', (tester) async {
      final copied = _captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await _focusNote(tester);
      _selectNote(tester);
      await tester.pump();
      expect(CruxEditSelectionRegistry.instance.text, _note);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // Focus leaves the area: it clears its selection.
      other.requestFocus();
      await tester.pump();
      expect(CruxEditSelectionRegistry.instance.text, isNull);
      // The menu hears of it once the frame that cleared it is done.
      await tester.pump();
      expect(_commandItems(tester)[1].onSelected, isNull);
      expect(performCruxEditCommand(CruxEditCommand.copy), isFalse);
      await tester.pump();
      expect(copied, isEmpty);
    });

    testWidgets('Cut, Copy, Paste and Select All act on a focused text '
        'field', (tester) async {
      final copied = _captureClipboard(tester, onPaste: 'pasted');
      final other = FocusNode();
      final field = TextEditingController(text: 'abc def');
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          body: _body(other, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();

      _commandItems(tester)[3].onSelected!(); // Select All
      await tester.pump();
      expect(
        field.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );

      _commandItems(tester)[1].onSelected!(); // Copy
      await tester.pump();
      expect(copied, ['abc def']);

      _commandItems(tester)[0].onSelected!(); // Cut
      await tester.pump();
      expect(field.text, isEmpty);
      expect(copied, ['abc def', 'abc def']);

      _commandItems(tester)[2].onSelected!(); // Paste
      await tester.pump();
      expect(field.text, 'pasted');
    });
  });

  group('the per-app copy fallback', () {
    testWidgets('Copy with focus on a pane that answers to nothing copies '
        "the app's own selection", (tester) async {
      final copied = _captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: ValueNotifier<String?>(_appSelection),
          body: _body(pane, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      // What a key press there finds: nothing.
      expect(
        Actions.maybeFind<CopySelectionTextIntent>(
          FocusManager.instance.primaryFocus!.context!,
        ),
        isNull,
      );

      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_appSelection]);
    });

    testWidgets('performCruxEditCommand copies it, and reports it', (
      tester,
    ) async {
      final copied = _captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Pane');
      addTearDown(pane.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: pane, child: const SizedBox()),
        ),
      );
      pane.requestFocus();
      await tester.pump();
      expect(
        performCruxEditCommand(
          CruxEditCommand.copy,
          fallbackText: _appSelection,
        ),
        isTrue,
      );
      expect(performCruxEditCommand(CruxEditCommand.copy), isFalse);
      // The other three have nothing to act on there.
      for (final c in [
        CruxEditCommand.cut,
        CruxEditCommand.paste,
        CruxEditCommand.selectAll,
      ]) {
        expect(performCruxEditCommand(c, fallbackText: _appSelection), isFalse);
      }
      await tester.pump();
      expect(copied, [_appSelection]);
    });

    testWidgets('a selection in a note wins over the app selection', (
      tester,
    ) async {
      final copied = _captureClipboard(tester);
      final pane = FocusNode();
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: ValueNotifier<String?>(_appSelection),
          body: _body(pane, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await _focusNote(tester);
      _selectNote(tester);
      await tester.pump();
      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_note]);
    });

    testWidgets('an empty selection in a focused note does not stand in for '
        'the app selection', (tester) async {
      // The note's copy action reports a copy handled with nothing selected;
      // the app's selection must still be what Copy copies.
      final copied = _captureClipboard(tester);
      final pane = FocusNode();
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: ValueNotifier<String?>(_appSelection),
          body: _body(pane, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await _focusNote(tester);
      expect(CruxEditSelectionRegistry.instance.text, isNull);
      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [_appSelection]);
    });

    testWidgets('a selection in a focused text field wins over the app '
        'selection', (tester) async {
      final copied = _captureClipboard(tester);
      final pane = FocusNode();
      final field = TextEditingController(text: 'abc def');
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: ValueNotifier<String?>(_appSelection),
          body: _body(pane, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
      await tester.pump();
      _commandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, ['def']);
    });

    testWidgets('a focused text field with nothing selected keeps Copy: it is '
        'greyed and copies nothing', (tester) async {
      final copied = _captureClipboard(tester);
      final pane = FocusNode();
      final field = TextEditingController(text: 'abc def');
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _host(
          platform: TargetPlatform.macOS,
          appSelection: ValueNotifier<String?>(_appSelection),
          body: _body(pane, field, Object()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(_commandItems(tester)[1].onSelected, isNull);
      expect(
        performCruxEditCommand(
          CruxEditCommand.copy,
          fallbackText: _appSelection,
        ),
        isFalse,
      );
      await tester.pump();
      expect(copied, isEmpty);
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

  group('CruxEditAvailability.resolve', () {
    CruxEditAvailability resolve(
      CruxEditFocus focus, {
      bool selectedText = false,
      bool fallback = false,
    }) => CruxEditAvailability.resolve(
      focus: focus,
      hasSelectedText: selectedText,
      fallbackAvailable: fallback,
    );

    const field = CruxEditFocus(editable: true);
    const fieldWithSelection = CruxEditFocus(
      editable: true,
      hasTextSelection: true,
    );

    test("Copy's precedence: field selection, note selection, app", () {
      expect(
        resolve(
          fieldWithSelection,
          selectedText: true,
          fallback: true,
        ).copySource,
        CruxCopySource.focusedText,
      );
      expect(
        resolve(
          CruxEditFocus.none,
          selectedText: true,
          fallback: true,
        ).copySource,
        CruxCopySource.selectedText,
      );
      expect(
        resolve(
          const CruxEditFocus(selectable: true),
          fallback: true,
        ).copySource,
        CruxCopySource.fallback,
      );
      expect(
        resolve(CruxEditFocus.none, fallback: true).copySource,
        CruxCopySource.fallback,
      );
      expect(resolve(CruxEditFocus.none).copySource, isNull);
      // A focused field with nothing selected has nothing to copy.
      expect(resolve(field, fallback: true).copySource, isNull);
    });

    test('Cut needs a selection in changeable text; Paste changeable text; '
        'Select All any text', () {
      expect(resolve(fieldWithSelection).canCut, isTrue);
      expect(resolve(field).canCut, isFalse);
      expect(
        resolve(
          const CruxEditFocus(
            editable: true,
            readOnly: true,
            hasTextSelection: true,
          ),
        ).canCut,
        isFalse,
      );
      expect(resolve(field).canPaste, isTrue);
      expect(
        resolve(const CruxEditFocus(editable: true, readOnly: true)).canPaste,
        isFalse,
      );
      expect(resolve(const CruxEditFocus(selectable: true)).canPaste, isFalse);
      expect(resolve(field).canSelectAll, isTrue);
      expect(
        resolve(const CruxEditFocus(selectable: true)).canSelectAll,
        isTrue,
      );
      expect(
        resolve(CruxEditFocus.none, fallback: true).canSelectAll,
        isFalse,
      );
    });

    test('a password is never cut or copied', () {
      const password = CruxEditFocus(
        editable: true,
        obscured: true,
        hasTextSelection: true,
      );
      expect(resolve(password, fallback: true).copySource, isNull);
      expect(resolve(password).canCut, isFalse);
      expect(resolve(password).canPaste, isTrue);
    });
  });

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
