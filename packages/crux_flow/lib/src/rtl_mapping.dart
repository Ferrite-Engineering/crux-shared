// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/src_span.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:meta/meta.dart';

/// How precisely a timing-path end was mapped back to the source design.
///
/// There is deliberately no "exact" level: a synthesized design keeps source
/// spans, not source truth, so line-exact is never claimed.
enum MappingFidelity {
  /// The end is a register the source declares, found by name.
  register('register'),

  /// The end maps to the statement that assigns a register, not to a name.
  statement('statement'),

  /// Only a source span is known, with no register behind it.
  span('span'),

  /// Nothing in the source could be related to the end.
  unmapped('unmapped');

  const MappingFidelity(this.wireName);

  /// The stable token written to JSON.
  final String wireName;

  /// The fidelity named by [wireName].
  static MappingFidelity fromWireName(String wireName) {
    for (final fidelity in values) {
      if (fidelity.wireName == wireName) return fidelity;
    }
    throw FlowReadException(
      FlowReadFailure.malformed,
      'unknown mapping fidelity ${describeFlowValue(wireName)}',
    );
  }
}

/// Where a timing-path end lands in the source design, and how sure that is.
@immutable
class RtlMapping {
  /// Creates a mapping.
  const RtlMapping({
    required this.fidelity,
    this.register,
    this.spans = const <SrcSpan>[],
  });

  /// Reads a mapping written by [toJson].
  factory RtlMapping.fromJson(Map<String, Object?> json) => RtlMapping(
    fidelity: MappingFidelity.fromWireName(
      requireString(json['fidelity'], 'fidelity'),
    ),
    register: optionalString(json['register'], 'register'),
    spans: [
      for (final (i, s) in optionalList(json['spans'], 'spans').indexed)
        withFlowContext(
          'spans[$i]',
          () => SrcSpan.fromJson(requireObject(s, 'span')),
        ),
    ],
  );

  /// The mapping for an end nothing could be related to.
  static const RtlMapping unmapped = RtlMapping(
    fidelity: MappingFidelity.unmapped,
  );

  /// The level reached.
  final MappingFidelity fidelity;

  /// The source register's name, at [MappingFidelity.register] and
  /// [MappingFidelity.statement].
  final String? register;

  /// The source spans behind the end, declaration first.
  final List<SrcSpan> spans;

  /// This mapping as JSON; [RtlMapping.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'fidelity': fidelity.wireName,
    if (register != null) 'register': register,
    if (spans.isNotEmpty) 'spans': [for (final s in spans) s.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RtlMapping &&
      other.fidelity == fidelity &&
      other.register == register &&
      listEquals(other.spans, spans);

  @override
  int get hashCode => Object.hash(fidelity, register, Object.hashAll(spans));

  @override
  String toString() => 'RtlMapping(${fidelity.wireName} $register)';
}
