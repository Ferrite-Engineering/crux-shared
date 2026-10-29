# crux_flow test fixtures: provenance

Nothing under a `*.expected.*` name here was produced by this package. Every
expectation comes from the tool's own output read independently, from the
RTL by construction, or from upstream source read without running it.

## `nextpnr/` and `fusesoc/`

A copy of the SimCrux open core's place-and-route fixtures
(`verification/fixtures/flow/nextpnr/` and `verification/fixtures/flow/fusesoc/`
in the `simcrux` repository, commit `88b29a8`), which hold the full
provenance: regenerator, command lines and the weekly live re-check.
Copied here because this package's tests run in this repository's CI, which
has no SimCrux checkout. Refresh by copying again; never edit a capture by
hand.

What was copied, and what was left out:

- Per case: `report.json` (`--report --detailed-timing-report`), `pnr.log`
  (`--log`), `exit_code.txt`, `max_frequency.txt` (the `grep` of nextpnr's
  own `Max frequency` lines) and `verdict.expected.json`.
- `rtl/` (the designs) and `mapping.expected.json` (registers and lines
  written from `rtl/path_adder.v`, not from any tool).
- From the FuseSoC run of `servant` on iCEBreaker, made without `--report`:
  its nextpnr log as `fusesoc/next.log`, and `verdict.expected.json`.
- Left out: the synthesized designs (`netlist.json`, 0.25 to 1.7 MB each).
  Their `src` attributes lost the user span before each `|` in the
  capture's path rewrite, so `synthesized/` (below) is a fresh capture
  instead.

Tools: OSS CAD Suite tag `2026-10-21` (Yosys 0.70+186, nextpnr
0.11.1-77-g6b438a1c), and FuseSoC 2.4.7 with Edalize 0.6.8; `versions.txt`
in each directory holds the exact lines the tools printed. Captured
2026-10-21. Machine paths were rewritten to `<work>`, `<home>` and
`<yosys-share>` by the regenerator.

Where the expectations come from:

- `verdict.expected.json`: the PASS or FAIL on nextpnr's own last
  `Max frequency` line, the constraint the case was run with, and nextpnr's
  exit status, written by hand after reading that line.
- `mapping.expected.json`: written from the RTL. The only deep path between
  registers in `path_adder.v` is `sum_q <= src_a + src_b` (line 16).

Eleven cases: `rescreen_ice40`, `rescreen_ice40_dsp` and `rescreen_ecp5`
(an 8 by 8 multiplier into an accumulator, at 100 MHz), and
`path_<family>_met` (12 MHz) and `path_<family>_violated` (1000 MHz) for
`ice40`, `ecp5`, `gowin` and `gatemate`. The four families write one report
schema; GateMate adds a `clk-skew` segment type, Gowin has no `source`
segment, and GateMate cell names are opaque.

## `elaboration/` and `synthesized/`

Yosys's own output for the two designs in `nextpnr/rtl/`, made with the
same OSS CAD Suite build as the place-and-route fixtures (tag `2026-10-21`,
Yosys 0.70+186), run from inside `nextpnr/rtl/` so the recorded source
paths are the bare file names. Captured 2026-10-21.

- `elaboration/path_adder.json` and `elaboration/top.json`: the source
  elaboration, exactly the script the suite's Yosys runner builds:

  ```
  yosys -q -p 'read_verilog "path_adder.v"; hierarchy -check -top path_adder; proc; write_json "<out>"'
  yosys -q -p 'read_verilog "top.v"; hierarchy -check -top top; proc; write_json "<out>"'
  ```

  Unedited. A live test re-elaborates both with whatever `yosys` is on
  `PATH` and requires the same registers, lines and files.

- `elaboration/regfile.v`, `elaboration/regfile.json` and
  `elaboration/regfile_mem.json`: a four-word register file and a plain
  register, hand-written for the memory cases, elaborated with the Yosys
  on `PATH` when captured (Yosys 0.69+post, Homebrew), run from inside `elaboration/`
  so the recorded paths are the bare file name:

  ```
  yosys -q -p 'read_verilog regfile.v; hierarchy -check -top regfile; proc; write_json regfile.json'
  yosys -q -p 'read_verilog regfile.v; hierarchy -check -top regfile; proc; memory -nomap; write_json regfile_mem.json'
  ```

  Unedited. The first keeps the memory in the `memories` section (the
  suite's Yosys runner script); the second has it as a `$mem_v2` cell. The
  expected lines in `memory_registers_test.dart` are read off `regfile.v`.

- `synthesized/path_adder_ice40.json`: the iCE40 synthesis of
  `path_adder.v`,

  ```
  yosys -q -p 'read_verilog "path_adder.v"; synth_ice40 -top path_adder; write_json "<out>"'
  ```

  reduced by `synthesized/trim_design.py`, which keeps only the top module
  (dropping the cell-library black boxes) and, span by span after splitting
  each `src` attribute on `|`, replaces the Yosys share directory prefix
  with `<yosys-share>`:

  ```
  python3 -I trim_design.py <out> path_adder_ice40.json <oss-cad-suite>/libexec/../share/yosys
  ```

  Nothing else is changed. Splitting first matters: a prefix rewrite over
  the whole attribute string also swallows the user span before the `|`.

The mapping tests take every expectation from `nextpnr/mapping.expected.json`
(written from the RTL); these files are inputs only.

## `librelane/`

A slim copy of the SimCrux open core's LibreLane fixtures
(`verification/fixtures/flow/librelane/` in the `simcrux` repository,
commit `115cbb9b`), whose `PROVENANCE.md` holds the full provenance: the
LibreLane releases (3.0.16 at `01ddb25`, 3.0.15 at `d7538ec`, each through
its own `shell.nix`), the open PDKs (sky130A, gf180mcuD and IHP sg13g2
through ciel at the versions both releases pin), the designs and
configurations, the regenerator and the weekly live re-run. Captured
2026-10-22 on macOS arm64.

Eight cases: on 3.0.16 `sky130A_met`, `sky130A_timing`, `sky130A_drc`,
`sky130A_antenna`, `sky130A_stopped`, `gf180mcuD_met` and `ihp-sg13g2_met`,
and on 3.0.15 `sky130A_met`. A ninth, 3.0.17 `sky130A_met`, is copied
from SimCrux's `3.0.17/sky130A_met` capture (LibreLane 3.0.17 at
`64ef808`, the same PDK versions, captured 2026-10-29 on Linux x64 by
SimCrux's weekly live workflow; SimCrux's `PROVENANCE.md` has the run).
Copied by a script that reads SimCrux's fixtures and writes these; the same
copy rerun over SimCrux's 3.0.16 `sky130A_met` and `sky130A_timing`
reproduces the committed files byte for byte, apart from line endings and
the `differs_by_platform` note SimCrux added to the timing case's
expectation afterwards. Per case:

- `case.expected.json` and `exit_code.txt`, unchanged. The expectations
  were written by hand from each configuration's intent and from
  LibreLane's records read with `jq` and `ls`, never by a reader.
- `run/flow.log`, `run/error.log`, `run/warning.log`,
  `run/final/metrics.json` and `run/final/metrics.csv`, unchanged.
- `run/resolved.json`: only the keys the readers read (`meta`, `PDK`,
  `STD_CELL_LIBRARY`, `DESIGN_NAME`, `CLOCK_PORT`, `CLOCK_PERIOD`, every
  `*VIOLATION_CORNERS`, every `ERROR_ON_*`, `WIRE_LENGTH_THRESHOLD`), values
  unchanged.
- Every step directory, with a zero-byte `config.json` (every step has
  one), a zero-byte `state_out.json` where the step wrote one (the readers
  key on its presence), and `runtime.txt` unchanged.
- The post-PnR STA step's corner directories with `max.rpt` and `min.rpt`:
  the nominal typical corner's listings unchanged for 3.0.16 `sky130A_met`,
  `sky130A_timing`, 3.0.15 `sky130A_met` and 3.0.17 `sky130A_met`,
  zero-byte placeholders for
  every other corner and case (as SimCrux trims them).
- `06-yosys-synthesis/path_adder.nl.v.json` (the synthesis sidecar),
  unchanged, for `sky130A_timing` only.

`librelane/mapping.expected.json` is SimCrux's, written from
`path_adder.v`: the worst register-to-register path starts at `src_a` or
`src_b` and ends at `sum_q`. The OpenSTA tests count paths and read slacks
from the listings with plain regular expressions, independently of the
reader.

## `metric_diff/`

Upstream LibreLane's own `compare` output, the oracle for `MetricDiff`.
`handbuilt/gold.metrics.json` and `handbuilt/new.metrics.json` are a pair
written by hand from the metric names and aggregators of LibreLane 3.0.16
`library.py` (no run data: the upstream librelane-metrics repository has no
licence, so nothing derived from it is here). Each `compare_py.<v>.md` is
what LibreLane 3.0.16 (`VERSION`), installed from its tag into a scratch
virtual environment, printed for

```
python -m librelane.common.metrics compare --table-verbosity <V> -f <filter> gold.metrics.json new.metrics.json
```

with `<V>` each of `CRITICAL`, `WORSE`, `CHANGED`, `ALL`, and the filter
`*` (`handbuilt/`) or `DEFAULT` (`handbuilt_default/`, the same pair).
Captured 2026-10-22. The regenerator is SimCrux's
`tool/flow/regen_metric_diff_parity.sh`; it writes only `compare_py.*.md`.

## `metrics/library-3.0.16.tsv`

The metric definitions of upstream LibreLane 3.0.16
(`librelane/common/metrics/library.py`, tag `3.0.16`, commit `01ddb25`),
extracted with Python's `ast` module from the source text without importing
or running it:

```
python3 -I -c "import ast,sys; t=ast.parse(open(sys.argv[1]).read()); ..." library.py
```

One row per `Metric(...)` call, in file order: name, `aggregator`,
`higher_is_better`, `critical`, `dont_aggregate`, each as written in the
source (`None` where the argument is absent). The package's own table is
held to it row by row.

## `metrics/upstream_vectors.json`

The inputs and expected outputs of upstream LibreLane's own unit tests for
`parse_metric_modifiers` and `aggregate_metrics`
(`test/common/test_common.py` at tag `3.0.16`), transcribed by hand.
