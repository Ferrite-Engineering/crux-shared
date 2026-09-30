# crux_netlist

The suite's shared elaborated-design model: a pure, immutable mirror of Yosys's
`write_json` document — modules, cells, nets, ports, bit references and the
hierarchy — plus the parser that builds it. Pure Dart, so a headless engine can
use it.

```dart
import 'package:crux_netlist/crux_netlist.dart';

final model = const YosysJsonParser().parse(rawJson);
final top = model.topModule;
final root = HierarchyNode.rootOf(model);
```

`crux_yosys` runs Yosys and captures `write_json`; this package is the other
half, the model that output becomes.

## Surface

| Symbol | Purpose |
|---|---|
| `NetlistModel` | The whole document: `creator`, `modules`, and `topModule`. |
| `Module`, `Cell`, `Net`, `Port`, `PortDirection` | One-to-one mirrors of the Yosys JSON objects, each with `fromJson` / `toJson`, `copyWith` and value equality. |
| `BitRef` — `NetBit`, `ConstantBit` (`ConstantBitValue`) | A single bit: a net id, or a constant `0` / `1` / `x` / `z`. |
| `HierarchyNode` | A path of instance names into the design, resolved against a model: parent, children, canonical path, the `Module` it names. |
| `YosysJsonParser`, `YosysJsonParseException` | String in, `NetlistModel` out; malformed input is a typed exception naming what was wrong. |

## Why it is shared

It was NetCrux's, because NetCrux was the only product that elaborated RTL. It
stopped being only NetCrux's when LintCrux's CDC engine needed the same graph:
clock-domain analysis runs over exactly the structure a schematic is drawn
from. Two copies of a netlist model would diverge on the first Yosys schema
change, and the two products would then disagree about what a design *is* —
the one thing cross-probing between them depends on.

## A thin mirror, on purpose

The model stays close to the wire format. Derived views — schematic layout,
domain partitions, fan-in and fan-out cones — belong to the consumer that needs
them, not here.

The package carries elaboration vocabulary (cells, nets, ports) because it *is*
the elaboration model. The domain-neutrality charter guard in `crux_workspace`
matches whole words, so identifiers such as `NetlistModel` do not trip it.
