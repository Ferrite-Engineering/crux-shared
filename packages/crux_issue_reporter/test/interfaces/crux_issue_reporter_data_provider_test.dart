// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Overlay-style data provider that contributes a category only when the
/// session snapshot says a gated feature is in use — the shape a Pro
/// overlay's "Pro State" contributor takes.
class _ProStateDataProvider implements CruxIssueReporterDataProvider {
  @override
  List<CruxIssueCategory> extraCategories(CruxIssueSessionContext context) {
    final proCount = context.attributes['proFeatureCount'];
    if (proCount is! int || proCount == 0) return const [];
    return [
      CruxIssueCategory(
        id: 'proState',
        title: context.localeTag == 'ja' ? 'Pro の状態' : 'Pro State',
        markdownBody: '- **Active Pro features:** $proCount',
      ),
    ];
  }
}

void main() {
  test('the no-op default contributes nothing', () {
    const provider = NoopCruxIssueReporterDataProvider();
    expect(provider.extraCategories(CruxIssueSessionContext.empty), isEmpty);
    expect(
      provider.extraCategories(
        const CruxIssueSessionContext(
          localeTag: 'ja',
          fields: [CruxIssueField(label: 'a', value: 'b')],
        ),
      ),
      isEmpty,
    );
  });

  test('an overlay reads the snapshot attributes to decide', () {
    final provider = _ProStateDataProvider();
    expect(provider.extraCategories(CruxIssueSessionContext.empty), isEmpty);
    expect(
      provider.extraCategories(
        const CruxIssueSessionContext(attributes: {'proFeatureCount': 0}),
      ),
      isEmpty,
    );
    final categories = provider.extraCategories(
      const CruxIssueSessionContext(attributes: {'proFeatureCount': 3}),
    );
    expect(categories.single.id, 'proState');
    expect(categories.single.markdownBody, contains('3'));
  });

  test('an overlay localizes from the snapshot locale tag, not a context', () {
    final provider = _ProStateDataProvider();
    expect(
      provider
          .extraCategories(
            const CruxIssueSessionContext(
              localeTag: 'ja',
              attributes: {'proFeatureCount': 1},
            ),
          )
          .single
          .title,
      'Pro の状態',
    );
  });
}
