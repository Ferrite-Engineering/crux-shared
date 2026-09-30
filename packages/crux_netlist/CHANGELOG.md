# Changelog

## 0.1.0

- Initial release. `NetlistModel`, `Module`, `Cell`, `Net`, `Port`,
  `PortDirection`, `BitRef` (`NetBit` / `ConstantBit`) and `HierarchyNode` —
  an immutable mirror of Yosys `write_json`, lifted out of NetCrux when
  LintCrux's CDC engine became the second consumer.
- `YosysJsonParser` and `YosysJsonParseException`.
- Pure Dart; depends only on `package:meta`.
