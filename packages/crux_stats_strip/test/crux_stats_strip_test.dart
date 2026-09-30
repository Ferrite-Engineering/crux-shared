// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show FrameTiming;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(
  ProviderContainer container, {
  List<CruxStatSegment> segments = const <CruxStatSegment>[],
  bool? expanded,
  VoidCallback? onToggle,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          const Spacer(),
          CruxStatsStrip(
            segments: segments,
            label: 'Stats',
            expanded: expanded,
            onToggle: onToggle,
          ),
        ],
      ),
    ),
  ),
);

void main() {
  group('disclosure', () {
    testWidgets('is collapsed by default — an ambient monitor must not take '
        '96px of the surface uninvited', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [CruxStatSegment(label: 'FPS', value: '60.0')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('FPS'), findsNothing);
    });

    testWidgets('expands and collapses on tap', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [CruxStatSegment(label: 'FPS', value: '60.0')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      expect(find.text('FPS'), findsOneWidget);
      expect(find.text('60.0'), findsOneWidget);

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      expect(find.text('FPS'), findsNothing);
    });

    testWidgets('honors a pre-set expanded state so a host can restore it '
        'from the workspace', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxStatsStripExpandedProvider.notifier).expanded = true;

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [CruxStatSegment(label: 'FPS', value: '60.0')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FPS'), findsOneWidget);
    });

    testWidgets('a host-supplied expanded state wins over the provider and '
        'routes taps to the host', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var toggles = 0;

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [CruxStatSegment(label: 'FPS', value: '60.0')],
          expanded: true,
          onToggle: () => toggles++,
        ),
      );
      await tester.pumpAndSettle();

      // Expanded even though the shared provider says collapsed — the host
      // (WaveCrux's per-tab session state) is the authority here.
      expect(container.read(cruxStatsStripExpandedProvider), isFalse);
      expect(find.text('FPS'), findsOneWidget);

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();
      // The tap reaches the host and leaves the provider alone; the host
      // rebuilds the strip with a new `expanded` when its own state moves.
      expect(toggles, 1);
      expect(container.read(cruxStatsStripExpandedProvider), isFalse);
    });
  });

  group('screen reader', () {
    Widget host(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              TextButton(onPressed: () {}, child: const Text('Open')),
              const Spacer(),
              const CruxStatsStrip(
                segments: <CruxStatSegment>[
                  CruxStatSegment(label: 'FPS', value: '60.0'),
                ],
                label: 'Stats',
                semanticLabel: 'Statistics',
                expandTooltip: 'Show Statistics',
                collapseTooltip: 'Hide Statistics',
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets('the disclosure is one button with one name and a state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(host(container));
      await tester.pumpAndSettle();

      var walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.stops.map((s) => s.line), <String>[
        'Open button',
        'Statistics button collapsed',
      ]);

      // A completed walk leaves focus back on its first stop.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(cruxStatsStripExpandedProvider), isTrue);

      walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.stops.last.line, 'Statistics button expanded');
      handle.dispose();
    });
  });

  group('segments', () {
    testWidgets('renders label and value for each', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxStatsStripExpandedProvider.notifier).expanded = true;

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [
            CruxStatSegment(label: 'FPS', value: '59.8'),
            CruxStatSegment(label: 'Memory', value: '412 MB'),
            CruxStatSegment(label: 'Queue', value: '17'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      for (final text in ['FPS', '59.8', 'Memory', '412 MB', 'Queue', '17']) {
        expect(find.text(text), findsOneWidget);
      }
    });

    testWidgets('draws a sparkline only with two or more points — one '
        'sample is not a trend', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxStatsStripExpandedProvider.notifier).expanded = true;

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [
            CruxStatSegment(label: 'One', value: '1', sparkline: [1]),
            CruxStatSegment(label: 'Two', value: '2', sparkline: [1, 2]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CruxSparkline), findsOneWidget);
    });

    testWidgets('renders a leading widget when supplied', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxStatsStripExpandedProvider.notifier).expanded = true;

      await tester.pumpWidget(
        _harness(
          container,
          segments: const [
            CruxStatSegment(
              label: 'Elaboration',
              value: '4.2 s',
              leading: Icon(Icons.sync, size: 12),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('scrolls rather than overflowing when segments do not fit', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxStatsStripExpandedProvider.notifier).expanded = true;

      await tester.pumpWidget(
        _harness(
          container,
          segments: <CruxStatSegment>[
            for (var i = 0; i < 30; i++)
              CruxStatSegment(label: 'Segment $i', value: '$i'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // A RenderFlex overflow in an ambient monitor would be a permanent
      // yellow-and-black stripe across the bottom of the app.
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('CruxSparkline', () {
    testWidgets('renders nothing for fewer than two points', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CruxSparkline(values: [1])),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles a flat series without dividing by zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CruxSparkline(values: [5, 5, 5, 5])),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('CruxFrameStats', () {
    test('empty reports a zero overrun ratio rather than NaN', () {
      expect(CruxFrameStats.empty.overrunRatio, 0);
    });

    test('overrunRatio is overruns over sampled frames', () {
      const stats = CruxFrameStats(
        framesPerSecond: 60,
        lastFrameMicros: 16000,
        budgetOverruns: 3,
        sampledFrames: 60,
        recentFrameMillis: <double>[],
      );
      expect(stats.overrunRatio, closeTo(0.05, 1e-9));
    });
  });

  group('cruxFormatBytes', () {
    test('whole units below a gigabyte, one decimal above', () {
      expect(cruxFormatBytes(512), '512 B');
      expect(cruxFormatBytes(2048), '2 KB');
      expect(cruxFormatBytes(5 * 1024 * 1024), '5 MB');
      expect(cruxFormatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('is binary, not decimal — 1 KB is 1024 B', () {
      expect(cruxFormatBytes(1024), '1 KB');
      expect(cruxFormatBytes(1000), '1000 B');
    });
  });

  group('cruxFrameStatsProvider publication throttle', () {
    /// A frame that took [millis] wall-clock, start to raster finish.
    FrameTiming timing(int millis) => FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: millis * 1000 ~/ 2,
      rasterStart: millis * 1000 ~/ 2,
      rasterFinish: millis * 1000,
      rasterFinishWallTime: millis * 1000,
    );

    test('the first batch publishes immediately — an ambient monitor that '
        'shows a dash for half a second reads as broken', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cruxFrameStatsProvider.notifier).debugRecordTimings([
        timing(10),
      ]);
      expect(container.read(cruxFrameStatsProvider).sampledFrames, 1);
    });

    test('a second batch inside the interval does not re-publish — this is '
        'what stops the strip feeding its own repaints', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxFrameStatsProvider.notifier)
        ..debugRecordTimings([timing(10)])
        ..debugRecordTimings([timing(10), timing(20)]);

      // Three frames counted, one publication: the visible state is still
      // the first batch's.
      expect(container.read(cruxFrameStatsProvider).sampledFrames, 1);
    });

    test('the throttled frames are counted, not dropped — the next '
        'publication carries all of them', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxFrameStatsProvider.notifier)
        ..debugRecordTimings([timing(10)])
        ..debugRecordTimings([timing(50), timing(50)])
        // Interval elapsed (driven, not waited out).
        ..publishInterval = Duration.zero
        ..debugRecordTimings([timing(10)]);

      final stats = container.read(cruxFrameStatsProvider);
      expect(stats.sampledFrames, 4);
      // Both 50 ms frames blew the 16.7 ms budget while publication was
      // suppressed, and both are in the tally.
      expect(stats.budgetOverruns, 2);
      expect(stats.recentFrameMillis.length, 4);
    });

    test('reset publishes at once and re-arms the throttle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cruxFrameStatsProvider.notifier)
        ..debugRecordTimings([timing(10)])
        ..reset();
      expect(container.read(cruxFrameStatsProvider), CruxFrameStats.empty);

      // A zeroed tally the user asked for must start climbing again
      // visibly, not after another half second of silence.
      notifier.debugRecordTimings([timing(10)]);
      expect(container.read(cruxFrameStatsProvider).sampledFrames, 1);
    });
  });

  group('CruxMemoryStats', () {
    test('reports no sample before the first read', () {
      expect(CruxMemoryStats.empty.hasSample, isFalse);
    });

    test('a real reading counts as a sample', () {
      const stats = CruxMemoryStats(
        residentBytes: 1024,
        recentResidentBytes: <double>[1024],
      );
      expect(stats.hasSample, isTrue);
    });
  });

  group('cruxMemoryStatsProvider', () {
    test('samples through the injectable reader', () async {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          cruxResidentBytesReaderProvider.overrideWithValue(() {
            calls++;
            return 1000 * calls;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(cruxMemoryStatsProvider);
      container.read(cruxMemoryStatsProvider.notifier)
        ..sampleNow()
        ..sampleNow();

      final stats = container.read(cruxMemoryStatsProvider);
      expect(stats.hasSample, isTrue);
      expect(stats.recentResidentBytes.length, greaterThanOrEqualTo(2));
    });

    test('a platform that cannot report RSS yields no sample rather than '
        'a zero reading', () async {
      final container = ProviderContainer(
        overrides: [
          cruxResidentBytesReaderProvider.overrideWithValue(() => 0),
        ],
      );
      addTearDown(container.dispose);

      container.read(cruxMemoryStatsProvider);
      container.read(cruxMemoryStatsProvider.notifier).sampleNow();

      expect(container.read(cruxMemoryStatsProvider).hasSample, isFalse);
    });
  });

  group('memory poll demand', () {
    test('nothing polls by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(cruxMemoryPollingActiveProvider), isFalse);
    });

    test('an expanded strip polls', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxStatsStripExpandedProvider.notifier).expanded = true;
      expect(container.read(cruxMemoryPollingActiveProvider), isTrue);
    });

    test('a tagged request polls with the strip collapsed — an App '
        'Diagnostics dialog opened over a collapsed strip must not show a '
        'permanently empty Memory section', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cruxMemoryPollRequestProvider.notifier).request('dialog');

      expect(container.read(cruxStatsStripExpandedProvider), isFalse);
      expect(container.read(cruxMemoryPollingActiveProvider), isTrue);
    });

    test('releasing the last tag stops polling', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxMemoryPollRequestProvider.notifier)
        ..request('dialog')
        ..release('dialog');

      expect(container.read(cruxMemoryPollingActiveProvider), isFalse);
    });

    test('one surface releasing does not stop another', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxMemoryPollRequestProvider.notifier)
        ..request('dialog')
        ..request('popover')
        ..release('dialog');

      expect(container.read(cruxMemoryPollingActiveProvider), isTrue);
    });

    test('request and release are both idempotent — a surface that leaks '
        'or double-fires a release must not wedge sampling', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cruxMemoryPollRequestProvider.notifier)
        ..request('dialog')
        ..request('dialog')
        ..release('dialog')
        ..release('dialog');

      expect(container.read(cruxMemoryPollRequestProvider), isEmpty);
      expect(container.read(cruxMemoryPollingActiveProvider), isFalse);
    });

    testWidgets('releasing the last tag cancels the timer even when nothing '
        'reads the provider again — a Notifier build only re-runs on demand, '
        'so pausing via `watch` left the poll running for the session', (
      tester,
    ) async {
      var reads = 0;
      final container = ProviderContainer(
        overrides: [
          cruxResidentBytesReaderProvider.overrideWithValue(() {
            reads++;
            return 4096;
          }),
        ],
      );
      addTearDown(container.dispose);

      // Bring the notifier up under demand, then drop the demand without
      // ever reading cruxMemoryStatsProvider again.
      container.read(cruxMemoryPollRequestProvider.notifier).request('dialog');
      container.read(cruxMemoryStatsProvider);
      await tester.pump(kCruxMemorySampleInterval * 2);
      container.read(cruxMemoryPollRequestProvider.notifier).release('dialog');

      final settled = reads;
      // Enough fake time for several more ticks. A live timer would sample;
      // and the binding's own pending-timer assertion fails the test too.
      await tester.pump(kCruxMemorySampleInterval * 5);

      expect(reads, settled);
    });

    test('history survives a pause — the samples that prompted a user to '
        'look must still be there when they open the surface', () {
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          cruxResidentBytesReaderProvider.overrideWithValue(() {
            calls++;
            return 1000 * calls;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(cruxMemoryPollRequestProvider.notifier).request('dialog');
      container.read(cruxMemoryStatsProvider);
      container.read(cruxMemoryStatsProvider.notifier)
        ..sampleNow()
        ..sampleNow();
      final before = container
          .read(cruxMemoryStatsProvider)
          .recentResidentBytes;

      container.read(cruxMemoryPollRequestProvider.notifier).release('dialog');

      expect(
        container.read(cruxMemoryStatsProvider).recentResidentBytes,
        before,
      );
    });
  });
}
