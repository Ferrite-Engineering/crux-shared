# Changelog

## Unreleased

- **Mapping a tool's cells back to source registers.** `NetlistSrcIndex`
  (cell and net name to `SrcSpan` over a synthesized design, with
  `isStorageCell` judging flip-flops and latches by their ports),
  `RtlRegisterSet` (each register of the source elaboration with its
  declaration, assigning statements and block, walked through the instance
  tree under depth and instance bounds) and `RtlRegisterResolver`
  (register, statement, span or unmapped per path end and segment, with the
  name-stem heuristic; `TimingPathMapping.nearestMapped` for an unmapped
  segment). Tested on the designed-path FPGA fixtures against expectations
  written from the RTL.
- **`FlowSarifWriter`**: SARIF 2.1.0 timing findings, one per clock that
  misses its constraint, anchored at the worst path's endpoint. Messages
  carry no numbers, so a baseline keyed on rule, file and message survives
  a rerun; `partialFingerprints` holds the `crux-fnv1a64/1` signature of
  rule, endpoint register and clock; every URI is relative to `SRCROOT`
  and none names a machine path.
- **`FlowContainment`**: run roots and the paths a run's records name
  resolve inside the allowed directories (project root, ingest directory,
  run root, PDK root), with symlinks resolved as an open would, and fixed
  refusal reasons that never repeat the path.

## 0.1.0

- Initial release. Models for a flow run: `FlowKind`, `FlowRunRef`,
  `FlowRun`, `FlowStep` and `FlowStepStatus`, `FlowVerdict`, `TimingPath`
  and `TimingSegment`, `SrcSpan`, `RtlMapping` and `MappingFidelity`, each
  with value equality and a JSON round trip.
- METRICS2.1: `MetricKey` parsing and formatting, the versioned metric table
  `librelaneMetricsV1` (ported from LibreLane 3.0.16 `library.py`),
  `aggregateMetrics`, and `MetricDiff` with `compare.py` semantics, verbosity
  levels, filter and Markdown table, in decimal arithmetic.
- `NextpnrReportReader` and `NextpnrLogReader`, one reader for every nextpnr
  architecture.
- Input limits on every reader (`FlowInputLimits`) and one exception type
  (`FlowReadException`).
- Pure Dart; depends on `crux_io`, `crux_netlist`, `meta` and `path`.
