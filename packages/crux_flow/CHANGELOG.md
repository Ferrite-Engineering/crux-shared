# Changelog

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
