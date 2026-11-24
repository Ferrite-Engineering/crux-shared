// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:edacrux_cxp/edacrux_cxp.dart';
import 'package:test/test.dart';

import 'support/rev10_schema.dart';

/// CXP §9.3.3 (rev. 11): the optional `time` field of `request_highlight` and
/// `notify_selection`.
///
/// Expected values are derived by hand from the grammar in §9.3.3, which is
/// the grammar of a `wavecrux://` link's `t`: `<digits>[.<digits>][unit]`,
/// unit one of fs ps ns us µs μs ms s, no unit meaning a whole tick count.
void main() {
  CxpTime s(int mantissa, int exponent) =>
      CxpTime.seconds(BigInt.from(mantissa), exponent);

  group('the grammar accepts', () {
    final accepted = <String, CxpTime>{
      // 1500 × 10^-9 s.
      '1500ns': s(1500, -9),
      // 1.5 × 10^-6 s = 1500 × 10^-9 s: the same instant.
      '1.5us': s(1500, -9),
      '2s': s(2, 0),
      // 0.5 × 10^-3 s = 500 × 10^-6 s.
      '0.5ms': s(500, -6),
      // U+00B5 MICRO SIGN and U+03BC GREEK SMALL LETTER MU are both `us`.
      '1µs': s(1, -6),
      '1μs': s(1, -6),
      '1us': s(1, -6),
      // 41.25 × 10^-9 s = 41250 × 10^-12 s.
      '41.25ns': s(41250, -12),
      '1fs': s(1, -15),
      // Half a femtosecond: 5 × 10^-16 s.
      '0.5fs': s(5, -16),
      '007ns': s(7, -9),
      '0s': s(0, 0),
      '0.000ns': s(0, 0),
      // No unit: a whole number of ticks.
      '42': CxpTime.ticks(42),
      '0': CxpTime.ticks(0),
    };
    for (final MapEntry(key: text, value: expected) in accepted.entries) {
      test('"$text"', () {
        expect(CxpTime.parse(text), expected);
        expect(CxpTime.tryParse(text), expected);
      });
    }

    test('24 digits either side of the point', () {
      final whole = '9' * 24;
      expect(CxpTime.parse(whole).isTicks, isTrue);
      expect(CxpTime.parse(whole).mantissa, BigInt.parse(whole));
      final fine = '1.${'0' * 23}1fs';
      expect(CxpTime.tryParse(fine), isNotNull);
    });

    test('a tick count and a time with a unit are never equal', () {
      expect(CxpTime.parse('0'), isNot(CxpTime.parse('0s')));
      expect(CxpTime.parse('42'), isNot(CxpTime.parse('42s')));
    });
  });

  group('the grammar refuses, never guessing a unit', () {
    const refused = <String>[
      '',
      ' 1ns',
      '1ns ',
      '1 ns',
      '1 ns',
      '-1ns',
      '+1ns',
      '-1',
      '1e3ns',
      '1e3',
      '1NS',
      '1Ns',
      '1MS',
      '1S',
      'ns',
      '.5ns',
      '5.ns',
      '1.5',
      '0.0',
      '1min',
      '1h',
      '1sec',
      '1as',
      '1.5.0ns',
      '1,5ns',
      '１ns',
      '0x10',
    ];
    for (final text in refused) {
      test('"$text"', () {
        expect(CxpTime.tryParse(text), isNull);
        expect(() => CxpTime.parse(text), throwsFormatException);
      });
    }

    test('more than 24 digits either side of the point', () {
      expect(CxpTime.tryParse('1' * 25), isNull);
      expect(CxpTime.tryParse('1.${'1' * 25}ns'), isNull);
    });

    test('more than 48 characters', () {
      // 24 + 1 + 24 + 2 = 51 characters, every part within its own bound.
      final long = '${'1' * 24}.${'1' * 24}fs';
      expect(long.length, 51);
      expect(CxpTime.tryParse(long), isNull);
    });
  });

  group('the wire form', () {
    test('a time with a unit is written in the largest whole unit', () {
      expect(CxpTime.parse('1.5us').toJson(), '1500ns');
      expect(CxpTime.parse('2000ms').toJson(), '2s');
      expect(CxpTime.parse('0.000ns').toJson(), '0s');
      expect(CxpTime.parse('1µs').toJson(), '1us');
      expect(CxpTime.parse('41.25ns').toJson(), '41250ps');
      expect(CxpTime.parse('0.5fs').toJson(), '0.5fs');
      expect(CxpTime.parse('1.000001fs').toJson(), '1.000001fs');
      expect(CxpTime.picoseconds(41250).toJson(), '41250ps');
    });

    test('a tick count is written as its decimal digits', () {
      expect(CxpTime.parse('007').toJson(), '7');
      expect(CxpTime.ticks(42).toJson(), '42');
    });

    test('what is written parses back to the same time', () {
      for (final text in const [
        '1500ns',
        '1.5us',
        '0.5ms',
        '41.25ns',
        '0.5fs',
        '1.000000000000000000000001fs',
        '999999999999999999999999s',
        '42',
        '0s',
      ]) {
        final time = CxpTime.parse(text);
        expect(CxpTime.parse(time.toJson()), time, reason: text);
      }
    });

    test('fromJson: absent or null is no time', () {
      expect(CxpTime.fromJson(null), isNull);
    });

    test('fromJson: a JSON number, or anything not a string, is refused', () {
      for (final value in <Object>[
        42,
        1.5,
        0,
        true,
        <Object?>[],
        <String, Object?>{},
      ]) {
        expect(
          () => CxpTime.fromJson(value),
          throwsFormatException,
          reason: '$value',
        );
      }
      expect(() => CxpTime.fromJson('5 ns'), throwsFormatException);
    });
  });

  group('constructors refuse what the grammar cannot carry', () {
    test('negative values', () {
      expect(() => CxpTime.seconds(BigInt.from(-1), 0), throwsArgumentError);
      expect(() => CxpTime.picoseconds(-1), throwsArgumentError);
      expect(() => CxpTime.ticks(-1), throwsArgumentError);
    });

    test('a time too long or too fine to write', () {
      // 10^30 s is 31 digits in seconds.
      expect(() => CxpTime.seconds(BigInt.one, 30), throwsArgumentError);
      // 10^-40 s is 25 fraction digits of a femtosecond.
      expect(() => CxpTime.seconds(BigInt.one, -40), throwsArgumentError);
    });
  });

  group('toTicks', () {
    test('converts to a timescale by hand-derived values', () {
      // 1.5 us on a 1 ns timescale: 1500 ticks.
      expect(
        CxpTime.parse('1.5us').toTicks(unitExponent: -9, factor: 1),
        BigInt.from(1500),
      );
      // 1.5 us on a 10 ns timescale: 150 ticks.
      expect(
        CxpTime.parse('1.5us').toTicks(unitExponent: -9, factor: 10),
        BigInt.from(150),
      );
      // 1 ns on a 100 ps timescale: 10 ticks.
      expect(
        CxpTime.parse('1ns').toTicks(unitExponent: -12, factor: 100),
        BigInt.from(10),
      );
      // 1 s on a 1 fs timescale: 10^15 ticks.
      expect(
        CxpTime.parse('1s').toTicks(unitExponent: -15, factor: 1),
        BigInt.from(10).pow(15),
      );
    });

    test('rounds to the nearest tick, a half up', () {
      // 15 ns / 10 ns = 1.5 -> 2; 14 ns / 10 ns = 1.4 -> 1.
      expect(
        CxpTime.parse('15ns').toTicks(unitExponent: -9, factor: 10),
        BigInt.two,
      );
      expect(
        CxpTime.parse('14ns').toTicks(unitExponent: -9, factor: 10),
        BigInt.one,
      );
      // 500 ps / 1 ns = 0.5 -> 1; 1 ps / 1 ns = 0.001 -> 0.
      expect(
        CxpTime.parse('500ps').toTicks(unitExponent: -9, factor: 1),
        BigInt.one,
      );
      expect(
        CxpTime.parse('1ps').toTicks(unitExponent: -9, factor: 1),
        BigInt.zero,
      );
    });

    test('a tick count is the count, whatever the timescale', () {
      expect(
        CxpTime.parse('42').toTicks(unitExponent: -9, factor: 10),
        BigInt.from(42),
      );
      expect(
        CxpTime.parse('42').toTicks(unitExponent: 0, factor: 0),
        BigInt.from(42),
      );
    });

    test('a time with a unit on no usable timescale is null', () {
      expect(CxpTime.parse('1ns').toTicks(unitExponent: -9, factor: 0), isNull);
    });
  });

  group('time on the wire (CXP §9.3.3)', () {
    const signal = ElementId(
      kind: ElementKind.signal,
      path: 'top.cpu.alu.result[7:0]',
    );

    Map<String, Object?> wire(CxpMessage m) =>
        jsonDecode(jsonEncode(m.toJson())) as Map<String, Object?>;

    test('RequestHighlight round-trips it beside the element', () {
      final req = RequestHighlight(
        element: signal,
        time: CxpTime.parse('41.25ns'),
      );
      expect(wire(req), {
        'element': {'kind': 'signal', 'path': 'top.cpu.alu.result[7:0]'},
        'time': '41250ps',
      });
      final recovered = RequestHighlight.fromJson(wire(req));
      expect(recovered, req);
      expect(recovered.time, CxpTime.picoseconds(41250));
    });

    test('NotifySelection round-trips it beside the elements', () {
      final sel = NotifySelection(
        elements: const [signal],
        time: CxpTime.ticks(42),
      );
      expect(wire(sel)['time'], '42');
      expect(NotifySelection.fromJson(wire(sel)), sel);
    });

    test('is absent from the payload when not set', () {
      expect(const RequestHighlight(element: signal).toJson(), {
        'element': signal.toJson(),
      });
      expect(
        const NotifySelection(elements: [signal]).toJson().containsKey('time'),
        isFalse,
      );
    });

    test('JSON null reads as absent', () {
      final req = RequestHighlight.fromJson(<String, Object?>{
        'element': signal.toJson(),
        'time': null,
      });
      expect(req.time, isNull);
    });

    test('a malformed time is a FormatException, so malformed_payload', () {
      for (final bad in <Object>[41250, '41250', '-1ns', '1.5', '1 ns', 'NS']) {
        final payload = <String, Object?>{
          'element': signal.toJson(),
          'time': bad,
        };
        if (bad == '41250') {
          // A bare string of digits is a tick count, not an error.
          expect(RequestHighlight.fromJson(payload).time, CxpTime.ticks(41250));
          continue;
        }
        expect(
          () => RequestHighlight.fromJson(payload),
          throwsFormatException,
          reason: '$bad',
        );
        expect(
          () => decodeCxpMessage(CxpMessageKind.requestHighlight, payload),
          throwsFormatException,
          reason: '$bad',
        );
        expect(
          () => NotifySelection.fromJson(<String, Object?>{
            'elements': [signal.toJson()],
            'time': bad,
          }),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('a retraction never carries a time and never fails on one', () {
      // §9.1.2: a retraction is never an error, so its time is not read.
      final retraction = NotifySelection.fromJson(const <String, Object?>{
        'elements': <Object?>[],
        'time': 'not a time',
      });
      expect(retraction.elements, isEmpty);
      expect(retraction.time, isNull);
      final sent = NotifySelection(
        elements: const <ElementId>[],
        time: CxpTime.ticks(1),
      );
      expect(sent.toJson(), {'elements': <Object?>[]});
    });

    test('time participates in message equality', () {
      expect(
        RequestHighlight(element: signal, time: CxpTime.ticks(1)),
        isNot(const RequestHighlight(element: signal)),
      );
      expect(
        RequestHighlight(element: signal, time: CxpTime.parse('1.5us')),
        RequestHighlight(element: signal, time: CxpTime.parse('1500ns')),
      );
      expect(
        NotifySelection(elements: const [signal], time: CxpTime.ticks(1)),
        isNot(const NotifySelection(elements: [signal])),
      );
    });
  });

  group('compatibility', () {
    // The §9.3.2 example, as a revision 10 peer sends it: no `time`.
    const rev10Payload = <String, Object?>{
      'element': {'kind': 'signal', 'path': 'top.cpu.alu.result[7:0]'},
      'metadata': {'crux.time_ps': 41250},
    };

    test('a peer that sends no time: its message decodes as before', () {
      final req = RequestHighlight.fromJson(rev10Payload);
      expect(req.time, isNull);
      expect(req.element.path, 'top.cpu.alu.result[7:0]');
      expect(req.metadata, {'crux.time_ps': 41250});
      // And a message built without a time is byte for byte what the
      // revision 10 encoder wrote.
      expect(
        jsonEncode(
          RequestHighlight(
            element: req.element,
            metadata: req.metadata,
          ).toJson(),
        ),
        jsonEncode(rev10Payload),
      );
      final sel = NotifySelection.fromJson(const <String, Object?>{
        'elements': [
          {'kind': 'signal', 'path': 'top.a'},
        ],
        'display_name': 'a',
      });
      expect(sel.time, isNull);
      expect(sel.displayName, 'a');
    });

    test('a peer that does not know the field ignores it', () {
      // Revision 11 payloads, a valid time, a tick count and a malformed
      // one, read by the revision 10 decoders: nothing throws, and the
      // element, metadata and coordinate are what the sender sent.
      for (final time in <Object?>['41250ps', '42', 41250, 'garbage']) {
        final payload = <String, Object?>{...rev10Payload, 'time': time};
        final old = rev10RequestHighlight(payload);
        expect(old.element.path, 'top.cpu.alu.result[7:0]');
        expect(old.element.kind, ElementKind.signal);
        expect(old.metadata, {'crux.time_ps': 41250});
        expect(old.coordinate, isNull);

        final oldSel = rev10NotifySelection(<String, Object?>{
          'elements': [
            {'kind': 'signal', 'path': 'top.a'},
          ],
          'display_name': 'a',
          'time': time,
        });
        expect(oldSel.elements.single.path, 'top.a');
        expect(oldSel.displayName, 'a');
        expect(oldSel.metadata, isEmpty);
      }
    });

    test('what this package sends, an older peer reads the same', () {
      final sent = RequestHighlight(
        element: const ElementId(kind: ElementKind.net, path: 'top.n'),
        time: CxpTime.parse('2us'),
        metadata: const {'crux.design_id': 'abc'},
      );
      final old = rev10RequestHighlight(
        jsonDecode(jsonEncode(sent.toJson())) as Map<String, Object?>,
      );
      expect(old.element, sent.element);
      expect(old.metadata, sent.metadata);
    });
  });
}
