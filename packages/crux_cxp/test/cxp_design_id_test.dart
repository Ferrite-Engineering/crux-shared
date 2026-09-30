// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('cxpDesignIdForPath', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('cxp_design_id_');
    });

    tearDown(() {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('is a filesystem-safe 16-hex token', () {
      final designDir = Directory(p.join(tempRoot.path, 'cdc_capture'))
        ..createSync();
      final id = cxpDesignIdForPath(
        p.join(designDir.path, 'cdc_capture.vcd'),
      );
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('same dir yields same id regardless of which file in it', () {
      final designDir = Directory(p.join(tempRoot.path, 'cdc_capture'))
        ..createSync();
      // Files need not exist — the id is derived from the containing dir.
      final fromVcd = cxpDesignIdForPath(
        p.join(designDir.path, 'cdc_capture.vcd'),
      );
      final fromSource = cxpDesignIdForPath(
        p.join(designDir.path, 'cdc_capture.v'),
      );
      final fromYaml = cxpDesignIdForPath(
        p.join(designDir.path, 'simcrux.yaml'),
      );
      expect(fromVcd, equals(fromSource));
      expect(fromVcd, equals(fromYaml));
    });

    test('passing the directory itself matches passing a file inside it', () {
      final designDir = Directory(p.join(tempRoot.path, 'design_a'))
        ..createSync();
      final fromDir = cxpDesignIdForPath(designDir.path);
      final fromDirTrailingSlash = cxpDesignIdForPath('${designDir.path}/');
      final fromFile = cxpDesignIdForPath(
        p.join(designDir.path, 'top.v'),
      );
      expect(fromDir, equals(fromFile));
      expect(fromDir, equals(fromDirTrailingSlash));
    });

    test('different dirs yield different ids', () {
      final dirA = Directory(p.join(tempRoot.path, 'design_a'))..createSync();
      final dirB = Directory(p.join(tempRoot.path, 'design_b'))..createSync();
      final idA = cxpDesignIdForPath(p.join(dirA.path, 'top.v'));
      final idB = cxpDesignIdForPath(p.join(dirB.path, 'top.v'));
      expect(idA, isNot(equals(idB)));
    });

    test(
      'resolves symlinks so two paths to one real dir agree',
      () {
        final realDir = Directory(p.join(tempRoot.path, 'real'))..createSync();
        final linkPath = p.join(tempRoot.path, 'link');
        Link(linkPath).createSync(realDir.path);
        final fromReal = cxpDesignIdForPath(p.join(realDir.path, 'wave.vcd'));
        final fromLink = cxpDesignIdForPath(p.join(linkPath, 'wave.vcd'));
        expect(fromLink, equals(fromReal));
      },
      onPlatform: {
        'windows': const Skip('symlink perms differ on Windows'),
      },
    );

    test('total for a not-yet-created design (no throw)', () {
      final ghost = p.join(
        tempRoot.path,
        'does_not_exist',
        'plan.simcrux.yaml',
      );
      final id = cxpDesignIdForPath(ghost);
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('the token round-trips as a CxpWorkspaceStore filename', () async {
      final designDir = Directory(p.join(tempRoot.path, 'cdc_capture'))
        ..createSync();
      final vcd = File(p.join(designDir.path, 'cdc_capture.vcd'))
        ..writeAsStringSync('\$date\n\$end\n');
      final designId = cxpDesignIdForPath(vcd.path);

      final wsDir = Directory(p.join(tempRoot.path, 'workspace'))..createSync();
      final store = CxpWorkspaceStore(workspaceDirectory: wsDir.path);
      await store.upsertArtifact(
        designId: designId,
        kind: 'waveform',
        path: vcd.path,
        producer: 'wavecrux',
        topModule: 'tb_cdc_capture',
        basename: 'cdc_capture.vcd',
      );

      // The store wrote exactly `<design_id>.json`, so the token is a legal
      // filename, and the entry resolves back out by the same id.
      expect(
        File(p.join(wsDir.path, '$designId.json')).existsSync(),
        isTrue,
      );
      final resolved = store.resolveArtifact(designId, 'waveform');
      expect(resolved, isNotNull);
      expect(resolved!.path, equals(vcd.path));
    });
  });
}
