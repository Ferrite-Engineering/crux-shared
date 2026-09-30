# Changelog

## 0.1.0

- Initial release. `CruxStatsStrip` — the collapsed-by-default live statistics
  strip that docks above the status bar, extracted from WaveCrux when SimCrux
  and NetCrux became the second and third consumers. `CruxStatSegment`,
  `CruxStatEmphasis` and `CruxSparkline` render whatever readings the host
  supplies.
- `cruxFrameStatsProvider` — FPS from mean frame time plus frame-budget
  overruns, from real `SchedulerBinding` timings. Frames are counted on every
  callback but published at `kCruxFrameStatsPublishInterval`, so an open strip
  does not drive the frames it measures.
- `cruxMemoryStatsProvider` — process RSS, sampled only while something has
  requested it through `cruxMemoryPollRequestProvider`, so memory polling costs
  nothing while nobody is looking.
- `cruxStatsStripExpandedProvider` holds the disclosure state by default; a
  host that persists it itself passes `expanded` and `onToggle` instead.
- `CruxPaintTimingProbe` — a `RenderProxyBox` that times a subtree's paint,
  for per-pane render segments.
- `cruxFormatBytes`, so every product's Memory segment reads alike.
- The disclosure is one accessible button: one name (`semanticLabel`, falling
  back to `label`), an expanded or collapsed state, and the caption and
  tooltip kept out of the semantics tree so a screen reader does not read all
  three.
