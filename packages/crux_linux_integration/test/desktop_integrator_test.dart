// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const app = LinuxDesktopApp(
    appId: 'com.ferriteengineering.simcrux_pro',
    name: 'SimCrux Pro',
    comment: 'Simulation regression runner and dashboard for HDL testbenches',
    execName: 'simcrux_pro',
  );

  // The same application, with the file kinds a product supplies: one type of
  // its own, one the system already maps, and one extension deliberately left
  // to other applications.
  final mimeApp = LinuxDesktopApp(
    appId: app.appId,
    name: app.name,
    comment: app.comment,
    execName: app.execName,
    fileTypes: [
      LinuxMimeType.declared(
        name: 'application/x-simcrux-workspace',
        comment: 'SimCrux workspace',
        extensions: const ['simcrux-workspace'],
        subClassOf: 'application/json',
      ),
      const LinuxMimeType.registered('application/x-yaml'),
      LinuxMimeType.unmapped(
        extensions: const ['f'],
        reason: 'a .f file is Fortran to every Linux desktop',
      ),
    ],
  );

  late Directory tmp;
  late String home;
  late String appDir;
  late File appImage;

  /// Creates a fake AppDir hicolor tree with the given icon [sizes] and a fake
  /// AppImage file, returning the environment map an integrator would read.
  Map<String, String> env({List<String> sizes = const ['48x48', '256x256']}) {
    for (final size in sizes) {
      final apps = Directory(
        p.join(appDir, 'usr', 'share', 'icons', 'hicolor', size, 'apps'),
      )..createSync(recursive: true);
      File(
        p.join(apps.path, '${app.appId}.png'),
      ).writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    }
    return {'APPIMAGE': appImage.path, 'APPDIR': appDir};
  }

  File desktopFile() => File(
    p.join(home, '.local', 'share', 'applications', '${app.appId}.desktop'),
  );

  File iconFile(String size) => File(
    p.join(
      home,
      '.local',
      'share',
      'icons',
      'hicolor',
      size,
      'apps',
      '${app.appId}.png',
    ),
  );

  File mimeFile({String? dataHome}) => File(
    p.join(
      dataHome ?? p.join(home, '.local', 'share'),
      'mime',
      'packages',
      '${app.appId}.xml',
    ),
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crux_linux_integration_test');
    home = p.join(tmp.path, 'home');
    appDir = p.join(tmp.path, 'mnt');
    Directory(home).createSync(recursive: true);
    appImage = File(p.join(tmp.path, 'SimCrux Pro-0.1.0-x86_64.AppImage'))
      ..writeAsStringSync('appimage-bytes');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('integrate', () {
    test(
      'writes the .desktop entry and copies each present icon size',
      () async {
        final integrator = DesktopIntegrator(
          homeDir: home,
          env: env(),
          cacheRunner: (_, _) async {},
        );

        final result = await integrator.integrate(app);

        expect(result.status, DesktopIntegrationStatus.integrated);
        expect(result.iconCount, 2);
        expect(desktopFile().existsSync(), isTrue);
        expect(
          desktopFile().readAsStringSync(),
          contains('Exec="${appImage.path}" %F\n'),
        );
        expect(iconFile('48x48').existsSync(), isTrue);
        expect(iconFile('256x256').existsSync(), isTrue);
      },
    );

    test('tolerates a missing AppDir icon tree', () async {
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: {'APPIMAGE': appImage.path, 'APPDIR': appDir},
        cacheRunner: (_, _) async {},
      );

      final result = await integrator.integrate(app);

      expect(result.status, DesktopIntegrationStatus.integrated);
      expect(result.iconCount, 0);
      expect(desktopFile().existsSync(), isTrue);
    });

    test('skips with notAppImage when APPIMAGE is absent', () async {
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: const {},
        cacheRunner: (_, _) async {},
      );

      final result = await integrator.integrate(app);

      expect(result.status, DesktopIntegrationStatus.skipped);
      expect(result.skipReason, DesktopIntegrationSkipReason.notAppImage);
      expect(desktopFile().existsSync(), isFalse);
    });

    test('second call with an unchanged AppImage is a no-op', () async {
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (_, _) async {},
      );

      await integrator.integrate(app);
      // Prove the rewrite is skipped: delete the entry and confirm the second
      // call does not recreate it.
      desktopFile().deleteSync();

      final result = await integrator.integrate(app);

      expect(result.status, DesktopIntegrationStatus.skipped);
      expect(result.skipReason, DesktopIntegrationSkipReason.alreadyCurrent);
      expect(desktopFile().existsSync(), isFalse);
    });

    test('re-integrates when the AppImage mtime changes', () async {
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (_, _) async {},
      );

      await integrator.integrate(app);
      desktopFile().deleteSync();
      // Simulate an in-place update: same path, newer mtime.
      appImage.setLastModifiedSync(
        DateTime.now().add(const Duration(minutes: 5)),
      );

      final result = await integrator.integrate(app);

      expect(result.status, DesktopIntegrationStatus.integrated);
      expect(desktopFile().existsSync(), isTrue);
    });

    test('runs both cache-refresh commands', () async {
      final calls = <List<Object>>[];
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (exe, args) async => calls.add([exe, args]),
      );

      await integrator.integrate(app);

      final appsDir = p.join(home, '.local', 'share', 'applications');
      final hicolor = p.join(home, '.local', 'share', 'icons', 'hicolor');
      expect(calls, [
        [
          'update-desktop-database',
          [appsDir],
        ],
        [
          'gtk-update-icon-cache',
          ['-f', '-t', hicolor],
        ],
      ]);
    });

    test('a throwing cache runner does not fail integration', () async {
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (_, _) async => throw const ProcessException('x', []),
      );

      final result = await integrator.integrate(app);

      expect(result.status, DesktopIntegrationStatus.integrated);
      expect(desktopFile().existsSync(), isTrue);
    });

    // Without this file nothing maps *.simcrux-workspace, so the file is
    // typed as JSON, and the entry's MimeType= line matches nothing.
    test('installs the MIME package and compiles the database', () async {
      final commands = <String>[];
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (executable, arguments) async =>
            commands.add('$executable ${arguments.join(' ')}'),
      );

      final result = await integrator.integrate(mimeApp);

      expect(result.status, DesktopIntegrationStatus.integrated);
      expect(result.mimePackagePath, mimeFile().path);
      expect(
        mimeFile().readAsStringSync(),
        contains('<glob pattern="*.simcrux-workspace"/>'),
      );
      expect(
        commands.first,
        'update-mime-database ${p.join(home, '.local', 'share', 'mime')}',
        reason:
            'the MIME database is taught the type before the desktop '
            'database maps it to an application',
      );
      expect(
        commands,
        contains(
          'update-desktop-database '
          '${p.join(home, '.local', 'share', 'applications')}',
        ),
      );
    });

    test('an application with no type of its own writes no package', () async {
      final commands = <String>[];
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (executable, arguments) async => commands.add(executable),
      );

      final result = await integrator.integrate(app);

      expect(result.mimePackagePath, isNull);
      expect(mimeFile().existsSync(), isFalse);
      expect(commands, isNot(contains('update-mime-database')));
    });

    // A type that is withdrawn must not outlive the application: the
    // installed package is the only place the user's database learns it from.
    test('removes a package the application no longer declares', () async {
      final commands = <String>[];
      DesktopIntegrator integrator() => DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (executable, arguments) async => commands.add(executable),
      );

      await integrator().integrate(mimeApp);
      expect(mimeFile().existsSync(), isTrue);

      // A later release of the same AppImage that declares nothing.
      appImage.writeAsStringSync('appimage-bytes-v2');
      commands.clear();
      final result = await integrator().integrate(app);

      expect(result.status, DesktopIntegrationStatus.integrated);
      expect(result.mimePackagePath, isNull);
      expect(mimeFile().existsSync(), isFalse);
      expect(commands, contains('update-mime-database'));
    });

    test('a missing update-mime-database does not fail integration', () async {
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: env(),
        cacheRunner: (executable, _) async {
          if (executable == 'update-mime-database') {
            throw const ProcessException('update-mime-database', [], 'missing');
          }
        },
      );

      final result = await integrator.integrate(mimeApp);

      expect(result.status, DesktopIntegrationStatus.integrated);
      expect(mimeFile().existsSync(), isTrue);
    });

    test('an unwritable data home is caught, not thrown', () async {
      final integrator = DesktopIntegrator(
        // A file where the data home should be: every write under it fails.
        homeDir: appImage.path,
        env: env(),
        cacheRunner: (_, _) async {},
      );

      final result = await integrator.integrate(mimeApp);

      expect(result.status, DesktopIntegrationStatus.failed);
      expect(result.error, isNotNull);
    });

    test('honours XDG_DATA_HOME when the session sets it', () async {
      final dataHome = p.join(tmp.path, 'xdg-data');
      final integrator = DesktopIntegrator(
        homeDir: home,
        env: {...env(), 'XDG_DATA_HOME': dataHome},
        cacheRunner: (_, _) async {},
      );

      final result = await integrator.integrate(mimeApp);

      expect(result.mimePackagePath, mimeFile(dataHome: dataHome).path);
      expect(mimeFile(dataHome: dataHome).existsSync(), isTrue);
      expect(
        File(
          p.join(dataHome, 'applications', '${app.appId}.desktop'),
        ).existsSync(),
        isTrue,
      );
      expect(mimeFile().existsSync(), isFalse);
    });
  });
}
