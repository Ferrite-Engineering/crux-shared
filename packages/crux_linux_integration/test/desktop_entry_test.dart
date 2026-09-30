// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/crux_linux_integration.dart';
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
  });
}
