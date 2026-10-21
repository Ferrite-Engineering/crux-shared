// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String project;
  late String ingest;
  late String outside;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_flow_containment_');
    project = p.join(temp.path, 'project');
    ingest = p.join(temp.path, 'downloads', 'tt-artifact');
    outside = p.join(temp.path, 'outside');
    Directory(
      p.join(project, 'runs', 'RUN_1', 'final', 'nl'),
    ).createSync(recursive: true);
    Directory(ingest).createSync(recursive: true);
    Directory(outside).createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('a run root', () {
    test('inside the project root or an ingest directory is allowed', () {
      final rule = FlowContainment([project, ingest]);
      expect(rule.allows(p.join(project, 'runs', 'RUN_1')), isTrue);
      expect(rule.allows(ingest), isTrue);
      expect(rule.refuse(p.join(project, 'runs', 'RUN_1')), isNull);
    });

    test('outside every root is refused, without naming the path', () {
      final rule = FlowContainment([project]);
      final reason = rule.refuse(outside);
      expect(reason, 'the path is outside the allowed directories');
      expect(reason, isNot(contains(temp.path)));
      expect(
        () => rule.require(outside),
        throwsA(
          isA<FlowContainmentException>().having(
            (e) => e.toString(),
            'message',
            isNot(contains(temp.path)),
          ),
        ),
      );
    });

    test('a link inside the project that points out is refused', () {
      final link = p.join(project, 'runs', 'linked');
      Link(link).createSync(outside);
      expect(FlowContainment([project]).allows(link), isFalse);
    });

    test('a path that climbs out with .. is refused', () {
      expect(
        FlowContainment([project]).allows(
          p.join(project, 'runs', '..', '..', 'outside'),
        ),
        isFalse,
      );
    });

    test('require returns the resolved path, which is what to open', () {
      final alias = p.join(temp.path, 'alias');
      Link(alias).createSync(project);
      final resolved = FlowContainment([project]).require(
        p.join(alias, 'runs', 'RUN_1'),
      );
      expect(
        resolved,
        p.join(Directory(project).resolveSymbolicLinksSync(), 'runs', 'RUN_1'),
      );
    });

    test('malformed paths and an empty rule are refused', () {
      final rule = FlowContainment([project]);
      expect(rule.refuse(''), 'the path is empty');
      expect(rule.refuse('runs/RUN_1'), 'the path is not absolute');
      expect(
        rule.refuse('${p.join(project, 'runs')}\x00'),
        'the path contains a NUL character',
      );
      expect(
        rule.refuse(' ${p.join(project, 'runs')}'),
        'the path begins or ends with white space',
      );
      expect(
        const FlowContainment(['', ' ']).refuse(project),
        'no directory has been allowed',
      );
      expect(
        rule.refuse(p.join(project, 'ghost', '..', 'runs')),
        'the path cannot be resolved',
      );
    });
  });

  group('a path a run records', () {
    test('relative to the run root, resolved and checked', () {
      final run = p.join(project, 'runs', 'RUN_1');
      final rule = FlowContainment([run]);
      expect(
        rule.requireRecorded(run, 'final/nl/top.nl.v'),
        p.join(
          Directory(run).resolveSymbolicLinksSync(),
          'final',
          'nl',
          'top.nl.v',
        ),
      );
      expect(
        () => rule.requireRecorded(run, '../../../outside/x.v'),
        throwsA(isA<FlowContainmentException>()),
      );
      expect(
        () => rule.requireRecorded(run, p.join(outside, 'x.v')),
        throwsA(isA<FlowContainmentException>()),
      );
      expect(
        () => rule.requireRecorded(run, 'final/\x00x'),
        throwsA(isA<FlowContainmentException>()),
      );
    });

    test('a PDK root that is a link is checked at its target', () {
      final store = p.join(temp.path, 'ciel', 'sky130A-abc');
      Directory(p.join(store, 'libs.ref')).createSync(recursive: true);
      final pdkRoot = p.join(temp.path, 'pdk');
      Directory(pdkRoot).createSync();
      final enabled = p.join(pdkRoot, 'sky130A');
      Link(enabled).createSync(store);
      final rule = FlowContainment([enabled]);
      expect(rule.allows(p.join(store, 'libs.ref')), isTrue);
      expect(rule.allows(p.join(enabled, 'libs.ref')), isTrue);
      expect(rule.allows(pdkRoot), isFalse);
    });
  });
}
