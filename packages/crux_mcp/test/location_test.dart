// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:test/test.dart';

/// Link test vectors, each (file, signal, time, the exact link).
///
/// The first is the example link of the reference server's JSON contract
/// (`cli-json-v1.md`, section 6, "Locations"); the next three are the vectors
/// of its output-contract test `the_link_matches_hand_derived_examples`,
/// copied byte for byte. The Rust builder must write exactly these, and so
/// must this one.
///
/// The last is derived by hand from the encoding rule (every UTF-8 byte but
/// `A-Z a-z 0-9 - . _ ~` as upper-case `%XX`): `(` `)` `!` `*` `'` are
/// `%28` `%29` `%21` `%2A` `%27`, which a URI component encoder would leave
/// alone.
final List<(String, String, McpTime, String)> _vectors = [
  (
    '/work/run 1/witness.vcd',
    'top.u_alu.result',
    McpTime(1500, McpTimeUnit.ns),
    'wavecrux://open?file=%2Fwork%2Frun%201%2Fwitness.vcd'
        '&signal=top.u_alu.result&t=1500ns',
  ),
  (
    '/work/c++/run 1/witness.vcd',
    'top.u_alu.result',
    McpTime(1500, McpTimeUnit.ns),
    'wavecrux://open?file=%2Fwork%2Fc%2B%2B%2Frun%201%2Fwitness.vcd'
        '&signal=top.u_alu.result&t=1500ns',
  ),
  (
    '/tmp/\u00b5-x~y.fst',
    'top.data[3]',
    McpTime(42, McpTimeUnit.tick),
    'wavecrux://open?file=%2Ftmp%2F%C2%B5-x~y.fst&signal=top.data%5B3%5D&t=42',
  ),
  (
    '/a&b=c?d#e.vcd',
    'tb.dut',
    McpTime(0, McpTimeUnit.us),
    'wavecrux://open?file=%2Fa%26b%3Dc%3Fd%23e.vcd&signal=tb.dut&t=0us',
  ),
  (
    "/x/(a)!*'.vcd",
    'top.a',
    McpTime(7, McpTimeUnit.tick),
    'wavecrux://open?file=%2Fx%2F%28a%29%21%2A%27.vcd&signal=top.a&t=7',
  ),
];

typedef _Builder = String Function(String file, String signal, McpTime time);

/// The oracle: each vector [build] does not write byte for byte.
List<String> _vectorProblems(_Builder build) => <String>[
  for (final (file, signal, time, link) in _vectors)
    if (build(file, signal, time) != link)
      '$file: ${build(file, signal, time)} != $link',
];

String _shipped(String file, String signal, McpTime time) =>
    waveCruxLink(file, signal: signal, time: time);

String _withEncoder(
  String Function(String) encode,
  String file,
  String signal,
  McpTime time,
) =>
    '${kWaveCruxLinkPrefix}file=${encode(file)}&signal=${encode(signal)}'
    '&t=${encode(time.linkValue)}';

void main() {
  group('links', () {
    test('the shipped builder writes every vector byte for byte', () {
      expect(_vectorProblems(_shipped), isEmpty);
    });

    test('mutation: a link built with another encoding fails the vectors', () {
      final mutants = <String, _Builder>{
        'URI component': (f, s, t) =>
            _withEncoder(Uri.encodeComponent, f, s, t),
        'URI query component': (f, s, t) =>
            _withEncoder(Uri.encodeQueryComponent, f, s, t),
        'lower-case hex': (f, s, t) => _withEncoder(
          (v) => mcpPercentEncode(v).replaceAllMapped(
            RegExp('%[0-9A-F]{2}'),
            (m) => m[0]!.toLowerCase(),
          ),
          f,
          s,
          t,
        ),
        'slash kept': (f, s, t) => _withEncoder(
          (v) => mcpPercentEncode(v).replaceAll('%2F', '/'),
          f,
          s,
          t,
        ),
      };
      for (final MapEntry(key: name, value: build) in mutants.entries) {
        expect(_vectorProblems(build), isNotEmpty, reason: name);
      }
    });

    test('a place link carries the file and the time only', () {
      expect(
        waveCruxLink('/w/a b.vcd', time: McpTime(10, McpTimeUnit.ps)),
        'wavecrux://open?file=%2Fw%2Fa%20b.vcd&t=10ps',
      );
      expect(waveCruxLink('/w/x.vcd'), 'wavecrux://open?file=%2Fw%2Fx.vcd');
    });

    test('a NetCrux link names a cell or a net', () {
      // `/` is %2F and `$` is %24.
      expect(
        netCruxLink('/w/top.json', kind: McpElementKind.cell, name: r'u/a$1'),
        'netcrux://open?file=%2Fw%2Ftop.json&cell=u%2Fa%241',
      );
      expect(
        netCruxLink(r'C:\w\t.json', kind: McpElementKind.net, name: 'n1'),
        'netcrux://open?file=C%3A%5Cw%5Ct.json&net=n1',
      );
    });

    test('refuses what the receiving app would refuse', () {
      final refused = throwsA(isA<McpLocationException>());
      expect(() => waveCruxLink('rel/x.vcd'), refused);
      expect(() => waveCruxLink(''), refused);
      expect(() => waveCruxLink('/x\n.vcd'), refused);
      expect(() => waveCruxLink('/x.vcd', signal: 'top. a'), refused);
      expect(() => waveCruxLink('/x.vcd', signal: 'top..a'), refused);
      expect(() => waveCruxLink('/x.vcd', signal: 'top.\u202ea'), refused);
      expect(() => waveCruxLink('/x.vcd', signal: ''), refused);
      expect(() => waveCruxLink('/${'a' * 4096}'), refused);
      expect(
        () => waveCruxLink('/x.vcd', signal: 'a' * 1025),
        refused,
      );
      expect(
        () => netCruxLink('/x', kind: McpElementKind.net, name: 'a b'),
        refused,
      );
      // 1,500 copies of U+00B5 are within the file bound (1,501 code
      // units), but each is two UTF-8 bytes, six link characters, so the
      // link passes 8,192.
      expect(() => waveCruxLink('/${'\u00b5' * 1500}'), refused);
    });

    test('absolute is judged on the text, for any host', () {
      expect(mcpIsAbsoluteText('/a'), isTrue);
      expect(mcpIsAbsoluteText(r'\\srv\share'), isTrue);
      expect(mcpIsAbsoluteText(r'C:\a'), isTrue);
      expect(mcpIsAbsoluteText('d:/a'), isTrue);
      expect(mcpIsAbsoluteText('C:a'), isFalse);
      expect(mcpIsAbsoluteText('a/b'), isFalse);
      expect(mcpIsAbsoluteText(''), isFalse);
    });
  });

  group('locations', () {
    final signal = McpSignalLocation(
      file: '/work/run 1/witness.vcd',
      signal: 'top.u_alu.result',
      time: McpTime(1500, McpTimeUnit.ns),
    );

    test('the signal form matches the contract example member for member', () {
      expect(
        jsonEncode(signal.toJson()),
        jsonEncode(<String, Object?>{
          'file': '/work/run 1/witness.vcd',
          'signal': 'top.u_alu.result',
          'time': <String, Object?>{'at': 1500, 'unit': 'ns'},
          'link': _vectors.first.$4,
        }),
      );
    });

    test('each form writes its members in order, null when empty', () {
      expect(
        jsonEncode(McpSourceLocation(file: 'rtl/alu.sv', line: 41).toJson()),
        '{"file":"rtl/alu.sv","line":41,"column":null}',
      );
      expect(
        jsonEncode(
          McpPlaceLocation(
            file: '/w.vcd',
            time: McpTime.ticks(3),
          ).toJson(),
        ),
        '{"file":"/w.vcd","time":{"at":3,"unit":"tick"}}',
      );
      expect(
        jsonEncode(
          McpElementLocation(
            file: '/d.json',
            kind: McpElementKind.net,
            name: 'n',
            module: 'top',
          ).toJson(),
        ),
        '{"file":"/d.json","net":"n","module":"top","src":null,"link":null}',
      );
      expect(
        jsonEncode(
          McpElementLocation(
            file: '/d.json',
            kind: McpElementKind.cell,
            name: 'u',
            module: 'top',
            src: McpSourceLocation(file: '/t.sv', line: 2, column: 5),
            linked: true,
          ).toJson(),
        ),
        '{"file":"/d.json","cell":"u","module":"top",'
        '"src":{"file":"/t.sv","line":2,"column":5},'
        '"link":"netcrux://open?file=%2Fd.json&cell=u"}',
      );
      expect(
        jsonEncode(McpTestLocation(test: 't', run: 'r').toJson()),
        '{"test":"t","run":"r","file":null,"line":null}',
      );
    });

    test('every form reads back to an equal location', () {
      final all = <McpLocation>[
        signal,
        McpSourceLocation(file: 'a.sv', line: 1, column: 2),
        McpPlaceLocation(file: '/w.vcd', time: McpTime(9, McpTimeUnit.fs)),
        McpElementLocation(
          file: '/d.json',
          kind: McpElementKind.cell,
          name: 'u',
          module: 'top',
          src: McpSourceLocation(file: '/t.sv', line: 2),
          linked: true,
        ),
        McpTestLocation(test: 't', run: 'r', file: '/log', line: 4),
      ];
      for (final location in all) {
        final back = McpLocation.fromJson(
          jsonDecode(jsonEncode(location.toJson())),
        );
        expect(back, location);
        expect(back.hashCode, location.hashCode);
        expect(back.file, location.file);
      }
    });

    test('reading refuses a link that is not the one its members give', () {
      final json = signal.toJson()..['link'] = 'wavecrux://open?file=/x';
      expect(
        () => McpLocation.fromJson(json),
        throwsA(isA<McpLocationException>()),
      );
      final element = McpElementLocation(
        file: '/d.json',
        kind: McpElementKind.net,
        name: 'n',
        module: 'm',
      ).toJson()..['link'] = 'netcrux://open?file=%2Fd.json&net=m';
      expect(
        () => McpLocation.fromJson(element),
        throwsA(isA<McpLocationException>()),
      );
    });

    test('reading refuses unknown and missing members and bad values', () {
      for (final bad in <Object?>[
        null,
        <String, Object?>{'file': 'a', 'line': 1},
        <String, Object?>{'file': 'a', 'line': 1, 'column': null, 'x': 1},
        <String, Object?>{'file': 'a', 'line': 0, 'column': null},
        <String, Object?>{'file': 'a', 'line': '1', 'column': null},
        <String, Object?>{
          'file': '/a',
          'time': <String, Object?>{'at': 1, 'unit': 'min'},
        },
        <String, Object?>{
          'file': '/a',
          'time': <String, Object?>{'at': -1, 'unit': 'ns'},
        },
        <String, Object?>{'file': '/a', 'time': 5},
        <String, Object?>{
          'file': 'rel.vcd',
          'time': <String, Object?>{'at': 1, 'unit': 'ns'},
        },
        <String, Object?>{
          'file': '/d',
          'cell': 'u',
          'module': 'm',
          'src': <String, Object?>{
            'test': 't',
            'run': 'r',
            'file': null,
            'line': null,
          },
          'link': null,
        },
        <String, Object?>{'test': 't', 'run': 'r', 'file': null, 'line': 3},
        <String, Object?>{'test': '', 'run': 'r', 'file': null, 'line': null},
      ]) {
        expect(
          () => McpLocation.fromJson(bad),
          throwsA(isA<McpLocationException>()),
          reason: '$bad',
        );
      }
    });

    test('a time is never negative and writes its link value', () {
      expect(() => McpTime(-1, McpTimeUnit.ns), throwsArgumentError);
      expect(McpTime(1500, McpTimeUnit.ns).linkValue, '1500ns');
      expect(McpTime.ticks(42).linkValue, '42');
      expect('${McpTime(1, McpTimeUnit.s)}', '1s');
      expect(McpTimeUnit.fromWireName('tick'), McpTimeUnit.tick);
      expect(McpTimeUnit.fromWireName('min'), isNull);
    });

    test('a location prints as its compact JSON', () {
      expect(
        McpSourceLocation(file: 'a', line: 1).toString(),
        '{"file":"a","line":1,"column":null}',
      );
      expect(
        const McpLocationException('m').toString(),
        'McpLocationException: m',
      );
    });
  });
}
