// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
// The barrel deliberately re-exports only `PaneSize` / `IdePaneBuilder`; these
// tests reach the live controller, so they import `panes` directly.
import 'package:panes/panes.dart';

/// Mutable read-side adapter for tests. Tests set the fields they vary via
/// cascade after construction.
class _FakeLayout implements IdePanelLayout {
  @override
  bool leftVisible = true;
  @override
  bool rightVisible = false;
  @override
  bool bottomVisible = false;
  @override
  PaneSize? leftSize;
  @override
  PaneSize? rightSize;
  @override
  PaneSize? bottomSize;
}

/// Recording write-side adapter for tests.
class _RecordingSink implements IdePanelLayoutSink {
  final List<String> calls = [];

  @override
  void setLeftVisible({required bool visible}) => calls.add('left=$visible');
  @override
  void setRightVisible({required bool visible}) => calls.add('right=$visible');
  @override
  void setBottomVisible({required bool visible}) =>
      calls.add('bottom=$visible');
  @override
  void setLeftSize(double pixels) => calls.add('leftSize=$pixels');
  @override
  void setRightSize(double pixels) => calls.add('rightSize=$pixels');
  @override
  void setBottomSize(double pixels) => calls.add('bottomSize=$pixels');
}

Widget _app(
  IdePanelLayout layout,
  IdePanelLayoutSink sink, {
  PaneSize? centerMinSize,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ],
    home: Scaffold(
      body: CruxIdeLayout(
        layout: layout,
        sink: sink,
        centerMinSize: centerMinSize,
        leftBuilder: (ctx, _) => const Text('LEFT'),
        centerBuilder: (ctx, _) => const Text('CENTER'),
        rightBuilder: (ctx, _) => const Text('RIGHT'),
        bottomBuilder: (ctx, _) => const Text('BOTTOM'),
      ),
    ),
  );
}

/// Host that lets a test mutate the layout and rebuild CruxIdeLayout, mirroring
/// how an app rebuilds it from a ref.watch.
class _ToggleHost extends StatefulWidget {
  const _ToggleHost({required this.layout, required this.sink});
  final _FakeLayout layout;
  final IdePanelLayoutSink sink;

  @override
  State<_ToggleHost> createState() => _ToggleHostState();
}

class _ToggleHostState extends State<_ToggleHost> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () =>
                  setState(() => widget.layout.leftVisible = false),
              child: const Text('hide-left'),
            ),
            Expanded(
              child: CruxIdeLayout(
                layout: widget.layout,
                sink: widget.sink,
                leftBuilder: (ctx, _) => const Text('LEFT'),
                centerBuilder: (ctx, _) => const Text('CENTER'),
                rightBuilder: (ctx, _) => const Text('RIGHT'),
                bottomBuilder: (ctx, _) => const Text('BOTTOM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Host that lets a test push an arbitrary mutation into the layout and then
/// rebuild `CruxIdeLayout`, mirroring how an app rebuilds it from a
/// `ref.watch`. Used for the right/bottom region deltas.
class _MutationHost extends StatefulWidget {
  const _MutationHost({
    required this.layout,
    required this.sink,
    required this.mutate,
  });
  final _FakeLayout layout;
  final IdePanelLayoutSink sink;
  final void Function(_FakeLayout layout) mutate;

  @override
  State<_MutationHost> createState() => _MutationHostState();
}

class _MutationHostState extends State<_MutationHost> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => widget.mutate(widget.layout)),
              child: const Text('mutate'),
            ),
            Expanded(
              child: CruxIdeLayout(
                layout: widget.layout,
                sink: widget.sink,
                leftBuilder: (ctx, _) => const Text('LEFT'),
                centerBuilder: (ctx, _) => const Text('CENTER'),
                rightBuilder: (ctx, _) => const Text('RIGHT'),
                bottomBuilder: (ctx, _) => const Text('BOTTOM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live [IdeController] the widget built, reached through the `panes`
/// [IdeLayout] it renders. Lets a test drive the controller the way a user
/// drag gesture does — outside the host-delta window — rather than through a
/// host rebuild.
IdeController _liveController(WidgetTester tester) =>
    tester.widget<IdeLayout>(find.byType(IdeLayout)).controller;

/// Host that rebuilds CruxIdeLayout with a new left pane size, mirroring how an
/// app re-feeds a persisted size after a session restore. The left pane content
/// fills its region so its rendered width equals the pane width.
class _ResizeHost extends StatefulWidget {
  const _ResizeHost({required this.layout, required this.sink});
  final _FakeLayout layout;
  final IdePanelLayoutSink sink;

  @override
  State<_ResizeHost> createState() => _ResizeHostState();
}

class _ResizeHostState extends State<_ResizeHost> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(
                () => widget.layout.leftSize = PaneSize.pixel(150),
              ),
              child: const Text('resize-left'),
            ),
            Expanded(
              child: CruxIdeLayout(
                layout: widget.layout,
                sink: widget.sink,
                leftBuilder: (ctx, _) =>
                    const SizedBox.expand(key: Key('left-pane')),
                centerBuilder: (ctx, _) => const Text('CENTER'),
                rightBuilder: (ctx, _) => const Text('RIGHT'),
                bottomBuilder: (ctx, _) => const Text('BOTTOM'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mounts `CruxIdeLayout` at an exact size, so a test can shrink and re-grow
/// "the window" by re-pumping with a different [size]. Re-pumping keeps the
/// widget's element (and so its `IdeController`) alive, mirroring a real window
/// resize rather than a fresh mount. Every region fills its slot, so a rendered
/// pane's size is its region's size.
Widget _sizedApp(
  IdePanelLayout layout,
  IdePanelLayoutSink sink, {
  required Size size,
  PaneSize? centerMinSize,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CruxIdeLayout(
            layout: layout,
            sink: sink,
            centerMinSize: centerMinSize,
            leftMinSize: PaneSize.pixel(150),
            rightMinSize: PaneSize.pixel(150),
            bottomMinSize: PaneSize.pixel(80),
            leftBuilder: (ctx, _) =>
                const SizedBox.expand(key: Key('left-pane')),
            centerBuilder: (ctx, _) =>
                const SizedBox.expand(key: Key('center-pane')),
            rightBuilder: (ctx, _) =>
                const SizedBox.expand(key: Key('right-pane')),
            bottomBuilder: (ctx, _) =>
                const SizedBox.expand(key: Key('bottom-pane')),
          ),
        ),
      ),
    ),
  );
}

/// Mounts `CruxIdeLayout` filling the whole test surface, so resizing the view
/// changes its constraints without rebuilding any widget — the real
/// window-resize path, where the fit clamp has to reach the panes from the
/// layout callback alone.
Widget _fullApp(IdePanelLayout layout, IdePanelLayoutSink sink) {
  return MaterialApp(
    home: Scaffold(
      body: CruxIdeLayout(
        layout: layout,
        sink: sink,
        centerMinSize: PaneSize.pixel(120),
        bottomMinSize: PaneSize.pixel(80),
        leftBuilder: (ctx, _) => const SizedBox.expand(key: Key('left-pane')),
        centerBuilder: (ctx, _) =>
            const SizedBox.expand(key: Key('center-pane')),
        rightBuilder: (ctx, _) => const SizedBox.expand(key: Key('right-pane')),
        bottomBuilder: (ctx, _) =>
            const SizedBox.expand(key: Key('bottom-pane')),
      ),
    ),
  );
}

double _paneHeight(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(Key(key))).height;

double _paneWidth(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(Key(key))).width;

void main() {
  testWidgets('renders center and the visible left pane', (tester) async {
    await tester.pumpWidget(_app(_FakeLayout(), _RecordingSink()));
    await tester.pump();
    expect(find.text('CENTER'), findsOneWidget);
    expect(find.text('LEFT'), findsOneWidget);
  });

  testWidgets('accepts fraction sizes without exception', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeLayout()
          ..rightVisible = true
          ..bottomVisible = true
          ..leftSize = PaneSize.fraction(0.2)
          ..rightSize = PaneSize.fraction(0.25)
          ..bottomSize = PaneSize.fraction(0.3),
        _RecordingSink(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('CENTER'), findsOneWidget);
  });

  testWidgets('accepts pixel sizes and a center min size', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeLayout()
          ..leftSize = PaneSize.pixel(280)
          ..rightSize = PaneSize.pixel(220)
          ..bottomSize = PaneSize.pixel(200),
        _RecordingSink(),
        centerMinSize: PaneSize.pixel(120),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('CENTER'), findsOneWidget);
  });

  testWidgets('applies a host visibility delta without echoing the sink', (
    tester,
  ) async {
    final layout = _FakeLayout();
    final sink = _RecordingSink();
    await tester.pumpWidget(_ToggleHost(layout: layout, sink: sink));
    await tester.pump();
    expect(find.text('LEFT'), findsOneWidget);

    await tester.tap(find.text('hide-left'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // A host-driven (programmatic) visibility change must NOT echo back into
    // the sink — the host already owns that value; only user drag gestures do.
    expect(sink.calls, isEmpty);
  });

  testWidgets(
    'reconciles a host-driven size delta onto the live controller '
    'without echoing the sink',
    (tester) async {
      final layout = _FakeLayout()..leftSize = PaneSize.pixel(280);
      final sink = _RecordingSink();
      await tester.pumpWidget(_ResizeHost(layout: layout, sink: sink));
      await tester.pump();

      // Initial pane width reflects the seeded size.
      expect(
        tester.getSize(find.byKey(const Key('left-pane'))).width,
        moreOrLessEquals(280, epsilon: 1),
      );

      // Host pushes a new size after the controller already exists (the
      // session-restore case). didUpdateWidget must apply it to the controller.
      await tester.tap(find.text('resize-left'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('left-pane'))).width,
        moreOrLessEquals(150, epsilon: 1),
      );

      // The programmatic reconcile must NOT echo back into the sink — only
      // genuine user drag gestures write sizes back.
      expect(sink.calls, isEmpty);
    },
  );

  testWidgets(
    'applies host visibility deltas for the right and bottom regions',
    (tester) async {
      final layout = _FakeLayout();
      final sink = _RecordingSink();
      await tester.pumpWidget(
        _MutationHost(
          layout: layout,
          sink: sink,
          mutate: (l) => l
            ..rightVisible = true
            ..bottomVisible = true,
        ),
      );
      await tester.pump();
      // `panes` keeps a hidden region built and laid out, so visibility is
      // asserted on the controller rather than on the widget tree.
      var controller = _liveController(tester);
      expect(controller.rootController.isVisible(IdePane.right.id), isFalse);
      expect(controller.centerController.isVisible(IdePane.bottom.id), isFalse);

      // Exercises the show branch of _applyVisibility for both regions.
      await tester.tap(find.text('mutate'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller = _liveController(tester);
      expect(controller.rootController.isVisible(IdePane.right.id), isTrue);
      expect(controller.centerController.isVisible(IdePane.bottom.id), isTrue);
      expect(sink.calls, isEmpty);
    },
  );

  testWidgets(
    'reconciles host-driven right and bottom size deltas without echoing',
    (tester) async {
      final layout = _FakeLayout()
        ..rightVisible = true
        ..bottomVisible = true
        ..rightSize = PaneSize.pixel(200)
        ..bottomSize = PaneSize.pixel(180);
      final sink = _RecordingSink();
      await tester.pumpWidget(
        _MutationHost(
          layout: layout,
          sink: sink,
          mutate: (l) => l
            ..rightSize = PaneSize.pixel(260)
            ..bottomSize = PaneSize.pixel(120),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('mutate'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Both regions are still rendered, and the reconcile stayed silent —
      // only genuine user gestures write back.
      expect(find.text('RIGHT'), findsOneWidget);
      expect(find.text('BOTTOM'), findsOneWidget);
      expect(sink.calls, isEmpty);
    },
  );

  testWidgets('mirrors a user-driven visibility change into the sink', (
    tester,
  ) async {
    final layout = _FakeLayout()
      ..rightVisible = true
      ..bottomVisible = true;
    final sink = _RecordingSink();
    await tester.pumpWidget(_app(layout, sink));
    await tester.pump();

    // Driving the controller directly reproduces a user drag-to-collapse:
    // `panes` fires onPaneStateChanged outside the host-delta window, so the
    // change must reach the sink. A regression that suppressed these
    // unconditionally would silently stop persisting panel visibility.
    final controller = _liveController(tester);
    controller.rootController.hide(IdePane.left.id);
    controller.rootController.hide(IdePane.right.id);
    controller.centerController.hide(IdePane.bottom.id);
    await tester.pumpAndSettle();

    expect(sink.calls, containsAll(<String>['left=false', 'right=false']));
    expect(sink.calls, contains('bottom=false'));

    sink.calls.clear();
    controller.rootController.show(IdePane.left.id);
    await tester.pumpAndSettle();
    expect(sink.calls, contains('left=true'));
  });

  testWidgets('mirrors a user-driven resize into the sink', (tester) async {
    final layout = _FakeLayout()
      ..rightVisible = true
      ..bottomVisible = true
      ..leftSize = PaneSize.pixel(280)
      ..rightSize = PaneSize.pixel(220)
      ..bottomSize = PaneSize.pixel(200);
    final sink = _RecordingSink();
    await tester.pumpWidget(_app(layout, sink));
    await tester.pump();

    // Reproduces a user splitter drag on each region.
    final controller = _liveController(tester);
    controller.rootController.updateSize(IdePane.left.id, PaneSize.pixel(310));
    controller.rootController.updateSize(IdePane.right.id, PaneSize.pixel(190));
    controller.centerController.updateSize(
      IdePane.bottom.id,
      PaneSize.pixel(240),
    );
    await tester.pumpAndSettle();

    expect(sink.calls, contains('leftSize=310.0'));
    expect(sink.calls, contains('rightSize=190.0'));
    expect(sink.calls, contains('bottomSize=240.0'));
  });

  testWidgets('never mirrors center-region changes into the sink', (
    tester,
  ) async {
    final sink = _RecordingSink();
    await tester.pumpWidget(_app(_FakeLayout(), sink));
    await tester.pump();

    // The center region is always visible and its size is derived from its
    // siblings, so neither event has anything to persist. A regression that
    // routed these to a sink setter would corrupt the host's stored layout.
    final controller = _liveController(tester);
    controller.centerController
      ..hide(IdePane.center.id)
      ..updateSize(IdePane.center.id, PaneSize.pixel(400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(sink.calls, isEmpty);
  });

  testWidgets(
    'shrinks the bottom region instead of overflowing a short window',
    (tester) async {
      final layout = _FakeLayout()
        ..bottomVisible = true
        ..bottomSize = PaneSize.pixel(415);
      final sink = _RecordingSink();

      // The reported case: a persisted 415 dp bottom region in a window with
      // only 363 dp for the vertical stack. Unclamped, `panes` hands the bottom
      // region its full 415 dp, starves the center to zero and overflows the
      // RenderFlex by 415 + 6 - 363 = 58 dp.
      await tester.pumpWidget(
        _sizedApp(
          layout,
          sink,
          size: const Size(579, 363),
          centerMinSize: PaneSize.pixel(120),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 363 - 6 (resizer) - 120 (center floor) = 237.
      expect(
        _paneHeight(tester, 'bottom-pane'),
        moreOrLessEquals(237, epsilon: 1),
      );
      expect(
        _paneHeight(tester, 'center-pane'),
        moreOrLessEquals(120, epsilon: 1),
      );
      // A fit clamp is a transient correction, not a user resize: persisting it
      // would overwrite the user's chosen size the moment they shrink the
      // window, and it would never grow back.
      expect(sink.calls, isEmpty);
    },
  );

  testWidgets('restores the preferred bottom size when the window grows', (
    tester,
  ) async {
    final layout = _FakeLayout()
      ..bottomVisible = true
      ..bottomSize = PaneSize.pixel(415);
    final sink = _RecordingSink();
    await tester.pumpWidget(
      _sizedApp(
        layout,
        sink,
        size: const Size(579, 363),
        centerMinSize: PaneSize.pixel(120),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _paneHeight(tester, 'bottom-pane'),
      moreOrLessEquals(237, epsilon: 1),
    );

    // Same element, taller window — the clamp inverts and the persisted size
    // comes back rather than staying stuck at the shrunken one.
    await tester.pumpWidget(
      _sizedApp(
        layout,
        sink,
        size: const Size(579, 600),
        centerMinSize: PaneSize.pixel(120),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      _paneHeight(tester, 'bottom-pane'),
      moreOrLessEquals(415, epsilon: 1),
    );
    expect(sink.calls, isEmpty);
  });

  testWidgets('shrinks both side regions in proportion in a narrow window', (
    tester,
  ) async {
    final layout = _FakeLayout()
      ..rightVisible = true
      ..leftSize = PaneSize.pixel(280)
      ..rightSize = PaneSize.pixel(220);
    final sink = _RecordingSink();
    await tester.pumpWidget(
      _sizedApp(
        layout,
        sink,
        size: const Size(400, 500),
        centerMinSize: PaneSize.pixel(120),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 400 - 2 × 6 (resizers) - 120 (center floor) = 268 dp for both sides,
    // split in the 280 : 220 ratio the user chose.
    final left = _paneWidth(tester, 'left-pane');
    final right = _paneWidth(tester, 'right-pane');
    expect(left + right, moreOrLessEquals(268, epsilon: 1));
    expect(left / right, moreOrLessEquals(280 / 220, epsilon: 0.01));
    expect(
      _paneWidth(tester, 'center-pane'),
      moreOrLessEquals(120, epsilon: 1),
    );
    expect(sink.calls, isEmpty);
  });

  testWidgets('clamps on a bare window resize, with no widget rebuild', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);

    final layout = _FakeLayout()
      ..bottomVisible = true
      ..bottomSize = PaneSize.pixel(415);
    final sink = _RecordingSink();
    await tester.pumpWidget(_fullApp(layout, sink));
    await tester.pumpAndSettle();
    expect(
      _paneHeight(tester, 'bottom-pane'),
      moreOrLessEquals(415, epsilon: 1),
    );

    // Dragging the window shorter delivers new constraints without dirtying a
    // single widget, so the clamp only gets the layout callback to work with.
    tester.view.physicalSize = const Size(900, 400);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 400 - 6 (resizer) - 120 (center floor) = 274.
    expect(
      _paneHeight(tester, 'bottom-pane'),
      moreOrLessEquals(274, epsilon: 1),
    );
    expect(
      _paneHeight(tester, 'center-pane'),
      moreOrLessEquals(120, epsilon: 1),
    );
    expect(sink.calls, isEmpty);
  });

  testWidgets('leaves regions alone when the window has room', (tester) async {
    final layout = _FakeLayout()
      ..rightVisible = true
      ..bottomVisible = true
      ..leftSize = PaneSize.pixel(280)
      ..rightSize = PaneSize.pixel(220)
      ..bottomSize = PaneSize.pixel(200);
    final sink = _RecordingSink();
    await tester.pumpWidget(
      _sizedApp(
        layout,
        sink,
        size: const Size(1200, 800),
        centerMinSize: PaneSize.pixel(120),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_paneWidth(tester, 'left-pane'), moreOrLessEquals(280, epsilon: 1));
    expect(_paneWidth(tester, 'right-pane'), moreOrLessEquals(220, epsilon: 1));
    expect(
      _paneHeight(tester, 'bottom-pane'),
      moreOrLessEquals(200, epsilon: 1),
    );
  });

  testWidgets('renders without exception across the locale sweep', (
    tester,
  ) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await tester.pumpWidget(
        _app(_FakeLayout(), _RecordingSink(), locale: locale),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'locale $locale');
    }
  });
}
