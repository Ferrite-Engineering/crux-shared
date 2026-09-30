// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_project/crux_project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _parser = CruxProjectParser();
const _planner = CruxProjectOpenPlanner();

/// The conventional manifest name for a design directory: its basename plus
/// the suite extension.
String manifestNameFor(String dir) =>
    '${p.basename(dir)}.$kCruxProjectExtension';

CruxProjectManifest parse(String yaml, {String dir = '/designs/cdc_capture'}) =>
    _parser.parse(yaml, manifestPath: p.join(dir, manifestNameFor(dir)));

void main() {
  group('parsing — the one strict rule', () {
    test('a missing version is fatal', () {
      // This check is the only thing separating "a manifest" from "some YAML
      // file the user happened to select".
      expect(
        () => parse('name: foo\n'),
        throwsA(
          isA<CruxProjectFormatException>().having(
            (e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });

    test('a non-integer version is fatal', () {
      expect(
        () => parse('version: "1"\n'),
        throwsA(isA<CruxProjectFormatException>()),
      );
      expect(
        () => parse('version: 1.5\n'),
        throwsA(isA<CruxProjectFormatException>()),
      );
    });

    test('a version below 1 is fatal', () {
      expect(
        () => parse('version: 0\n'),
        throwsA(isA<CruxProjectFormatException>()),
      );
    });

    test('invalid YAML is fatal and names the file', () {
      expect(
        () => parse('version: 1\n  bad: [indent\n'),
        throwsA(
          isA<CruxProjectFormatException>().having(
            (e) => e.path,
            'path',
            endsWith('cdc_capture.crux-project'),
          ),
        ),
      );
    });

    test('a non-mapping document is fatal', () {
      expect(
        () => parse('- just\n- a\n- list\n'),
        throwsA(isA<CruxProjectFormatException>()),
      );
    });

    test('version alone is valid — and empty', () {
      final m = parse('version: 1\n');
      expect(m.version, 1);
      expect(m.isEmpty, isTrue);
      // A design that has not produced anything yet still deserves a manifest.
      expect(m.warnings, isEmpty);
    });
  });

  group('parsing — everything else degrades to a warning', () {
    test('a kind this build does not consume is kept, not rejected', () {
      // Forward tolerance: kinds are opaque manifest keys, so a key a later
      // suite version introduces is retained verbatim and the file still
      // opens. Nothing here decides which keys are "known".
      final m = parse('''
version: 1
artifacts:
  waveform: sim/dump.vcd
  coverage: cov/merged.ucdb
''');
      expect(m.rawArtifacts['waveform'], 'sim/dump.vcd');
      expect(m.rawArtifacts['coverage'], 'cov/merged.ucdb');
      expect(m.artifact('coverage'), endsWith(p.join('cov', 'merged.ucdb')));
      expect(
        m.warnings,
        isEmpty,
        reason: 'unrecognized kinds are expected, not odd',
      );
    });

    test('a future schema version warns and keeps what it understands', () {
      final m = parse('''
version: 99
artifacts:
  waveform: sim/dump.vcd
''');
      expect(m.version, 99);
      expect(m.artifact('waveform'), endsWith(p.join('sim', 'dump.vcd')));
      expect(m.warnings.single, contains('99'));
    });

    test('a malformed sources entry is skipped with a warning', () {
      final m = parse('''
version: 1
design:
  sources:
    - rtl/a.v
    - {not: a path}
    - rtl/b.v
''');
      expect(m.rawSources, ['rtl/a.v', 'rtl/b.v']);
      expect(m.warnings.single, contains('sources[1]'));
    });

    test('a non-mapping design section is ignored with a warning', () {
      final m = parse('version: 1\ndesign: nope\n');
      expect(m.top, isNull);
      expect(m.warnings.single, contains('design'));
    });

    test('a non-string artifact value is skipped with a warning', () {
      final m = parse('''
version: 1
artifacts:
  waveform: 42
''');
      expect(m.rawArtifacts, isEmpty);
      expect(m.warnings.single, contains('waveform'));
    });
  });

  group('paths resolve against the manifest, never the process cwd', () {
    test('relative artifact paths join the manifest directory', () {
      final m = parse(
        'version: 1\nartifacts:\n  waveform: sim/dump.vcd\n',
        dir: '/designs/uart_tx',
      );
      expect(
        m.artifact('waveform'),
        p.normalize('/designs/uart_tx/sim/dump.vcd'),
      );
    });

    test('.. in a relative path is normalized', () {
      final m = parse(
        'version: 1\nartifacts:\n  waveform: ../shared/dump.vcd\n',
        dir: '/designs/uart_tx',
      );
      expect(
        m.artifact('waveform'),
        p.normalize('/designs/shared/dump.vcd'),
      );
    });

    test('an absolute path passes through verbatim', () {
      final m = parse(
        'version: 1\nartifacts:\n  waveform: /tmp/other.vcd\n',
        dir: '/designs/uart_tx',
      );
      expect(
        m.artifact('waveform'),
        p.normalize('/tmp/other.vcd'),
      );
    });

    test('a tilde is NOT expanded — a path is a path', () {
      final m = parse(
        'version: 1\nartifacts:\n  waveform: ~/dump.vcd\n',
        dir: '/designs/uart_tx',
      );
      expect(m.artifact('waveform'), contains('~'));
    });

    test('an absent kind resolves to null, not to the directory', () {
      final m = parse('version: 1\n');
      expect(m.artifact('lint'), isNull);
    });
  });

  group('display name', () {
    test('uses the declared name', () {
      expect(parse('version: 1\nname: My Design\n').displayName, 'My Design');
    });

    test('falls back to the directory basename', () {
      // A directory deliberately UNLIKE the helper's default. Passing the
      // default here would have the assertion pass whether or not the fallback
      // consulted the directory at all, which is the one thing this test is
      // for.
      expect(
        parse('version: 1\n', dir: '/work/spi_bringup').displayName,
        'spi_bringup',
      );
    });

    test('a blank name is treated as absent', () {
      final m = parse('version: 1\nname: "   "\n', dir: '/designs/foo');
      expect(m.displayName, 'foo');
      expect(m.warnings.single, contains('name'));
    });
  });

  group('open planning', () {
    CruxProjectManifest full() => parse('''
version: 1
name: uart_tx
design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v
artifacts:
  waveform:   sim/uart_tx.vcd
  lint:       project.lintcrux
  simulation: simcrux.yaml
''');

    bool everythingExists(String _) => true;
    bool nothingExists(String _) => false;

    test('each product gets its own artifact', () {
      final m = full();
      for (final (kind, suffix) in <(String, String)>[
        ('waveform', p.join('sim', 'uart_tx.vcd')),
        ('lint', 'project.lintcrux'),
        ('simulation', 'simcrux.yaml'),
      ]) {
        final plan = _planner.plan(m, kind: kind, exists: everythingExists);
        expect(plan.artifactPath, endsWith(suffix), reason: kind);
        expect(plan.refusal, isNull);
      }
    });

    test('an absent kind refuses rather than guessing', () {
      final plan = _planner.plan(
        full(),
        kind: 'netlist',
        exists: everythingExists,
      );
      expect(plan.artifactPath, isNull);
      expect(plan.refusal, CruxOpenRefusal.kindAbsent);
    });

    test('a fallback kind applies in order', () {
      final m = parse('''
version: 1
artifacts:
  source: rtl/top.v
''');
      final plan = _planner.plan(
        m,
        kind: 'netlist',
        fallbackKinds: const ['source'],
        exists: everythingExists,
      );
      expect(plan.artifactPath, endsWith(p.join('rtl', 'top.v')));
    });

    test('sources alone are actionable for an elaborating product', () {
      // NetCrux with no pre-built netlist: nothing to "open", plenty to do.
      final plan = _planner.plan(
        full(),
        kind: 'netlist',
        includeSources: true,
        exists: everythingExists,
      );
      expect(plan.refusal, isNull);
      expect(plan.isActionable, isTrue);
      expect(plan.sources.single, endsWith(p.join('rtl', 'uart_tx.v')));
      expect(plan.top, 'uart_tx');
    });

    test('a named-but-missing path refuses distinguishably', () {
      // A dump that has not been regenerated is a different user problem from
      // a manifest that never named one, and the message should differ.
      final plan = _planner.plan(
        full(),
        kind: 'waveform',
        exists: nothingExists,
      );
      expect(plan.refusal, CruxOpenRefusal.pathMissing);
      expect(plan.artifactPath, isNull);
    });

    test('the design id is carried even when nothing opens', () {
      final plan = _planner.plan(
        full(),
        kind: 'netlist',
        exists: nothingExists,
      );
      expect(plan.designId, isNotEmpty);
    });
  });

  group('design identity — the rule the whole feature rests on', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('crux_project_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test(
      'a manifest-opened design and a directly-opened file share an id',
      () {
        // If this ever fails, cross-probe between a manifest-opened design and
        // a directly-opened one silently stops joining — and nothing else in
        // the suite would notice.
        final designDir = Directory(p.join(tmp.path, 'cdc_capture'))
          ..createSync(recursive: true);
        final sim = Directory(p.join(designDir.path, 'sim'))
          ..createSync(recursive: true);
        final dump = File(p.join(sim.path, 'cdc.vcd'))..writeAsStringSync('');
        final manifestPath = p.join(designDir.path, 'cdc_capture.crux-project');
        File(manifestPath).writeAsStringSync(
          'version: 1\nartifacts:\n  waveform: sim/cdc.vcd\n',
        );

        final manifest = _parser.parseFile(manifestPath);
        final plan = _planner.plan(
          manifest,
          kind: 'waveform',
        );

        // The manifest directory is canonicalized (symlinks resolved), which
        // is exactly what makes the design id stable — on macOS that turns
        // /var into /private/var. Compare canonical forms, not raw ones.
        expect(
          plan.artifactPath,
          File(dump.path).resolveSymbolicLinksSync(),
        );
        // The direct-open path derives from the *design directory*, which is
        // what the manifest's directory is.
        expect(plan.designId, cxpDesignIdForPath(designDir.path));
      },
    );

    test('the id comes from the manifest directory, not the artifact', () {
      // The artifact lives in a subdirectory; deriving from it would produce a
      // different id than a direct open of the design folder.
      final designDir = Directory(p.join(tmp.path, 'uart'))
        ..createSync(recursive: true);
      final sub = Directory(p.join(designDir.path, 'sim'))
        ..createSync(recursive: true);
      final dump = File(p.join(sub.path, 'u.vcd'))..writeAsStringSync('');
      final manifestPath = p.join(designDir.path, 'uart.crux-project');
      File(manifestPath).writeAsStringSync(
        'version: 1\nartifacts:\n  waveform: sim/u.vcd\n',
      );

      final plan = _planner.plan(
        _parser.parseFile(manifestPath),
        kind: 'waveform',
      );
      expect(plan.designId, cxpDesignIdForPath(designDir.path));
      expect(plan.designId, isNot(cxpDesignIdForPath(dump.path)));
    });
  });

  group('the file name', () {
    test('a named manifest is recognised by its extension', () {
      expect(
        CruxProjectParser.isManifestPath('/a/b/uart_tx.crux-project'),
        isTrue,
      );
      expect(CruxProjectParser.isManifestPath('uart_tx.crux-project'), isTrue);
      expect(
        CruxProjectParser.isManifestPath('/a/b/UART_TX.Crux-Project'),
        isTrue,
        reason: 'pickers and Finder compare extensions case-insensitively',
      );
      expect(
        CruxProjectParser.isLegacyManifestPath('/a/b/uart_tx.crux-project'),
        isFalse,
      );
    });

    test('the legacy bare name is still recognised, and flagged', () {
      expect(CruxProjectParser.isManifestPath('/a/b/.crux-project'), isTrue);
      expect(CruxProjectParser.isManifestPath('.crux-project'), isTrue);
      expect(
        CruxProjectParser.isLegacyManifestPath('/a/b/.crux-project'),
        isTrue,
      );
    });

    test('a name that only resembles a manifest is not one', () {
      for (final path in <String>[
        '/a/b/crux-project.yaml',
        '/a/b/notes.crux-project.txt',
        '/a/b/crux-project',
        '/a/b/uart_tx.crux-projects',
        '/a/b/uart_tx.netcrux-project',
      ]) {
        expect(CruxProjectParser.isManifestPath(path), isFalse, reason: path);
        expect(
          CruxProjectParser.isLegacyManifestPath(path),
          isFalse,
          reason: path,
        );
      }
    });

    test('the extension constant is what a picker filter takes', () {
      expect(kCruxProjectExtension, 'crux-project');
      expect(kCruxProjectExtension.startsWith('.'), isFalse);
    });

    test('a named manifest parses with no warning', () {
      final m = _parser.parse(
        'version: 1\n',
        manifestPath: '/designs/uart_tx/uart_tx.crux-project',
      );
      expect(m.warnings, isEmpty);
    });

    test('a legacy manifest opens, with a deprecation warning first', () {
      final m = _parser.parse(
        'version: 99\nartifacts:\n  waveform: sim/dump.vcd\n',
        manifestPath: '/designs/uart_tx/.crux-project',
      );
      expect(m.artifact('waveform'), endsWith(p.join('sim', 'dump.vcd')));
      expect(m.warnings, hasLength(2));
      expect(m.warnings.first, contains('".crux-project" is deprecated'));
      expect(
        m.warnings.first,
        contains('"uart_tx.crux-project"'),
        reason: 'the diagnostic names the file to rename it to',
      );
      expect(m.warnings.last, contains('99'));
    });

    test('the design id does not depend on which name the manifest uses', () {
      // The CXP design id comes from the manifest directory, so renaming the
      // legacy file to the named form keeps every existing cross-probe join.
      const yaml = 'version: 1\n';
      final legacy = _parser.parse(
        yaml,
        manifestPath: '/designs/uart_tx/.crux-project',
      );
      final named = _parser.parse(
        yaml,
        manifestPath: '/designs/uart_tx/uart_tx.crux-project',
      );
      expect(named.directory, legacy.directory);
      expect(
        _planner.plan(named, kind: 'waveform').designId,
        _planner.plan(legacy, kind: 'waveform').designId,
      );
    });
  });

  group('discovery', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('crux_find'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String touch(String name, [String text = 'version: 1\n']) {
      final path = p.join(tmp.path, name);
      File(path).writeAsStringSync(text);
      return path;
    }

    Matcher ambiguousOver(List<String> names) =>
        isA<CruxProjectAmbiguousException>()
            .having((e) => e.directory, 'directory', tmp.path)
            .having(
              (e) => e.candidates.map(p.basename).toList(),
              'candidate names',
              names,
            )
            .having(
              (e) => e.message,
              'message',
              allOf([for (final n in names) contains(n)]),
            );

    test('an empty directory holds no manifest', () {
      touch('README.md', '# not a manifest\n');
      expect(CruxProjectParser.findIn(tmp.path), isNull);
    });

    test('a missing directory holds no manifest', () {
      expect(CruxProjectParser.findIn(p.join(tmp.path, 'absent')), isNull);
    });

    test('a named manifest is found', () {
      final path = touch('uart_tx.crux-project');
      expect(CruxProjectParser.findIn(tmp.path), path);
    });

    test('a legacy manifest on its own is found', () {
      final path = touch('.crux-project');
      expect(CruxProjectParser.findIn(tmp.path), path);
      expect(
        _parser.parseFile(path).warnings.first,
        contains('deprecated'),
      );
    });

    test('a legacy manifest beside a named one is ambiguous', () {
      // Preferring either would silently open a design from a file the user
      // may not know is stale — so both are named and neither is chosen.
      touch('uart_tx.crux-project');
      touch('.crux-project');
      expect(
        () => CruxProjectParser.findIn(tmp.path),
        throwsA(ambiguousOver(['.crux-project', 'uart_tx.crux-project'])),
      );
    });

    test('several named manifests are ambiguous, and all are named', () {
      touch('b.crux-project');
      touch('a.crux-project');
      touch('c.crux-project');
      expect(
        () => CruxProjectParser.findIn(tmp.path),
        throwsA(
          ambiguousOver(['a.crux-project', 'b.crux-project', 'c.crux-project']),
        ),
      );
    });

    test('a directory with a manifest-shaped name is not a manifest', () {
      Directory(p.join(tmp.path, 'archive.crux-project')).createSync();
      final path = touch('uart_tx.crux-project');
      expect(CruxProjectParser.findIn(tmp.path), path);
    });

    test('discovery does not recurse into subdirectories', () {
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      File(
        p.join(sub.path, 'sub.crux-project'),
      ).writeAsStringSync('version: 1');
      expect(CruxProjectParser.findIn(tmp.path), isNull);
    });

    test('locate accepts the manifest file itself', () {
      final path = touch('uart_tx.crux-project');
      expect(CruxProjectParser.locate(path), path);
    });

    test('locate accepts the design directory', () {
      final path = touch('uart_tx.crux-project');
      expect(CruxProjectParser.locate(tmp.path), path);
    });

    test('locate names the file even beside another manifest', () {
      // Only a directory is ambiguous; a path naming one file is a choice.
      final named = touch('uart_tx.crux-project');
      touch('.crux-project');
      expect(CruxProjectParser.locate(named), named);
      expect(
        () => CruxProjectParser.locate(tmp.path),
        throwsA(isA<CruxProjectAmbiguousException>()),
      );
    });

    test('locate refuses a path that is not a manifest', () {
      final other = touch('dump.vcd', '');
      expect(CruxProjectParser.locate(other), isNull);
      expect(
        CruxProjectParser.locate(p.join(tmp.path, 'absent.vcd')),
        isNull,
      );
    });

    test('the file and its directory resolve to the same design', () {
      final design = Directory(p.join(tmp.path, 'uart_tx'))..createSync();
      final manifestPath = p.join(design.path, 'uart_tx.crux-project');
      File(manifestPath).writeAsStringSync('version: 1\n');

      final viaFile = _parser.parseFile(
        CruxProjectParser.locate(manifestPath)!,
      );
      final viaDir = _parser.parseFile(CruxProjectParser.locate(design.path)!);

      expect(viaDir.directory, viaFile.directory);
      final id = _planner.plan(viaFile, kind: 'waveform').designId;
      expect(_planner.plan(viaDir, kind: 'waveform').designId, id);
      expect(id, cxpDesignIdForPath(design.path));
    });

    test('parseFile reports an unreadable file as a format exception', () {
      expect(
        () => _parser.parseFile('/definitely/not/here/uart_tx.crux-project'),
        throwsA(isA<CruxProjectFormatException>()),
      );
    });
  });

  group('the spec example parses as documented', () {
    test('the uart_tx example', () {
      final m = parse('''
version: 1
name: uart_tx

design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v

artifacts:
  waveform:   sim/uart_tx.vcd
  lint:       project.lintcrux
  simulation: simcrux.yaml
''');
      expect(m.displayName, 'uart_tx');
      expect(m.top, 'uart_tx');
      expect(m.rawSources, ['rtl/uart_tx.v']);
      expect(m.rawArtifacts, hasLength(3));
      expect(m.rawArtifacts['netlist'], isNull);
      expect(m.warnings, isEmpty);
    });

    test('JSON is accepted, since JSON is valid YAML', () {
      final m = parse(
        '{"version": 1, "artifacts": {"waveform": "sim/d.vcd"}}',
      );
      expect(m.artifact('waveform'), endsWith(p.join('sim', 'd.vcd')));
    });
  });
}
