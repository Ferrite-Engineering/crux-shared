// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The half that makes `MimeType=` mean anything for a type of ours. A file
// manager types a file first and looks for handlers second, so with nothing
// mapping `*.netcrux-project` the file is typed as JSON and the application
// is never offered, however completely the entry lists it.

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:test/test.dart';

LinuxDesktopApp _app(List<LinuxMimeType> types) => LinuxDesktopApp(
  appId: 'com.ferriteengineering.netcrux',
  name: 'NetCrux',
  comment: 'Netlist explorer',
  execName: 'netcrux',
  fileTypes: types,
);

void main() {
  group('LinuxMimeType', () {
    test('refuses to declare a type the system already maps', () {
      // Our <comment> would replace the description every file of that type
      // shows on the machine, including files we never open.
      expect(
        () => LinuxMimeType.declared(
          name: 'application/json',
          comment: 'Project file',
          extensions: const ['json'],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('already maps'),
          ),
        ),
      );
      expect(kLinuxSystemMimeTypes, contains('application/json'));
    });

    test('refuses a declaration with nothing to match', () {
      expect(
        () => LinuxMimeType.declared(
          name: 'application/x-netcrux-project',
          comment: 'NetCrux project',
          extensions: const [],
        ),
        throwsArgumentError,
      );
    });

    test('an unmapped record carries the reason it was left', () {
      expect(
        () => LinuxMimeType.unmapped(extensions: const ['f'], reason: '  '),
        throwsArgumentError,
      );
      final f = LinuxMimeType.unmapped(
        extensions: const ['f'],
        reason: 'a .f file is Fortran to every Linux desktop',
      );
      expect(f.isNamed, isFalse);
      expect(f.isDeclared, isFalse);
      expect(f.reason, contains('Fortran'));
    });

    test('a registered type declares nothing and is still named', () {
      const verilog = LinuxMimeType.registered('text/x-verilog');
      expect(verilog.isDeclared, isFalse);
      expect(verilog.isNamed, isTrue);
      expect(verilog.extensions, isEmpty);
    });
  });

  group('buildMimePackage', () {
    test('declares a type per glob, with its comment and parent', () {
      final xml = buildMimePackage(
        _app([
          LinuxMimeType.declared(
            name: 'application/x-netcrux-project',
            comment: 'NetCrux project',
            extensions: const ['netcrux-project', 'netcrux-workspace'],
            subClassOf: 'application/json',
          ),
        ]),
      );

      expect(
        xml,
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<mime-info '
        'xmlns="http://www.freedesktop.org/standards/shared-mime-info">\n'
        '  <mime-type type="application/x-netcrux-project">\n'
        '    <comment>NetCrux project</comment>\n'
        '    <sub-class-of type="application/json"/>\n'
        '    <glob pattern="*.netcrux-project"/>\n'
        '    <glob pattern="*.netcrux-workspace"/>\n'
        '  </mime-type>\n'
        '</mime-info>\n',
      );
    });

    test('leaves system types and unmapped records out', () {
      final xml = buildMimePackage(
        _app([
          LinuxMimeType.declared(
            name: 'application/x-netcrux-session',
            comment: 'NetCrux session',
            extensions: const ['netcrux'],
          ),
          const LinuxMimeType.registered('text/x-verilog'),
          LinuxMimeType.unmapped(
            extensions: const ['f'],
            reason: 'Fortran owns it',
          ),
        ]),
      );

      expect(xml, contains('application/x-netcrux-session'));
      expect(xml, isNot(contains('text/x-verilog')));
      expect(xml, isNot(contains('Fortran')));
      expect('$xml'.split('<mime-type').length - 1, 1);
    });

    // A .vcd is globbed to a Video CD playlist on a stock database.
    // Outranking that would retype every .vcd on the machine, so the waveform
    // type takes a glob below the default weight and is recognised by the
    // tokens a VCD header actually carries.
    test('shares a claimed extension by content, not by outranking it', () {
      final xml = buildMimePackage(
        _app([
          LinuxMimeType.declared(
            name: 'application/x-wavecrux-vcd',
            comment: 'Value change dump',
            extensions: const ['vcd'],
            globWeight: 40,
            magic: LinuxMimeMagic(
              priority: 60,
              matches: const [
                LinuxMimeMagicMatch(value: r'$date', offsetEnd: 64),
                LinuxMimeMagicMatch(value: r'$version', offsetEnd: 64),
              ],
            ),
          ),
        ]),
      );

      expect(
        xml,
        contains(
          '    <magic priority="60">\n'
          '      <match type="string" value="\$date" offset="0:64"/>\n'
          '      <match type="string" value="\$version" offset="0:64"/>\n'
          '    </magic>\n'
          '    <glob pattern="*.vcd" weight="40"/>\n',
        ),
      );
      expect(kLinuxSystemMimeTypes, contains('application/x-cdlink'));
      expect(kLinuxDefaultGlobWeight, 50);
    });

    test('a weight outside the allowed range is refused', () {
      expect(
        () => LinuxMimeType.declared(
          name: 'application/x-wavecrux-vcd',
          comment: 'Value change dump',
          extensions: const ['vcd'],
          globWeight: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => LinuxMimeMagic(matches: const [], priority: 60),
        throwsArgumentError,
      );
      expect(
        () => LinuxMimeMagic(
          matches: const [LinuxMimeMagicMatch(value: 'x')],
          priority: 101,
        ),
        throwsArgumentError,
      );
    });

    test('writes nothing when the application declares no type of its own', () {
      expect(buildMimePackage(_app(const [])), isNull);
      expect(
        buildMimePackage(_app([const LinuxMimeType.registered('text/plain')])),
        isNull,
      );
    });

    test('escapes what a product supplies', () {
      // A description reaches this file verbatim, and one unescaped `&`
      // makes the package unparseable — which update-mime-database reports
      // by ignoring it, leaving the association silently missing.
      final xml = buildMimePackage(
        _app([
          LinuxMimeType.declared(
            name: 'application/x-netcrux-project',
            comment: 'NetCrux <design> & "netlist" project',
            extensions: const ['netcrux-project'],
          ),
        ]),
      )!;

      expect(
        xml,
        contains(
          '<comment>NetCrux &lt;design&gt; &amp; "netlist" project</comment>',
        ),
      );
      expect(xml, isNot(contains('<design>')));
    });

    test('is the shape the specification describes', () {
      final xml = buildMimePackage(
        _app([
          LinuxMimeType.declared(
            name: 'application/x-netcrux-project',
            comment: 'NetCrux project',
            extensions: const ['netcrux-project'],
          ),
        ]),
      )!;
      final lines = xml.trimRight().split('\n');

      expect(lines.first, '<?xml version="1.0" encoding="UTF-8"?>');
      expect(
        lines[1],
        '<mime-info '
        'xmlns="http://www.freedesktop.org/standards/shared-mime-info">',
      );
      expect(lines.last, '</mime-info>');
      // Every element the spec's own examples use, and nothing else.
      final elements = RegExp('<(/?[a-z-]+)')
          .allMatches(xml)
          .map((m) => m.group(1)!)
          .where((e) => e != '?xml')
          .toSet();
      expect(elements, <String>{
        'mime-info',
        '/mime-info',
        'mime-type',
        '/mime-type',
        'comment',
        '/comment',
        'glob',
      });

      // And with every optional part, still only the elements the
      // specification defines, in the order its own rules are written in.
      final full = buildMimePackage(
        _app([
          LinuxMimeType.declared(
            name: 'application/x-wavecrux-vcd',
            comment: 'Value change dump',
            extensions: const ['vcd'],
            subClassOf: 'text/plain',
            globWeight: 40,
            magic: LinuxMimeMagic(
              matches: const [LinuxMimeMagicMatch(value: r'$date')],
            ),
          ),
        ]),
      )!;
      expect(
        RegExp('<(/?[a-z-]+)')
            .allMatches(full)
            .map((m) => m.group(1)!)
            .where((e) => e != '?xml')
            .toList(),
        <String>[
          'mime-info',
          'mime-type',
          'comment',
          '/comment',
          'sub-class-of',
          'magic',
          'match',
          '/magic',
          'glob',
          '/mime-type',
          '/mime-info',
        ],
      );
    });
  });

  group('checkLinuxMimeCoverage', () {
    final netcrux = _app([
      LinuxMimeType.declared(
        name: 'application/x-netcrux-project',
        comment: 'NetCrux project',
        extensions: const ['netcrux-project'],
        subClassOf: 'application/json',
      ),
      const LinuxMimeType.registered('text/x-verilog'),
      LinuxMimeType.unmapped(
        extensions: const ['f'],
        reason:
            'a .f file is Fortran to every Linux desktop, and claiming it '
            'would take the extension from Fortran editors',
      ),
    ]);

    test('the entry and the installed package agree', () {
      final report = checkLinuxMimeCoverage(
        netcrux,
        registeredExtensions: const {'netcrux-project', 'v', 'f'},
        registeredExtensionsOf: const {
          'text/x-verilog': ['v'],
        },
      );

      expect(report.problems, isEmpty, reason: '$report');
      expect(report.isComplete, isTrue);
      expect(
        report.deliberatelyUnmapped,
        containsPair('f', contains('Fortran')),
      );
      expect('$report', contains('deliberately unmapped: .f'));
    });

    test('an extension nothing on Linux maps is a problem', () {
      final report = checkLinuxMimeCoverage(
        netcrux,
        registeredExtensions: const {'netcrux-project', 'netcrux-workspace'},
      );

      expect(report.isComplete, isFalse);
      expect(
        report.problems.single,
        allOf(
          contains('.netcrux-workspace'),
          contains('nothing on Linux maps it'),
        ),
      );
    });

    // The generic types are listed here; the types of a product's own trade
    // are the product's to name, and it passes them in.
    test(
      'a declaration of a type the product knows is mapped is a problem',
      () {
        final wrong = _app([
          LinuxMimeType.declared(
            name: 'application/x-netcrux-source',
            comment: 'Design source',
            extensions: const ['xyz'],
          ),
        ]);

        final report = checkLinuxMimeCoverage(
          wrong,
          registeredExtensions: const {'xyz'},
          additionalSystemTypes: const {'application/x-netcrux-source'},
        );

        expect(report.problems.single, contains('already maps'));
      },
    );

    test('two types claiming one extension is a problem', () {
      final clashing = _app([
        LinuxMimeType.declared(
          name: 'application/x-netcrux-project',
          comment: 'NetCrux project',
          extensions: const ['crux-project'],
        ),
        LinuxMimeType.declared(
          name: 'application/x-edacrux-manifest',
          comment: 'EDACrux design manifest',
          extensions: const ['crux-project'],
        ),
      ]);

      final report = checkLinuxMimeCoverage(
        clashing,
        registeredExtensions: const {'crux-project'},
      );

      expect(report.problems.single, contains('claimed by both'));
    });
  });
}
