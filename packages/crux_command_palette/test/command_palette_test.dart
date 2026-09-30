// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_command_palette/crux_command_palette.dart';
// The scoring counters are diagnostics, deliberately not part of the public
// barrel, so the cost guards below reach them through the src library.
import 'package:crux_command_palette/src/command_palette.dart'
    show
        commandPaletteKeyHandlerDebugLabel,
        debugCommandPaletteScoreCount,
        debugResetCommandPaletteScoreCount;
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal product-style action enum used to exercise the generic widget.
enum _DemoAction implements CruxAction {
  openFile(category: ActionCategory.file),
  zoomIn(category: ActionCategory.view),
  zoomOut(category: ActionCategory.view),
  showAbout(category: ActionCategory.help);

  const _DemoAction({required this.category});

  @override
  final ActionCategory category;

  @override
  String get id => 'demo.$name';

  /// Plain-English label used in tests in place of a real L10N lookup.
  String get displayLabel => switch (this) {
    _DemoAction.openFile => 'Open File',
    _DemoAction.zoomIn => 'Zoom In',
    _DemoAction.zoomOut => 'Zoom Out',
    _DemoAction.showAbout => 'About',
  };
}

Widget _host({
  required List<_DemoAction> actions,
  required void Function(_DemoAction) onAction,
  Map<_DemoAction, ShortcutActivator?> bindings = const {},
  ShortcutActivatorLabel? activatorLabel,
  ScrollWrapperBuilder? scrollWrapperBuilder,
  Widget? Function(_DemoAction)? trailingBuilder,
}) {
  return MaterialApp(
    home: Material(
      child: CommandPalette<_DemoAction>(
        actions: actions,
        labelFor: (a) => a.displayLabel,
        onAction: onAction,
        hintText: 'Type to filter…',
        noResultsLabel: 'No matching commands.',
        bindings: bindings,
        activatorLabel: activatorLabel,
        scrollWrapperBuilder: scrollWrapperBuilder,
        trailingBuilder: trailingBuilder,
      ),
    ),
  );
}

/// Locales the widget is swept across. The palette renders caller-supplied
/// strings, so the sweep is about directionality and locale-sensitive text
/// machinery, not about translations this package owns.
const _localeSweep = [
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

/// State captured by [_pumpPaletteRoute] for a pumped palette.
class _PaletteHarness {
  _PaletteHarness(this.dispatches, this._tester);

  /// Every action the palette dispatched, in order. A list rather than a
  /// single value so double-dispatch is visible instead of idempotent.
  final List<_DemoAction> dispatches;

  final WidgetTester _tester;

  _DemoAction? get picked => dispatches.isEmpty ? null : dispatches.single;

  /// Whether the route the palette was opened *from* is still on screen.
  /// A palette that pops twice takes this with it.
  bool get hostVisible =>
      _tester.any(find.byKey(const Key('palette-host-route')));
}

/// Pumps the palette the way products actually open it — as a dialog route
/// over a host route — and returns a harness over its dispatches.
Future<_PaletteHarness> _pumpPaletteRoute(
  WidgetTester tester, {
  Locale? locale,
  List<_DemoAction> actions = _DemoAction.values,
}) async {
  final dispatches = <_DemoAction>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: _localeSweep,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          key: const Key('palette-host-route'),
          body: Center(
            child: TextButton(
              onPressed: () => CommandPalette.show<_DemoAction>(
                context,
                actions: actions,
                labelFor: (a) => a.displayLabel,
                onAction: dispatches.add,
                hintText: 'Type to filter…',
                noResultsLabel: 'No matching commands.',
              ),
              child: const Text('open palette'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open palette'));
  await tester.pumpAndSettle();
  return _PaletteHarness(dispatches, tester);
}

/// Label of the currently highlighted row, read off the rendered selection
/// tint rather than off private state — only the selected row paints a
/// background colour.
String _highlightedLabel(WidgetTester tester) {
  final tinted = find.descendant(
    of: find.byType(ListView),
    matching: find.byWidgetPredicate((w) => w is Container && w.color != null),
  );
  final label = find.descendant(of: tinted, matching: find.byType(Text));
  return tester.widgetList<Text>(label).single.data!;
}

void main() {
  group('CommandPalette<T>', () {
    testWidgets('renders every supplied action when no query is typed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          actions: const [
            _DemoAction.openFile,
            _DemoAction.zoomIn,
            _DemoAction.zoomOut,
            _DemoAction.showAbout,
          ],
          onAction: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open File'), findsOneWidget);
      expect(find.text('Zoom In'), findsOneWidget);
      expect(find.text('Zoom Out'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('fuzzy-filters when a query is typed', (tester) async {
      await tester.pumpWidget(
        _host(
          actions: const [
            _DemoAction.openFile,
            _DemoAction.zoomIn,
            _DemoAction.zoomOut,
            _DemoAction.showAbout,
          ],
          onAction: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pumpAndSettle();

      expect(find.text('Zoom In'), findsOneWidget);
      expect(find.text('Zoom Out'), findsOneWidget);
      expect(find.text('Open File'), findsNothing);
      expect(find.text('About'), findsNothing);
    });

    testWidgets('shows the no-results message when the query matches nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          actions: const [_DemoAction.openFile, _DemoAction.zoomIn],
          onAction: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'xyznothing');
      await tester.pumpAndSettle();

      expect(find.text('No matching commands.'), findsOneWidget);
    });

    testWidgets('tap on an action fires onAction with that action', (
      tester,
    ) async {
      _DemoAction? picked;
      await tester.pumpWidget(
        _host(
          actions: const [_DemoAction.openFile, _DemoAction.zoomIn],
          onAction: (a) => picked = a,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Zoom In'));
      await tester.pumpAndSettle();

      expect(picked, _DemoAction.zoomIn);
    });

    testWidgets('renders the configured shortcut next to its action', (
      tester,
    ) async {
      const binding = SingleActivator(
        LogicalKeyboardKey.keyO,
        control: true,
      );
      await tester.pumpWidget(
        _host(
          actions: const [_DemoAction.openFile],
          onAction: (_) {},
          bindings: const {_DemoAction.openFile: binding},
        ),
      );
      await tester.pumpAndSettle();

      // Default formatter renders Ctrl-modifier + key as "Ctrl+O".
      expect(find.text('Ctrl+O'), findsOneWidget);
    });

    testWidgets('custom activatorLabel overrides the default formatter', (
      tester,
    ) async {
      const binding = SingleActivator(
        LogicalKeyboardKey.keyP,
        meta: true,
      );
      await tester.pumpWidget(
        _host(
          actions: const [_DemoAction.openFile],
          onAction: (_) {},
          bindings: const {_DemoAction.openFile: binding},
          activatorLabel: (a) => '⌘P',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('⌘P'), findsOneWidget);
    });

    testWidgets('scrollWrapperBuilder wraps the inner list when supplied', (
      tester,
    ) async {
      var wrapperCalled = false;
      await tester.pumpWidget(
        _host(
          actions: const [_DemoAction.openFile, _DemoAction.zoomIn],
          onAction: (_) {},
          scrollWrapperBuilder: (ctx, ctrl, child) {
            wrapperCalled = true;
            return KeyedSubtree(
              key: const Key('test-scroll-wrapper'),
              child: child,
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(wrapperCalled, isTrue);
      expect(find.byKey(const Key('test-scroll-wrapper')), findsOneWidget);
    });

    testWidgets(
      'empty actions list shows the no-results placeholder immediately',
      (tester) async {
        await tester.pumpWidget(
          _host(
            actions: const [],
            onAction: (_) {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No matching commands.'), findsOneWidget);
      },
    );

    testWidgets('renders a trailing widget for actions when supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          actions: _DemoAction.values,
          onAction: (_) {},
          trailingBuilder: (a) => a == _DemoAction.zoomIn
              ? const Icon(Icons.star, key: Key('badge-zoomIn'))
              : null,
        ),
      );
      await tester.pumpAndSettle();

      // The badge is rendered only for the action the builder opted into.
      expect(find.byKey(const Key('badge-zoomIn')), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('CommandPalette keyboard operation', () {
    // Keyboard-only operation is the palette's whole reason to exist, and it
    // shipped broken on desktop for one specific reason: Enter pressed in a
    // focused text field never reaches the framework's key pipeline on
    // platforms whose embedder owns the text-input connection. The engine
    // translates it into a text-input `done` action instead. A test that only
    // ever calls `sendKeyEvent(enter)` cannot see that, so every Enter test
    // below is written twice — once per delivery path.
    //
    // The palette is pumped inside a real dialog route so `Navigator.pop()`
    // has something of its own to pop; a bare pump would pop the host route
    // and mask a double-pop bug.

    testWidgets('Enter delivered as an engine done action executes the '
        'highlighted item', (tester) async {
      final harness = await _pumpPaletteRoute(tester);

      await tester.enterText(find.byType(TextField), 'zoom in');
      await tester.pumpAndSettle();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        harness.picked,
        _DemoAction.zoomIn,
        reason:
            'Enter arrives as TextInputAction.done on every platform whose '
            'engine owns the focused field; handling it only as a key event '
            'is what broke keyboard execution in shipped desktop builds.',
      );
      expect(find.byType(TextField), findsNothing);
      expect(harness.hostVisible, isTrue);
    });

    testWidgets('Enter delivered as a key event executes the highlighted '
        'item', (tester) async {
      final harness = await _pumpPaletteRoute(tester);

      await tester.enterText(find.byType(TextField), 'zoom in');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harness.picked, _DemoAction.zoomIn);
      expect(find.byType(TextField), findsNothing);
      expect(harness.hostVisible, isTrue);
    });

    testWidgets('numpad Enter executes the highlighted item', (tester) async {
      final harness = await _pumpPaletteRoute(tester);

      await tester.enterText(find.byType(TextField), 'zoom in');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();

      expect(harness.picked, _DemoAction.zoomIn);
    });

    testWidgets('both Enter delivery paths for one keypress execute once and '
        'pop once', (tester) async {
      // A platform that delivers Enter as *both* a key event and a done
      // action must not pop twice — the second pop would take the route
      // underneath the palette with it — nor dispatch twice.
      final harness = await _pumpPaletteRoute(tester);

      await tester.enterText(find.byType(TextField), 'zoom in');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(harness.dispatches, [_DemoAction.zoomIn]);
      expect(
        harness.hostVisible,
        isTrue,
        reason: 'The route underneath the palette must survive.',
      );
    });

    testWidgets('ArrowDown/ArrowUp move the highlight while focus stays in '
        'the query field', (tester) async {
      final harness = await _pumpPaletteRoute(tester);

      final queryFocus = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(queryFocus.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(
        queryFocus.hasFocus,
        isTrue,
        reason: 'Navigating must not steal focus out of the query field.',
      );
      expect(_highlightedLabel(tester), 'Zoom Out');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_highlightedLabel(tester), 'Zoom In');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(harness.picked, _DemoAction.zoomIn);
    });

    testWidgets('the highlight clamps at both ends of the list', (
      tester,
    ) async {
      await _pumpPaletteRoute(tester);

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.pumpAndSettle();
      expect(_highlightedLabel(tester), 'Open File');

      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();
      expect(_highlightedLabel(tester), 'About');
    });

    testWidgets('typing a query resets the highlight to the first result', (
      tester,
    ) async {
      final harness = await _pumpPaletteRoute(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'o');
      await tester.pumpAndSettle();

      // 'Open File' is the only prefix match, so it ranks first.
      expect(_highlightedLabel(tester), 'Open File');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(harness.picked, _DemoAction.openFile);
    });

    testWidgets('Escape closes the palette without dispatching', (
      tester,
    ) async {
      final harness = await _pumpPaletteRoute(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(harness.dispatches, isEmpty);
      expect(
        harness.hostVisible,
        isTrue,
        reason:
            'Escape must consume the key; letting it bubble to the enclosing '
            'ModalRoute pops a second route.',
      );
    });

    testWidgets('Enter on an empty result set neither dispatches nor closes', (
      tester,
    ) async {
      final harness = await _pumpPaletteRoute(tester);

      await tester.enterText(find.byType(TextField), 'xyznothing');
      await tester.pumpAndSettle();
      expect(find.text('No matching commands.'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(harness.dispatches, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
    });

    for (final locale in _localeSweep) {
      testWidgets(
        'keyboard execution works under locale ${locale.toLanguageTag()}',
        (
          tester,
        ) async {
          final harness = await _pumpPaletteRoute(tester, locale: locale);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();

          expect(harness.picked, _DemoAction.zoomIn);
        },
      );
    }

    for (final platform in TargetPlatform.values) {
      testWidgets('keyboard execution works on $platform', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final harness = await _pumpPaletteRoute(tester);

        await tester.enterText(find.byType(TextField), 'zoom in');
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Reset before the expectation so a failure does not also trip the
        // binding's "debug variable was changed" invariant and hide it.
        debugDefaultTargetPlatformOverride = null;
        expect(harness.picked, _DemoAction.zoomIn);
      });
    }
  });

  group('CommandPalette filtering cost', () {
    // The palette scores every registered action — 200–300 in a real product,
    // in four products. These guards pin the two ways that cost used to be
    // multiplied: scoring inside the sort comparator (2·n·log n passes rather
    // than n) and re-filtering on rebuilds that cannot change the result.

    setUp(debugResetCommandPaletteScoreCount);

    testWidgets('scores each candidate once per query, not once per '
        'comparison', (tester) async {
      // Enough actions that a per-comparison implementation is unmistakably
      // distinguishable from a per-candidate one: n = 24, so a comparator
      // that scores both operands runs ~2·24·log2(24) ≈ 220 scorings.
      final actions = List<_DemoAction>.generate(
        24,
        (i) => _DemoAction.values[i % _DemoAction.values.length],
      );
      await tester.pumpWidget(_host(actions: actions, onAction: (_) {}));
      await tester.pumpAndSettle();

      debugResetCommandPaletteScoreCount();
      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pumpAndSettle();

      expect(
        debugCommandPaletteScoreCount,
        actions.length,
        reason:
            'Scoring must happen once per candidate '
            '(decorate-sort-undecorate), not inside the sort comparator.',
      );
    });

    testWidgets('does not re-score when the selection moves', (tester) async {
      await tester.pumpWidget(
        _host(actions: _DemoAction.values, onAction: (_) {}),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'o');
      await tester.pumpAndSettle();

      debugResetCommandPaletteScoreCount();

      // Arrow keys rebuild the widget but leave the query untouched, so the
      // filtered + ordered list is provably identical. Re-deriving it was
      // pure waste on the most latency-sensitive interaction in the palette.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
      }

      expect(
        debugCommandPaletteScoreCount,
        0,
        reason: 'Moving the selection must reuse the cached filtered list.',
      );
    });

    testWidgets('re-scores when the query actually changes', (tester) async {
      await tester.pumpWidget(
        _host(actions: _DemoAction.values, onAction: (_) {}),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pumpAndSettle();
      debugResetCommandPaletteScoreCount();

      // The cache must be keyed on the query, not simply never invalidated.
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pumpAndSettle();

      expect(debugCommandPaletteScoreCount, _DemoAction.values.length);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Zoom In'), findsNothing);
    });

    testWidgets('keeps a stable FocusNode across rebuilds', (tester) async {
      await tester.pumpWidget(
        _host(actions: _DemoAction.values, onAction: (_) {}),
      );
      await tester.pumpAndSettle();

      FocusNode keyboardNode() => tester
          .widget<Focus>(
            find.byWidgetPredicate(
              (w) =>
                  w is Focus &&
                  w.debugLabel == commandPaletteKeyHandlerDebugLabel,
            ),
          )
          .focusNode!;

      final initial = keyboardNode();

      // Every keystroke and every arrow key re-enters build(). A FocusNode
      // constructed there would be a fresh, never-disposed instance each time.
      await tester.enterText(find.byType(TextField), 'z');
      await tester.pumpAndSettle();
      expect(identical(keyboardNode(), initial), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(identical(keyboardNode(), initial), isTrue);

      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pumpAndSettle();
      expect(
        identical(keyboardNode(), initial),
        isTrue,
        reason:
            'The key-handler FocusNode must be a disposed-once State field, '
            'not constructed inside build().',
      );

      // Tearing the widget down must dispose it exactly once; a double
      // dispose or a leak both surface here.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('defaultShortcutActivatorLabel', () {
    test('returns empty string for null activator', () {
      expect(defaultShortcutActivatorLabel(null), isEmpty);
    });

    test('returns empty string for non-SingleActivator activators', () {
      const activator = CharacterActivator('a');
      expect(defaultShortcutActivatorLabel(activator), isEmpty);
    });

    test('formats a Ctrl-modifier single activator', () {
      const activator = SingleActivator(
        LogicalKeyboardKey.keyP,
        control: true,
      );
      expect(defaultShortcutActivatorLabel(activator), 'Ctrl+P');
    });

    test('formats a multi-modifier single activator in canonical order', () {
      const activator = SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
        alt: true,
        meta: true,
      );
      expect(
        defaultShortcutActivatorLabel(activator),
        'Ctrl+Alt+Shift+Cmd+S',
      );
    });
  });
}
