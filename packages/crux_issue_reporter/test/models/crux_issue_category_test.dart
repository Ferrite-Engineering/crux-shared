// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const category = CruxIssueCategory(
    id: 'session',
    title: 'Session State',
    description: 'Counts only.',
    markdownBody: '- **Open tabs:** 3',
  );

  test('value equality and hashCode', () {
    expect(
      category,
      const CruxIssueCategory(
        id: 'session',
        title: 'Session State',
        description: 'Counts only.',
        markdownBody: '- **Open tabs:** 3',
      ),
    );
    expect(
      category.hashCode,
      const CruxIssueCategory(
        id: 'session',
        title: 'Session State',
        description: 'Counts only.',
        markdownBody: '- **Open tabs:** 3',
      ).hashCode,
    );
    expect(category, isNot(category.copyWith(id: 'other')));
    expect(category, isNot(category.copyWith(markdownBody: 'x')));
  });

  test('description is optional', () {
    const bare = CruxIssueCategory(id: 'a', title: 'A', markdownBody: 'b');
    expect(bare.description, isNull);
  });

  test('copyWith replaces only the named fields', () {
    final renamed = category.copyWith(title: 'Renamed');
    expect(renamed.title, 'Renamed');
    expect(renamed.id, category.id);
    expect(renamed.markdownBody, category.markdownBody);
  });

  test('toString names id and title but not the body', () {
    expect(category.toString(), contains('session'));
    expect(category.toString(), contains('Session State'));
    expect(category.toString(), isNot(contains('Open tabs')));
  });
}
