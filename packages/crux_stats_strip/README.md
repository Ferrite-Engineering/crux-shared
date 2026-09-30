# crux_stats_strip

The collapsible live statistics strip that docks above the status bar, plus
the app-level collectors every product shares.

Extracted from WaveCrux's shipped statistics strip when SimCrux and NetCrux
became the second and third consumers.

## What's here

| Symbol | Purpose |
|---|---|
| `CruxStatsStrip` | The collapsible strip. Renders whatever segments the host supplies. |
| `CruxStatSegment` | One labelled reading: value, optional sparkline, emphasis, leading widget. |
| `CruxSparkline` | Miniature history chart, ported from WaveCrux's `SparklineWidget`. |
| `cruxFrameStatsProvider` | FPS + frame-budget overruns, from real `SchedulerBinding` frame timings. |
| `cruxMemoryStatsProvider` | Process RSS on a 2 s poll. |
| `cruxStatsStripExpandedProvider` | Disclosure state, for the host to persist. |
| `cruxFormatBytes` | Byte formatting for the value column, so every product's Memory segment reads alike. |

## Usage

```dart
CruxStatsStrip(
  label: l10n.statsStripLabel,
  segments: [
    CruxStatSegment(label: 'FPS', value: fps.toStringAsFixed(1),
        sparkline: frameStats.recentFrameMillis),
    CruxStatSegment(label: 'Memory', value: formatBytes(rss),
        sparkline: memoryStats.recentResidentBytes),
    // …then whatever this product measures.
  ],
)
```

The strip has no product knowledge. SimCrux's queue depth and NetCrux's
layout time are the same type as the shared readings; the host decides the
order and the formatting — the strip will not guess whether `1024` means
bytes or tests. When a host *has* decided it means bytes, `cruxFormatBytes`
is here so the four Memory segments agree to the digit.

## Design decisions

**Collapsed by default.** An ambient monitor that appears uninvited takes
96 px from the surface the user actually came for. The disclosure row stays
visible so the feature is still discoverable.

**One disclosure row, optionally on the host's state.** Every product shows
the same triangle in the same place. `cruxStatsStripExpandedProvider` is the
default home for the bit, but a host that already persists it passes
`expanded:` + `onToggle:` and keeps its own — WaveCrux stores the strip's
disclosure per tab in its session sidecar and drives it from a keyboard
shortcut. The alternative, a host-side control *beside* the shared row,
puts two affordances on one piece of state.

**Overruns, not just FPS.** Average FPS hides jank: a window that holds
60 fps on average while dropping four frames during a scroll feels broken
and reads as fine. `budgetOverruns` does not average the stutter away.

**FPS from mean frame time, not frames per wall-second.** An idle app
produces no frames at all, and a wall-clock rate would report 0 fps for a
perfectly healthy window in which nothing needed redrawing.

**Frame stats publish at 2 Hz, not per frame.** The strip watches the frame
collector, so publishing every frame closed a loop: new state → strip
rebuild → a frame → a timings callback → new state. An idle window with the
strip open rendered flat out — a strange thing for a performance monitor to
do to the app it is measuring. Frames are still *counted* on every callback;
only the publication is throttled, so the history and the overrun tally stay
exact.

**Process RSS, not Dart heap.** On every product in the suite, memory is
dominated by things outside the Dart heap — a memory-mapped waveform, a
Yosys subprocess, an elkjs bundle in a JS runtime. Reporting only the Dart
heap would show a flat, reassuring line while the process grew to several
GB.

**The collectors are not auto-disposed.** History that reset whenever the
strip was collapsed would be useless exactly when the user expands it to
look at a stutter they just saw.

**Dimmed, not hidden, when idle.** A segment that disappears makes the
strip's layout jump every time a run starts and stops. `CruxStatEmphasis.dimmed`
keeps it in place.

**The segment row scrolls.** A `RenderFlex` overflow in an ambient monitor
would be a permanent yellow-and-black stripe across the bottom of the app.

**16.67 ms budget even on 120 Hz panels.** The real budget there is half
that, but flagging every frame between 8 and 16 ms would cry wolf
constantly when 16 ms still renders smoothly. This is an ambient signal,
not a profiler.
