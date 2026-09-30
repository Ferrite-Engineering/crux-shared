// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

/// CXP §9.9 — the semantic stream coordinate.
///
/// The rules under test are the three the spec section turns on:
/// `stream_id` carries the index space, `attributes` are never identity, and
/// a malformed or unstatable coordinate is *dropped* rather than escalated.
void main() {
  group('CxpStreamCoordinate', () {
    test('round-trips through JSON with every field populated', () {
      final coord = CxpStreamCoordinate(
        streamId: CxpStreamCoordinate.riscvRvfiRetireStreamId,
        sequenceIndex: 4132,
        subId: '0',
        attributes: const <String, String>{
          CxpStreamCoordinate.riscvPcAttribute: '0x800001a4',
          CxpStreamCoordinate.riscvInsnAttribute: '0x40628533',
        },
      );
      final recovered = CxpStreamCoordinate.tryFromJson(
        jsonDecode(jsonEncode(coord.toJson())),
      );
      expect(recovered, equals(coord));
      expect(recovered!.sequenceIndex, 4132);
      expect(recovered.subId, '0');
      expect(
        recovered.attributes[CxpStreamCoordinate.riscvPcAttribute],
        '0x800001a4',
      );
    });

    test('omits absent optional fields rather than sending null', () {
      final json = CxpStreamCoordinate(
        streamId: 'riscv.formal.trace_step',
        sequenceIndex: 7,
      ).toJson();
      expect(json.containsKey('sub_id'), isFalse);
      expect(json.containsKey('attributes'), isFalse);
      expect(json['stream_id'], 'riscv.formal.trace_step');
      expect(json['sequence_index'], 7);
    });

    test('index 0 is a real coordinate, not an absent one', () {
      final coord = CxpStreamCoordinate(streamId: 's', sequenceIndex: 0);
      final recovered = CxpStreamCoordinate.tryFromJson(coord.toJson());
      expect(recovered, isNotNull);
      expect(recovered!.sequenceIndex, 0);
    });

    test('attributes are unmodifiable once constructed', () {
      final coord = CxpStreamCoordinate(
        streamId: 's',
        sequenceIndex: 1,
        attributes: const <String, String>{'a': 'b'},
      );
      expect(() => coord.attributes['c'] = 'd', throwsUnsupportedError);
    });

    group('tryFromJson returns null rather than throwing', () {
      // §6.1 obliges a receiver to ignore what it does not understand and
      // keep serving the connection. A peer that rejected a whole message
      // because its optional coordinate was malformed would fail worse than
      // one that landed at the top of the right artifact.
      test('for a non-object', () {
        expect(CxpStreamCoordinate.tryFromJson(null), isNull);
        expect(CxpStreamCoordinate.tryFromJson('riscv.rvfi.retire#4'), isNull);
        expect(CxpStreamCoordinate.tryFromJson(<Object?>[]), isNull);
      });

      test('for a missing or empty stream_id', () {
        expect(
          CxpStreamCoordinate.tryFromJson(<String, Object?>{
            'sequence_index': 4,
          }),
          isNull,
        );
        expect(
          CxpStreamCoordinate.tryFromJson(<String, Object?>{
            'stream_id': '',
            'sequence_index': 4,
          }),
          isNull,
        );
      });

      test('for a missing, negative or fractional sequence_index', () {
        for (final bad in <Object?>[null, -1, 4.5, '4']) {
          expect(
            CxpStreamCoordinate.tryFromJson(<String, Object?>{
              'stream_id': 's',
              'sequence_index': bad,
            }),
            isNull,
            reason: 'sequence_index $bad must not decode',
          );
        }
      });
    });

    test('accepts an integral double, which JSON transport can produce', () {
      final coord = CxpStreamCoordinate.tryFromJson(<String, Object?>{
        'stream_id': 's',
        'sequence_index': 4132.0,
      });
      expect(coord, isNotNull);
      expect(coord!.sequenceIndex, 4132);
    });

    test('drops non-string attribute entries instead of failing', () {
      final coord = CxpStreamCoordinate.tryFromJson(<String, Object?>{
        'stream_id': 's',
        'sequence_index': 1,
        'attributes': <String, Object?>{'good': 'yes', 'bad': 7},
      });
      expect(coord, isNotNull);
      expect(coord!.attributes, equals(<String, String>{'good': 'yes'}));
    });

    test('an empty sub_id decodes as absent, not as a lane named ""', () {
      final coord = CxpStreamCoordinate.tryFromJson(<String, Object?>{
        'stream_id': 's',
        'sequence_index': 1,
        'sub_id': '',
      });
      expect(coord!.subId, isNull);
    });

    test('the two registered stream ids are the spec literals', () {
      // These strings are the wire contract between SimCrux and WaveCrux.
      // A typo here is a silent no-op at the far end, so they are pinned.
      expect(
        CxpStreamCoordinate.riscvRvfiRetireStreamId,
        'riscv.rvfi.retire',
      );
      expect(
        CxpStreamCoordinate.riscvFormalTraceStepStreamId,
        'riscv.formal.trace_step',
      );
    });
  });

  group('coordinate on the wire', () {
    final coord = CxpStreamCoordinate(
      streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
      sequenceIndex: 7,
      subId: 'ch0',
      attributes: const <String, String>{'riscv.formal.check': 'insn_sub_ch0'},
    );

    test('RequestHighlight round-trips it beside the element', () {
      final req = RequestHighlight(
        element: const ElementId(kind: ElementKind.source, path: '/t.vcd'),
        coordinate: coord,
      );
      final recovered = RequestHighlight.fromJson(
        jsonDecode(jsonEncode(req.toJson())) as Map<String, Object?>,
      );
      expect(recovered, equals(req));
      expect(recovered.coordinate, equals(coord));
    });

    test('NotifySelection round-trips it beside the elements', () {
      final sel = NotifySelection(
        elements: const <ElementId>[
          ElementId(kind: ElementKind.source, path: '/t.vcd'),
        ],
        displayName: 'insn_sub_ch0',
        coordinate: coord,
      );
      final recovered = NotifySelection.fromJson(
        jsonDecode(jsonEncode(sel.toJson())) as Map<String, Object?>,
      );
      expect(recovered, equals(sel));
      expect(recovered.coordinate, equals(coord));
    });

    test('is absent from the payload when not set', () {
      const req = RequestHighlight(
        element: ElementId(kind: ElementKind.signal, path: 'top.a'),
      );
      expect(req.toJson().containsKey('coordinate'), isFalse);
      const sel = NotifySelection(
        elements: <ElementId>[ElementId(kind: ElementKind.signal, path: 'a')],
      );
      expect(sel.toJson().containsKey('coordinate'), isFalse);
    });

    test('a malformed coordinate does not sink the message', () {
      // The forward-compatibility rule in payload-field form: a 1.x peer
      // that garbled the coordinate still gets its highlight honoured.
      final recovered = RequestHighlight.fromJson(const <String, Object?>{
        'element': <String, Object?>{'kind': 'source', 'path': '/t.vcd'},
        'coordinate': <String, Object?>{'stream_id': 'oops'},
      });
      expect(recovered.element.path, '/t.vcd');
      expect(recovered.coordinate, isNull);
    });

    test('an unrecognised stream id decodes intact for the receiver to '
        'ignore', () {
      // The receiver decides it cannot act on `axi.transaction`; the
      // protocol layer must not decide that for it, or a peer could never
      // be upgraded independently.
      final recovered = NotifySelection.fromJson(const <String, Object?>{
        'elements': <Object?>[
          <String, Object?>{'kind': 'signal', 'path': 'a'},
        ],
        'coordinate': <String, Object?>{
          'stream_id': 'axi.transaction',
          'sequence_index': 17,
        },
      });
      expect(recovered.coordinate!.streamId, 'axi.transaction');
      expect(recovered.coordinate!.sequenceIndex, 17);
    });

    test('coordinate participates in message equality', () {
      final a = RequestHighlight(
        element: const ElementId(kind: ElementKind.source, path: '/t.vcd'),
        coordinate: coord,
      );
      const b = RequestHighlight(
        element: ElementId(kind: ElementKind.source, path: '/t.vcd'),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
