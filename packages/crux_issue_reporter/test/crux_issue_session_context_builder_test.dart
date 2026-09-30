// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxIssueSessionContextBuilder', () {
    test('preserves field order', () {
      final b = CruxIssueSessionContextBuilder()
        ..addCount('Open tabs', 3)
        ..addText('Active format', 'VCD')
        ..addList('Active decoders', <String>['SPI #1', 'UART #2']);

      expect(b.build().fields.map((f) => f.label), <String>[
        'Open tabs',
        'Active format',
        'Active decoders',
      ]);
    });

    test('substitutes the fallback for null and empty values', () {
      final b = CruxIssueSessionContextBuilder()
        ..addText('A', null)
        ..addText('B', '')
        ..addText('C', null, fallback: CruxIssueFallback.noneLoaded)
        ..addList('D', const <String>[]);

      expect(b.build().fields.map((f) => f.value), <String>[
        '(none)',
        '(none)',
        '(none loaded)',
        '(none)',
      ]);
    });

    test(
      'records the typed value as the attribute, not the rendered string',
      () {
        final ctx =
            (CruxIssueSessionContextBuilder()
                  ..addCount('Tabs', 7, attributeKey: 'tabs')
                  ..addList(
                    'Ids',
                    <String>['a', 'b'],
                    attributeKey: 'ids',
                  )
                  ..addFlag('Loaded', value: true, attributeKey: 'loaded'))
                .build();

        expect(ctx.attributes['tabs'], 7);
        expect(ctx.attributes['ids'], <String>['a', 'b']);
        expect(ctx.attributes['loaded'], isTrue);
      },
    );

    test('a redacted field leaks through neither channel', () {
      final ctx = (CruxIssueSessionContextBuilder()..redact('Project path'))
          .build();

      expect(ctx.fields.single.value, '(redacted)');
      expect(
        ctx.attributes,
        isEmpty,
        reason:
            'A value withheld from the visible report must not reappear in '
            'the machine-readable attributes.',
      );
    });

    test('guard degrades instead of throwing', () {
      final b = CruxIssueSessionContextBuilder();
      var ran = false;

      final ok = b.guard(() => throw StateError('no workspace'));
      final ok2 = b.guard(() {
        ran = true;
        b.addCount('After', 1);
      });

      expect(ok, isFalse);
      expect(ok2, isTrue);
      expect(ran, isTrue);
      // The failed guard must not have prevented later fields.
      expect(b.build().fields.single.label, 'After');
    });

    test('partial state survives a mid-block failure', () {
      // The real shape: a product reads several providers in one guard and the
      // third throws. Whatever landed before the throw must still be reported —
      // the issue reporter exists to describe broken states.
      final b = CruxIssueSessionContextBuilder();
      b.guard(() {
        b
          ..addCount('First', 1)
          ..addCount('Second', 2);
        throw StateError('provider missing');
      });

      expect(b.build().fields.map((f) => f.label), <String>['First', 'Second']);
    });

    test('the built snapshot is unmodifiable', () {
      final ctx = (CruxIssueSessionContextBuilder()..addCount('A', 1)).build();
      expect(
        () => ctx.fields.add(const CruxIssueField(label: 'x', value: 'y')),
        throwsUnsupportedError,
      );
      expect(() => ctx.attributes['k'] = 1, throwsUnsupportedError);
    });

    test('carries the locale tag through', () {
      final ctx = CruxIssueSessionContextBuilder(localeTag: 'ja').build();
      expect(ctx.localeTag, 'ja');
    });
  });
}
