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
