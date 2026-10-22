// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:crux_linux_integration/src/desktop_entry.dart';
import 'package:test/test.dart';

void main() {
  group('buildDesktopEntry', () {
    const app = LinuxDesktopApp(
      appId: 'com.ferriteengineering.simcrux_pro',
      name: 'SimCrux Pro',
      comment: 'Simulation regression runner and dashboard for HDL testbenches',
      execName: 'simcrux_pro',
    );

    test('renders every field in the recipe order', () {
      final text = buildDesktopEntry(
        app,
        appImagePath: '/opt/SimCrux.AppImage',
      );
      expect(
        text,
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=SimCrux Pro\n'
        'Comment=Simulation regression runner and dashboard for HDL '
        'testbenches\n'
        'Exec="/opt/SimCrux.AppImage" %F\n'
        'Icon=com.ferriteengineering.simcrux_pro\n'
        'StartupWMClass=com.ferriteengineering.simcrux_pro\n'
        'Terminal=false\n'
        'Categories=Development;Electronics;\n',
      );
    });

    test('quotes the Exec path so a path with spaces is one argument', () {
      final text = buildDesktopEntry(
        app,
        appImagePath: '/home/me/Downloads/SimCrux Pro-0.1.0-x86_64.AppImage',
      );
      expect(
        text,
        contains(
          'Exec="/home/me/Downloads/SimCrux Pro-0.1.0-x86_64.AppImage" %F\n',
        ),
      );
    });

    test('Icon and StartupWMClass both key on the application id', () {
      final text = buildDesktopEntry(app, appImagePath: '/x.AppImage');
      expect(text, contains('Icon=com.ferriteengineering.simcrux_pro\n'));
      expect(
        text,
        contains('StartupWMClass=com.ferriteengineering.simcrux_pro\n'),
      );
    });

    // Without MimeType, "Open With" never lists the application: the entry
    // claims no type, so a file manager has no reason to offer it. The list
    // holds both kinds — the types the application declares itself and the
    // ones the system already maps — because both have to be claimed here to
    // be offered.
    test('names both our own types and the ones the system maps', () {
      final netcrux = LinuxDesktopApp(
        appId: 'com.ferriteengineering.netcrux',
        name: 'NetCrux',
        comment: 'Netlist explorer',
        execName: 'netcrux',
        fileTypes: [
          LinuxMimeType.declared(
            name: 'application/x-netcrux-project',
            comment: 'NetCrux project',
            extensions: const ['netcrux-project'],
            subClassOf: 'application/json',
          ),
          const LinuxMimeType.registered('text/x-verilog'),
          LinuxMimeType.unmapped(
            extensions: const ['f'],
            reason: 'a .f file is Fortran to every Linux desktop',
          ),
        ],
      );
      final text = buildDesktopEntry(netcrux, appImagePath: '/x.AppImage');
      expect(
        text,
        contains('MimeType=application/x-netcrux-project;text/x-verilog;\n'),
      );
      // Last line, after Categories, as the recipes write it.
      expect(text.trimRight().split('\n').last, startsWith('MimeType='));
    });

    // The list products carry today: bare names, which reach the entry and
    // install no mapping. Kept working until each product moves to fileTypes,
    // and reported by the coverage check until it does.
    test('still renders the superseded bare-name list', () {
      const bare = LinuxDesktopApp(
        appId: 'com.ferriteengineering.netcrux',
        name: 'NetCrux',
        comment: 'Netlist explorer',
        execName: 'netcrux',
        mimeTypes: ['application/x-netcrux-project', 'text/x-verilog'],
      );
      final text = buildDesktopEntry(bare, appImagePath: '/x.AppImage');
      expect(
        text,
        contains('MimeType=application/x-netcrux-project;text/x-verilog;\n'),
      );
      expect(buildMimePackage(bare), isNull);
      expect(
        checkLinuxMimeCoverage(
          bare,
          registeredExtensions: const {'netcrux-project'},
        ).problems.first,
        contains('install no mapping'),
      );
    });

    test('omits the key when the application claims nothing', () {
      final text = buildDesktopEntry(app, appImagePath: '/x.AppImage');
      expect(text, isNot(contains('MimeType')));
      expect(text, endsWith('Categories=Development;Electronics;\n'));
    });

    test('an extension left unmapped on purpose claims nothing', () {
      final onlyUnmapped = LinuxDesktopApp(
        appId: 'x',
        name: 'X',
        comment: 'c',
        execName: 'x',
        fileTypes: [
          LinuxMimeType.unmapped(
            extensions: const ['f'],
            reason: 'Fortran owns it',
          ),
        ],
      );
      final text = buildDesktopEntry(onlyUnmapped, appImagePath: '/x.AppImage');
      expect(text, isNot(contains('MimeType')));
    });

    test('honours a custom categories list', () {
      const custom = LinuxDesktopApp(
        appId: 'x',
        name: 'X',
        comment: 'c',
        execName: 'x',
        categories: ['Development', 'Electronics', 'Utility'],
      );
      final text = buildDesktopEntry(custom, appImagePath: '/x.AppImage');
      expect(text, contains('Categories=Development;Electronics;Utility;\n'));
    });

    // Schemes go in the hidden handler entry, never the main one: the main
    // entry is byte-identical whether or not the app declares any.
    test('declaring URL schemes leaves the main entry unchanged', () {
      const withSchemes = LinuxDesktopApp(
        appId: 'com.ferriteengineering.simcrux_pro',
        name: 'SimCrux Pro',
        comment:
            'Simulation regression runner and dashboard for HDL testbenches',
        execName: 'simcrux_pro',
        urlSchemes: ['simcrux'],
      );
      expect(
        buildDesktopEntry(withSchemes, appImagePath: '/opt/SimCrux.AppImage'),
        buildDesktopEntry(app, appImagePath: '/opt/SimCrux.AppImage'),
      );
    });

    test('quotes reserved characters in the Exec path', () {
      final text = buildDesktopEntry(app, appImagePath: r'/opt/a$b.AppImage');
      expect(
        text,
        contains(
          r'Exec="/opt/a\\$b.AppImage" %F'
          '\n',
        ),
      );
    });
  });

  group('buildUrlHandlerEntry', () {
    const wavecrux = LinuxDesktopApp(
      appId: 'com.ferriteengineering.wavecrux',
      name: 'WaveCrux',
      comment: 'Waveform viewer',
      execName: 'wavecrux',
      urlSchemes: ['wavecrux'],
    );

    test('renders the hidden %u entry', () {
      expect(
        buildUrlHandlerEntry(
          wavecrux,
          appImagePath: '/home/me/Apps/WaveCrux-1.2.0-x86_64.AppImage',
        ),
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=WaveCrux\n'
        'Exec="/home/me/Apps/WaveCrux-1.2.0-x86_64.AppImage" %u\n'
        'Icon=com.ferriteengineering.wavecrux\n'
        'Terminal=false\n'
        'NoDisplay=true\n'
        'MimeType=x-scheme-handler/wavecrux;\n',
      );
    });

    // The dock matches the running window to the main entry; a second entry
    // with the same StartupWMClass would compete for it.
    test('carries no StartupWMClass', () {
      final text = buildUrlHandlerEntry(wavecrux, appImagePath: '/x.AppImage');
      expect(text, isNot(contains('StartupWMClass')));
    });

    test('claims each scheme once, in declaration order', () {
      const two = LinuxDesktopApp(
        appId: 'x',
        name: 'X',
        comment: 'c',
        execName: 'x',
        urlSchemes: ['wavecrux', 'wavecrux-dev', 'wavecrux'],
      );
      expect(
        buildUrlHandlerEntry(two, appImagePath: '/x.AppImage'),
        contains(
          'MimeType=x-scheme-handler/wavecrux;x-scheme-handler/wavecrux-dev;\n',
        ),
      );
    });

    test('returns null when no scheme is declared', () {
      const none = LinuxDesktopApp(
        appId: 'x',
        name: 'X',
        comment: 'c',
        execName: 'x',
      );
      expect(buildUrlHandlerEntry(none, appImagePath: '/x.AppImage'), isNull);
    });

    for (final bad in ['WaveCrux', 'wave crux', '1wave', 'wave://', '', 'é']) {
      test('rejects the malformed scheme "$bad"', () {
        final app = LinuxDesktopApp(
          appId: 'x',
          name: 'X',
          comment: 'c',
          execName: 'x',
          urlSchemes: [bad],
        );
        expect(
          () => buildUrlHandlerEntry(app, appImagePath: '/x.AppImage'),
          throwsArgumentError,
        );
      });
    }

    test('the handler file sits beside the main entry', () {
      expect(
        urlHandlerDesktopFileName('com.ferriteengineering.wavecrux'),
        'com.ferriteengineering.wavecrux-url-handler.desktop',
      );
    });
  });

  // The Desktop Entry Specification's two layers: the Exec quoting rule, then
  // the general string escapes, which is why a literal backslash takes four.
  group('quoteDesktopExecArgument', () {
    final cases = <String, String>{
      '/opt/WaveCrux.AppImage': '"/opt/WaveCrux.AppImage"',
      '/home/me/My Apps/W.AppImage': '"/home/me/My Apps/W.AppImage"',
      '/a"b': r'"/a\\"b"',
      '/a`b': r'"/a\\`b"',
      r'/a$b': r'"/a\\$b"',
      r'/a\b': r'"/a\\\\b"',
      '/a%b': '"/a%%b"',
      '/100%u': '"/100%%u"',
      '/a\nb': r'"/a\nb"',
      '/a\tb': r'"/a\tb"',
      '/a\rb': r'"/a\rb"',
      "/it's": '"/it\'s"',
      '/ünï': '"/ünï"',
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      test('quotes ${input.replaceAll('\n', r'\n')}', () {
        expect(quoteDesktopExecArgument(input), expected);
      });
    }

    // Reading the entry back the way a launcher does must give the original
    // path: undo the general escapes, then the quoting rule.
    test('round-trips through a spec reader', () {
      String read(String value) {
        final general = StringBuffer();
        for (var i = 0; i < value.length; i++) {
          if (value[i] == r'\' && i + 1 < value.length) {
            final next = value[++i];
            general.write(switch (next) {
              's' => ' ',
              'n' => '\n',
              't' => '\t',
              'r' => '\r',
              r'\' => r'\',
              _ => '\\$next',
            });
          } else {
            general.write(value[i]);
          }
        }
        final s = general.toString();
        expect(s.startsWith('"') && s.endsWith('"'), isTrue);
        final inner = s.substring(1, s.length - 1);
        final out = StringBuffer();
        for (var i = 0; i < inner.length; i++) {
          if (inner[i] == r'\') {
            out.write(inner[++i]);
          } else if (inner[i] == '%') {
            expect(inner[++i], '%');
            out.write('%');
          } else {
            expect(inner[i], isNot('"'));
            out.write(inner[i]);
          }
        }
        return out.toString();
      }

      const nasty = 'C:/x/"q" `c` \$v \\b 50% \n\t\r end';
      expect(read(quoteDesktopExecArgument(nasty)), nasty);
    });
  });
}
