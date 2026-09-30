// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Direction of a module port or cell connection.
///
/// Yosys writes these as lowercase strings in its JSON output. [fromJson]
/// is permissive: unknown strings fall through to [PortDirection.inout]
/// rather than throwing, because Yosys occasionally emits unusual port
/// directions (e.g. `unknown`) that should not crash the elaboration
/// pipeline. Strict consumers can inspect the source string before calling.
enum PortDirection {
  /// Input port — driven from outside the module.
  input,

  /// Output port — drives outward from the module.
  output,

  /// Bidirectional port.
  inout;

  /// Parses a Yosys-emitted direction string. Comparisons are
  /// case-insensitive. An unrecognised string yields [PortDirection.inout].
  static PortDirection fromJson(String value) {
    switch (value.toLowerCase()) {
      case 'input':
        return PortDirection.input;
      case 'output':
        return PortDirection.output;
      case 'inout':
        return PortDirection.inout;
      default:
        return PortDirection.inout;
    }
  }

  /// JSON representation matching Yosys's lowercase encoding.
  String toJsonString() {
    switch (this) {
      case PortDirection.input:
        return 'input';
      case PortDirection.output:
        return 'output';
      case PortDirection.inout:
        return 'inout';
    }
  }
}
