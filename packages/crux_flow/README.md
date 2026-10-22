# crux_flow

Implementation-flow results for the suite: the models a flow run is read
into, METRICS2.1 metric keys with the LibreLane metric table, aggregation and
run-to-run comparison, Yosys source spans, the readers for nextpnr's report
and log, the mapping of a tool's cells back to source registers, SARIF
output, and the containment rule for the paths a run names. Pure Dart, so
the headless binaries read a run without Flutter.

```dart
import 'package:crux_flow/crux_flow.dart';

final reading = await const NextpnrReportReader().readFile('build/report.json');
switch (reading.verdict) {
  case FlowVerdict.met:
    print('every clock reached its constraint');
  case FlowVerdict.violated:
    for (final path in reading.result!.criticalPaths) {
      print('${path.startpoint} -> ${path.endpoint}: ${path.delayPs} ps');
    }
  case FlowVerdict.notRun || FlowVerdict.stopped || FlowVerdict.unrecognised:
    print(reading.problem);
}

final diff = MetricDiff.fromMetrics(goldMetrics, newMetrics);
print(diff.renderMarkdown(MetricDiffVerbosity.worse));
```

## Surface

| Symbol | Purpose |
|---|---|
| `FlowKind`, `FlowRunRef`, `FlowRun`, `FlowStep`, `FlowStepStatus` | One flow run read from its directory: which reader read it and whether that reader is verified for the tool version, the steps, final metrics, worst paths, artifacts and tool versions. Value equality and a JSON round trip. |
| `FlowVerdict` | `met`, `violated`, `stopped`, `notRun`, `unrecognised`, read from the tool's report or log, never its exit status. |
| `TimingPath`, `TimingSegment`, `TimingSegmentType`, `TimingPathOrigin`, `ClockEdge` | A timing path and its segments. Delays are integer picoseconds for comparison, with the tool's own nanoseconds kept for display. The segment-type set is open: an unseen type reads as `other` with the tool's word kept. |
| `SrcSpan`, `sharedPathSuffixLength`, `matchSourceBySuffix` | Yosys `src` spans (`file:l.c-l.c`, the short forms, `|`-joined lists, Windows paths), and matching a recorded path to a design's own file by trailing path segments. Nothing here opens a path a report names. |
| `RtlMapping`, `MappingFidelity` | Where a path end lands in the source, at `register`, `statement`, `span` or `unmapped`. There is no "exact" level. |
| `MetricKey`, `MetricModifier` | METRICS2.1 names: `base__part__modifier:value`, parsed as upstream LibreLane parses them. |
| `MetricDefinition`, `MetricDefinitionTable`, `librelaneMetricsV1`, `MetricAggregator` | The versioned metric table, ported from LibreLane's `library.py` with its provenance. |
| `aggregateMetrics` | Per-modifier values folded into their bases, as LibreLane's `aggregate_metrics`. |
| `MetricDiff`, `MetricComparison`, `MetricDiffStatistics`, `MetricDiffVerbosity`, `MetricChangeClass`, `MetricFilter` | Two runs' metrics compared with LibreLane `compare.py` semantics in decimal arithmetic, its four verbosity levels, its wildcard filter, and its Markdown table. |
| `MetricsDocument` | A `metrics.json` read under the input limits. |
| `NextpnrReportReader`, `NextpnrLogReader`, `NextpnrReport`, `NextpnrLog`, `NextpnrClockFrequency`, `NextpnrResourceUse`, `NextpnrReading` | nextpnr's `report.json` (one reader for iCE40, ECP5, Gowin and GateMate) and its log (for runs without `--report`). Met iff every clock reaches its constraint. |
| `NetlistSrcIndex`, `isStorageCell` | A synthesized design's cell and net names to their `SrcSpan`s, and whether a cell is a flip-flop or latch (by its ports, so an unseen library reads too). |
| `RtlRegisterSet`, `RtlRegister`, `isToolLibraryPath`, `sameSourceRange` | The source design's registers from its elaboration: declaration, assigning statements and block, named by instance path; the name stem of a synthesized flip-flop (`ra_SB_DFF_Q_2_DFFLC` is `ra`). |
| `RtlRegisterResolver`, `TimingPathMapping` | A path's start, end and every segment mapped to `register`, `statement`, `span` or `unmapped`, preferring the register. |
| `FlowSarifWriter` | Timing findings as SARIF 2.1.0 for any SARIF reader: no numbers in messages (baselines survive reruns), `crux-fnv1a64/1` fingerprints, URIs relative to `SRCROOT`, English only. |
| `FlowContainment`, `FlowContainmentException` | A run root, or a path a run's records name, must resolve inside the allowed directories, symlinks resolved. |
| `FlowInputLimits`, `FlowReadException`, `FlowReadFailure` | The byte, JSON-depth, key-length and line-length caps every reader applies, and the one exception every reader throws. |

## Inputs are hostile until read

A run directory may come from someone else's CI artifact. Every reader caps
the bytes it reads, refuses JSON nested past a depth, rejects non-finite
numbers, ignores keys it does not know, and drops (and counts) metric keys
over 256 characters. Each throws `FlowReadException`, a `FormatException`,
and nothing else; the fuzz tests hold every reader to that.

## Where the expectations come from

The tests' expectations never come from this package. The nextpnr fixtures
are captures from real place-and-route runs, with verdicts written from
nextpnr's own log lines; the metric table is checked row by row against an
extraction of upstream's `library.py`; aggregation and key parsing carry
upstream's own unit-test vectors; and the comparison's decimal strings were
checked against Python's `decimal` module. The mapping's expectations are
written from the designed-path RTL (`mapping.expected.json`), over Yosys's
own elaboration and synthesis of it. `test/fixtures/PROVENANCE.md` has the
detail.

## Exported on purpose

`tool/unused-exports.py` reports a symbol as *internal* when no other package and no product references it. These stay in the export namespace, for the reason given:

- **Named by an exported signature** (a host can receive or must name the type): `ClockEdge` (in `TimingPath`), `MetricAggregator` (in `MetricDefinition`), `MetricChangeClass` (in `MetricComparison`), `MetricDiffStatistics` (in `MetricDiff`), `MetricFilter` (in `MetricDiff`), `NextpnrLog` (in `NextpnrLogReader`), `NextpnrReading` (in `NextpnrLogReader`), `NextpnrResourceUse` (in `NextpnrReport`), `RtlRegister` (in `RtlRegisterSet`).
