// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxIssueField', () {
    test('value equality and hashCode', () {
      const a = CruxIssueField(label: 'Open tabs', value: '3');
      expect(a, const CruxIssueField(label: 'Open tabs', value: '3'));
      expect(
        a.hashCode,
        const CruxIssueField(label: 'Open tabs', value: '3').hashCode,
      );
      expect(a, isNot(const CruxIssueField(label: 'Open tabs', value: '4')));
    });

    test('toString renders label and value', () {
      expect(
        const CruxIssueField(label: 'Open tabs', value: '3').toString(),
        contains('Open tabs: 3'),
      );
    });
  });

  group('CruxIssueSessionContext', () {
    const populated = CruxIssueSessionContext(
      localeTag: 'ja',
      fields: [CruxIssueField(label: 'Open tabs', value: '3')],
      attributes: {'proDecoders': 1},
    );

    test('empty contributes nothing', () {
      expect(CruxIssueSessionContext.empty.isEmpty, isTrue);
      expect(CruxIssueSessionContext.empty.isNotEmpty, isFalse);
      expect(CruxIssueSessionContext.empty.localeTag, isEmpty);
      expect(CruxIssueSessionContext.empty.attributes, isEmpty);
    });

    test('isNotEmpty tracks the field list', () {
      expect(populated.isNotEmpty, isTrue);
      expect(populated.isEmpty, isFalse);
    });

    test('copyWith replaces only the named fields', () {
      final tagged = CruxIssueSessionContext.empty.copyWith(localeTag: 'ko');
      expect(tagged.localeTag, 'ko');
      expect(tagged.fields, isEmpty);

      final relabelled = populated.copyWith(localeTag: 'en');
      expect(relabelled.localeTag, 'en');
      expect(relabelled.fields, populated.fields);
      expect(relabelled.attributes, populated.attributes);
    });

    test('value equality covers locale, fields and attributes', () {
      expect(
        populated,
        const CruxIssueSessionContext(
          localeTag: 'ja',
          fields: [CruxIssueField(label: 'Open tabs', value: '3')],
          attributes: {'proDecoders': 1},
        ),
      );
      expect(populated, isNot(populated.copyWith(localeTag: 'en')));
      expect(
        populated,
        isNot(populated.copyWith(attributes: const {'proDecoders': 2})),
      );
      expect(
        populated,
        isNot(
          populated.copyWith(
            fields: const [
              CruxIssueField(label: 'Open tabs', value: '3'),
              CruxIssueField(label: 'Extra', value: 'x'),
            ],
          ),
        ),
      );
    });

    test('hashCode agrees with equality', () {
      expect(
        populated.hashCode,
        const CruxIssueSessionContext(
          localeTag: 'ja',
          fields: [CruxIssueField(label: 'Open tabs', value: '3')],
          attributes: {'proDecoders': 1},
        ).hashCode,
      );
    });

    test('toString summarizes without dumping values', () {
      expect(populated.toString(), contains('locale: ja'));
      expect(populated.toString(), contains('fields: 1'));
    });
  });
}
