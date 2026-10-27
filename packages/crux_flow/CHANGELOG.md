# Changelog

## Unreleased

- **Readers refuse what is not a regular file.** A run directory is someone
  else's files: a step's `runtime.txt` linked to `/dev/zero` (which reports a
  length of zero and never ends) made `LibreLaneStepReader` read without
  bound, and a named pipe in place of a log, a metrics file or an OpenSTA
  listing blocked the reader for as long as nothing wrote to it. Every file
  read now goes through one check that it is a regular file once its links
  are followed, and no read goes more than one byte past the cap, even when
  the file grows after its length was taken.
- **`RtlRegisterSet` collects memories.** A register file such as PicoRV32's
  `cpuregs` stays a memory in a source elaboration, so it was no register of
  the set and a timing endpoint on one of its bits (`cpuregs[21][19]`)
  mapped to nothing. Each memory is now one register, from the `memories`
  section a `hierarchy; proc` elaboration writes or from the `$mem` and
  `$mem_v2` cells the `memory` passes leave, with its own declaration span,
  its write ports as blocks and the cone of their data as assignments. On
  the LibreLane PicoRV32 run, 98 of the worst 100 setup endpoints now map to
  `cpuregs` at register fidelity against the RTL elaboration (0 before).
  Fixes #52.
- **LibreLane run readers, one per verified minor line.**
  `LibreLaneReaders` detects the release from `resolved.json`
  (`meta.librelane_version`, then `meta.openlane_version`) and selects
  `LibreLane30RunReader`, verified for exactly 3.0.15 and 3.0.16
  (`kLibreLane30Verified`); any other release is read by the nearest older
  line's reader with `FlowRunRef.verified` false and a
  `FlowReaderUnsupported` reason. `LibreLaneStepReader` (status from
  `state_out.json`, ids from `flow.log`, steps turned off listed by name),
  `LibreLaneMetricsReader` (`final/metrics.json`, `metrics.csv` fallback)
  and `kLibreLane30Checks`: the metrics of every LibreLane 3.0 checker with
  its error and corner variables, judged by `evaluateLibreLaneChecks` the
  way the checker judges them, plus the antenna counts no checker fails on.
  The verdict comes from these records, never the exit status.
- **`OpenStaReportReader`**: OpenSTA `report_checks` text listings, read as
  a stream, sorted by slack, worst paths kept with clock-to-output, routing,
  logic and setup or hold segments.
- **`LibreLaneNetlist`**: the synthesis sidecar with `write_verilog`'s
  `_NNN_` names rebuilt, so timing-report instances map to the source
  design through their flip-flop's output net ("nearest register").
- **`FlowSarifWriter.librelane`**: one result per failing check (timing,
  DRC, LVS, antenna, physical, synthesis), the worst setup path anchored at
  its endpoint's source; a check the run's configuration only warns about
  is a `note`.
- **`NextpnrReportReader.parseNetTimings`** reads `detailed_net_timings`;
  `checkJsonDepth`, `decodeFlowJson` and `decodeFlowText` are exported.
- `MetricDiff` is held byte for byte to upstream `compare` output on the
  hand-built pair.
- `RtlRegisterSet` reads a register whose bits a synthesis tool split into
  one-bit nets named after the bits (`sum_q[23]`) as the one register
  (`sum_q`), and `registerNameOfNet` gives hosts the same rule;
  `LibreLaneCheck.defaultCorners` stands in for corner variables
  a run's configuration lacks; a LibreLane step's log is its largest.
- **Export namespace narrowed by 6 symbols.** `isToolLibraryPath`, `kFlowClockConstraintRule`, `kFlowSarifFingerprintKey`, `kFlowSarifSourceRoot`, `kFlowTimingPathRule`, `sharedPathSuffixLength` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

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
