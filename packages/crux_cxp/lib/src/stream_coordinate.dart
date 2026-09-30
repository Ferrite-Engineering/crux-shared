// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/element_id.dart';
import 'package:meta/meta.dart';

/// A **semantic stream coordinate** — CXP §9.9.
///
/// An [ElementId] names a design object. It cannot name *one element of a
/// decoded stream*: the 4,132nd retired instruction, transaction #17, frame
/// #900. This does, with three fields and no domain vocabulary:
///
/// - [streamId] — which decoded stream this indexes, **and the index space
///   [sequenceIndex] counts in**;
/// - [sequenceIndex] — the element's position in that stream;
/// - [subId] — optional lane / channel discriminator (hart, port, virtual
///   channel).
///
/// Everything else the sender knows — program counter, address, opcode,
/// timestamp — travels in [attributes] and is **never identity**. A receiver
/// MUST be able to resolve the coordinate from the triple alone; attributes
/// exist so it can display, cross-check or explain the element it found, not
/// so it can find it. Unknown attribute keys MUST be ignored.
///
/// ### Why it is not ISA-shaped
///
/// The identical triple addresses an AXI transaction, an Ethernet frame, a USB
/// packet, a functional test vector and a video line. Shipping an
/// `(rvfi_order, pc, hart)` coordinate would have bought a second, parallel
/// coordinate type within a year and then carried both forever. The generality
/// costs the same field count and the same amount of producer and consumer
/// code; only the field *names* differ.
///
/// ### Absence beats approximation
///
/// A producer MUST NOT construct a coordinate whose [sequenceIndex] it cannot
/// state in the named stream's own index space. Omitting the coordinate is a
/// correct and expected outcome; a plausible index computed in a *different*
/// index space silently sends the receiver to the wrong element, which is
/// worse than sending it nowhere. This is the class's reason for having no
/// convenience constructor that guesses.
@immutable
class CxpStreamCoordinate {
  /// Creates a coordinate. [sequenceIndex] must be non-negative.
  CxpStreamCoordinate({
    required this.streamId,
    required this.sequenceIndex,
    this.subId,
    Map<String, String> attributes = const <String, String>{},
  }) : attributes = Map<String, String>.unmodifiable(attributes),
       assert(streamId.isNotEmpty, 'streamId must not be empty'),
       assert(sequenceIndex >= 0, 'sequenceIndex must be >= 0');

  /// Decodes a coordinate from its JSON object, or returns null when [json]
  /// is not a coordinate this peer can act on.
  ///
  /// **Returns null rather than throwing** for every malformed shape —
  /// missing `stream_id`, missing or negative `sequence_index`, a
  /// `sequence_index` that is not an integer. The coordinate is an optional
  /// payload field, and CXP §6.1 obliges a receiver to ignore what it does
  /// not understand and keep serving the connection; a peer that rejected the
  /// whole message because a coordinate was malformed would fail worse than
  /// one that simply landed at the top of the right artifact.
  static CxpStreamCoordinate? tryFromJson(Object? json) {
    final Map<String, Object?> map;
    if (json is Map<String, Object?>) {
      map = json;
    } else if (json is Map) {
      map = json.cast<String, Object?>();
    } else {
      return null;
    }
    final streamId = map['stream_id'];
    if (streamId is! String || streamId.isEmpty) return null;
    final rawIndex = map['sequence_index'];
    // A JSON number that round-tripped through a double (`4132.0`) is still
    // an integer index; a fractional one is not an index at all.
    final int index;
    if (rawIndex is int) {
      index = rawIndex;
    } else if (rawIndex is double && rawIndex == rawIndex.roundToDouble()) {
      index = rawIndex.toInt();
    } else {
      return null;
    }
    if (index < 0) return null;
    final subId = map['sub_id'];
    final rawAttributes = map['attributes'];
    final attributes = <String, String>{};
    if (rawAttributes is Map) {
      for (final entry in rawAttributes.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is String) attributes[key] = value;
      }
    }
    return CxpStreamCoordinate(
      streamId: streamId,
      sequenceIndex: index,
      subId: subId is String && subId.isNotEmpty ? subId : null,
      attributes: attributes,
    );
  }

  /// Stream identifier of the RISC-V RVFI retired-instruction stream —
  /// CXP §9.9.2, the protocol's one normative binding.
  ///
  /// [sequenceIndex] is RVFI's `rvfi_order`: the number of instructions
  /// retired before this one, so the first retirement of a run is index 0.
  /// [subId] is the hart id in decimal, and its absence means hart 0.
  static const String riscvRvfiRetireStreamId = 'riscv.rvfi.retire';

  /// Stream identifier of a bounded-proof counterexample trace's step
  /// sequence — CXP §9.9.2, part of the same binding rather than a second
  /// one.
  ///
  /// It addresses the *same retirement* as [riscvRvfiRetireStreamId], on the
  /// only index a model checker can state. A bounded-proof engine reports
  /// "the assertion failed at step 7"; it does not report `rvfi_order`, and
  /// the two cannot be converted without the trace, because the number of
  /// instructions a core retires in seven cycles is a property of the core
  /// under proof. The producer therefore states the step it observed and the
  /// receiver, which holds the decoded trace, does the conversion.
  /// [subId] is the RVFI channel the failing check was written against.
  static const String riscvFormalTraceStepStreamId = 'riscv.formal.trace_step';

  /// Attribute key: the retiring instruction's address (`rvfi_pc_rdata`).
  static const String riscvPcAttribute = 'riscv.pc';

  /// Attribute key: the encoded instruction word (`rvfi_insn`).
  static const String riscvInsnAttribute = 'riscv.insn';

  /// Attribute key: the RVFI channel a retirement was observed on.
  static const String riscvRvfiChannelAttribute = 'riscv.rvfi_channel';

  /// Attribute key: the ISA string the producer was configured with.
  static const String riscvIsaAttribute = 'riscv.isa';

  /// Attribute key: producer-defined provenance token. The Crux suite uses it
  /// to mark a coordinate derived from a replayed fixture rather than a live
  /// run, so a receiver never presents replayed evidence as measured.
  static const String riscvModeAttribute = 'riscv.mode';

  /// Which decoded stream this indexes, and the index space [sequenceIndex]
  /// counts in. An **open vocabulary**: a receiver that does not implement a
  /// stream id ignores the coordinate and honours the rest of the message.
  final String streamId;

  /// The element's position within [streamId]'s stream. Non-negative.
  final int sequenceIndex;

  /// Lane / channel discriminator within the stream — hart, port, virtual
  /// channel. Null means the stream has one lane, or its conventional
  /// default (hart 0 for the RVFI retire binding).
  final String? subId;

  /// Everything else the sender knows about this element. Advisory: never
  /// required to resolve the coordinate. Keys are namespaced like `metadata`
  /// keys and unrecognised ones are ignored.
  final Map<String, String> attributes;

  /// Encodes to the CXP §9.9 wire shape. Optional fields are omitted rather
  /// than sent null.
  Map<String, Object?> toJson() => <String, Object?>{
    'stream_id': streamId,
    'sequence_index': sequenceIndex,
    'sub_id': ?subId,
    if (attributes.isNotEmpty) 'attributes': attributes,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpStreamCoordinate &&
          other.streamId == streamId &&
          other.sequenceIndex == sequenceIndex &&
          other.subId == subId &&
          _attributesEqual(other.attributes, attributes));

  @override
  int get hashCode =>
      Object.hash(streamId, sequenceIndex, subId, attributes.length);

  @override
  String toString() =>
      'CxpStreamCoordinate($streamId#$sequenceIndex'
      '${subId == null ? '' : '/$subId'}'
      '${attributes.isEmpty ? '' : ', attrs=$attributes'})';
}

bool _attributesEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
