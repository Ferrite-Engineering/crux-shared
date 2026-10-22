# Changelog

## Unreleased

- **`Module.memories` and `Memory`.** The `memories` section Yosys writes
  after `proc` (name, width, size, start offset, attributes) is read instead
  of dropped, and written back only when non-empty.
- **The `fromJson` factories throw `FormatException`, as documented.** A
  field of the wrong JSON type (a string where an object belongs, a number
  where a list does, a non-integer `hide_name`) used to be a `TypeError`
  from a cast, which a caller catching the documented `FormatException`
  would not catch. Each factory now checks the shape it reads, and the
  message names the module, the cell, port or net, and the field.
- **Error messages repeat no more than 64 characters of the offending
  value**, followed by its length. `BitRef` used to interpolate the whole
  value, so a multi-megabyte bit produced a multi-megabyte message that was
  then copied into logs, the issue reporter's buffer and the interface.

## 0.1.0

- Initial release. `NetlistModel`, `Module`, `Cell`, `Net`, `Port`,
  `PortDirection`, `BitRef` (`NetBit` / `ConstantBit`) and `HierarchyNode` —
  an immutable mirror of Yosys `write_json`, lifted out of NetCrux when
  LintCrux's CDC engine became the second consumer.
- `YosysJsonParser` and `YosysJsonParseException`.
- Pure Dart; depends only on `package:meta`.
