// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:crux_linux_integration/src/desktop_entry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The host entry follows the newest AppImage, never the last one launched.
///
/// Two AppImages of one app sit side by side; whichever started last used to
/// rewrite the entry, so starting 1.1.0 after 1.2.0 sent the launcher back to
/// 1.1.0. The entry now carries `X-AppImage-Version`, an older AppImage leaves
/// a newer, still-existing one alone, and every write goes through a rename.
///
/// The "file system" is a fake `HOME` under a temporary directory, as in
/// `desktop_integrator_test.dart`.
void main() {
  const app = LinuxDesktopApp(
    appId: 'com.ferriteengineering.simcrux_pro',
    name: 'SimCrux Pro',
    comment: 'Simulation regression runner',
    execName: 'simcrux_pro',
  );

  late Directory tmp;
  late String home;

  File image(String version) =>
      File(p.join(tmp.path, 'SimCrux Pro-$version-x86_64.AppImage'));

  File desktopFile() => File(
    p.join(home, '.local', 'share', 'applications', '${app.appId}.desktop'),
  );

  Future<DesktopIntegrationResult> launch(
    String version, {
    LinuxDesktopApp theApp = app,
  }) {
    final file = image(version);
    if (!file.existsSync()) file.writeAsStringSync('appimage-$version');
    return DesktopIntegrator(
      homeDir: home,
      env: {'APPIMAGE': file.path},
      cacheRunner: (_, _) async {},
    ).integrate(theApp);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crux_linux_downgrade_test');
    home = p.join(tmp.path, 'home');
    Directory(home).createSync(recursive: true);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('the entry records the version of the AppImage it points at', () async {
    await launch('1.2.0');

    expect(
      desktopFile().readAsStringSync(),
      contains('X-AppImage-Version=1.2.0\n'),
    );
  });

  test('an older AppImage does not replace a newer one that exists', () async {
    await launch('1.2.0');
    final before = desktopFile().readAsStringSync();

    final result = await launch('1.1.0');

    expect(result.status, DesktopIntegrationStatus.skipped);
    expect(
      result.skipReason,
      DesktopIntegrationSkipReason.newerEntryPresent,
    );
    expect(desktopFile().readAsStringSync(), before);
    expect(before, contains('1.2.0'));
  });

  test('a newer AppImage replaces an older entry', () async {
    await launch('1.1.0');

    final result = await launch('1.2.0');

    expect(result.status, DesktopIntegrationStatus.integrated);
    expect(desktopFile().readAsStringSync(), contains('1.2.0-x86_64'));
    expect(
      desktopFile().readAsStringSync(),
      contains('X-AppImage-Version=1.2.0'),
    );
  });

  test('an older AppImage takes over once the newer one is gone', () async {
    await launch('1.2.0');
    image('1.2.0').deleteSync();

    final result = await launch('1.1.0');

    expect(result.status, DesktopIntegrationStatus.integrated);
    expect(desktopFile().readAsStringSync(), contains('1.1.0-x86_64'));
  });

  test('versions compare as numbers, not text', () async {
    await launch('1.9.0');

    final result = await launch('1.10.0');

    expect(result.status, DesktopIntegrationStatus.integrated);
    expect(desktopFile().readAsStringSync(), contains('1.10.0-x86_64'));
  });

  test('an entry without a version is rewritten as before', () async {
    desktopFile().parent.createSync(recursive: true);
    desktopFile().writeAsStringSync(
      buildDesktopEntry(app, appImagePath: image('9.9.9').path),
    );
    image('9.9.9').writeAsStringSync('x');

    final result = await launch('1.1.0');

    expect(result.status, DesktopIntegrationStatus.integrated);
    expect(desktopFile().readAsStringSync(), contains('1.1.0-x86_64'));
  });

  test('an explicit version overrides the file name', () async {
    const versioned = LinuxDesktopApp(
      appId: 'com.ferriteengineering.simcrux_pro',
      name: 'SimCrux Pro',
      comment: 'Simulation regression runner',
      execName: 'simcrux_pro',
      version: '3.0.0',
    );
    await launch('1.2.0', theApp: versioned);

    expect(
      desktopFile().readAsStringSync(),
      contains('X-AppImage-Version=3.0.0\n'),
    );
  });

  test('writes leave no temporary file behind', () async {
    await launch('1.2.0');

    final names = desktopFile().parent
        .listSync()
        .map((e) => p.basename(e.path))
        .toList();
    expect(names, ['${app.appId}.desktop']);
  });

  test('the entry is replaced by rename, not rewritten in place', () async {
    await launch('1.1.0');
    final before = desktopFile().statSync();
    // A reader holding the old file open keeps seeing the old content once the
    // path is replaced by a rename; an in-place write would change it.
    final reader = desktopFile().openSync();
    addTearDown(reader.closeSync);
    final oldText = String.fromCharCodes(reader.readSync(before.size));

    await launch('1.2.0');

    reader.setPositionSync(0);
    expect(String.fromCharCodes(reader.readSync(before.size)), oldText);
    expect(desktopFile().readAsStringSync(), isNot(oldText));
  }, skip: Platform.isWindows ? 'open files cannot be replaced' : null);

  test('the Exec path survives quoting, spaces and percent signs', () {
    for (final path in <String>[
      '/home/u/My Apps/SimCrux Pro-1.2.0-x86_64.AppImage',
      r'/home/u/a"b$c`d\e%f/x.AppImage',
    ]) {
      expect(
        parseDesktopExecProgram(buildDesktopEntry(app, appImagePath: path)),
        path,
      );
    }
  });

  test('version comparison', () {
    expect(isNewerAppImageVersion('1.2.0', '1.1.9'), isTrue);
    expect(isNewerAppImageVersion('1.2', '1.2.0'), isFalse);
    expect(isNewerAppImageVersion('1.2.0', '1.2.0'), isFalse);
    expect(isNewerAppImageVersion('2.0.0', '1.99.99'), isTrue);
    expect(isNewerAppImageVersion('x', '1.0.0'), isFalse);
    expect(
      appImageVersionFromFileName('/a/b/Wave-1.2.0-x86_64.AppImage'),
      '1.2.0',
    );
    expect(appImageVersionFromFileName('/a/b/Wave.AppImage'), isNull);
  });
}
