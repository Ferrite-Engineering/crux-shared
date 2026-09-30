// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart' show BitRef;
import 'package:crux_netlist/src/bit_ref.dart' show BitRef;
import 'package:crux_netlist/src/module.dart';
import 'package:meta/meta.dart';

/// Root immutable representation of a Yosys-elaborated netlist.
///
/// A [NetlistModel] is what the elaboration pipeline produces: a `creator`
/// string identifying the Yosys version, and a collection of [modules]
/// keyed by name. The "top" module — the one declared `(* top *)` or
/// passed via `hierarchy -top` — is reported via [topModule].
///
/// This type is intentionally a thin, pure mirror of Yosys's `write_json`
/// schema rather than a richer "schematic" model. NetCrux's schematic
/// canvas builds its own derived views on top.
@immutable
class NetlistModel {
  /// Creates a netlist.
  const NetlistModel({
    required this.creator,
    required this.modules,
  });

  /// Parses a full Yosys `write_json` document.
  ///
  /// Throws [FormatException] if the top-level shape is wrong (missing
  /// `modules`, wrong type). Per-module / per-cell parse errors propagate
  /// from the inner [Module.fromJson] / [BitRef.fromJson] calls so the
  /// caller can surface a precise diagnostic.
  factory NetlistModel.fromJson(Map<String, Object?> json) {
    final creator = json['creator']?.toString() ?? '';
    final modulesRaw = json['modules'];
    if (modulesRaw is! Map<String, Object?>) {
      throw const FormatException('Yosys JSON is missing a `modules` object');
    }
    final modules = <String, Module>{
      for (final entry in modulesRaw.entries)
        entry.key: Module.fromJson(
          entry.key,
          entry.value! as Map<String, Object?>,
        ),
    };
    return NetlistModel(creator: creator, modules: modules);
  }

  /// Free-form string identifying the producer (typically a Yosys version
  /// banner). Useful for diagnostics; not semantically interpreted.
  final String creator;

  /// All modules in the elaboration, keyed by module name.
  final Map<String, Module> modules;

  /// The first module whose `top` attribute is set, or `null` if none of
  /// the modules are marked as the top.
  Module? get topModule {
    for (final module in modules.values) {
      if (module.isTop) return module;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  NetlistModel copyWith({String? creator, Map<String, Module>? modules}) {
    return NetlistModel(
      creator: creator ?? this.creator,
      modules: modules ?? this.modules,
    );
  }

  /// Serializes back to Yosys-compatible JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'creator': creator,
    'modules': <String, Object?>{
      for (final entry in modules.entries) entry.key: entry.value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetlistModel) return false;
    if (other.creator != creator) return false;
    if (other.modules.length != modules.length) return false;
    for (final entry in modules.entries) {
      if (other.modules[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = creator.hashCode;
    for (final entry in modules.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  @override
  String toString() =>
      'NetlistModel(creator: "$creator", modules: ${modules.length})';
}
