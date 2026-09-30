// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = CruxIssueReporterConfig(
    productName: 'NetCrux',
    repositorySlug: 'Ferrite-Engineering/netcrux',
  );

  test('newIssueUrl is built from host + slug', () {
    expect(
      config.newIssueUrl.toString(),
      'https://github.com/Ferrite-Engineering/netcrux/issues/new',
    );
  });

  test('default labels are bug + user-report', () {
    expect(config.defaultLabels, ['bug', 'user-report']);
  });

  test('no default label is beta-scoped', () {
    // `beta-feedback` did not survive the 1.0 launch; a beta-scoped default
    // would be applied to every report filed from a shipping product.
    expect(
      config.defaultLabels.where((l) => l.contains('beta')),
      isEmpty,
    );
  });

  test('the screenshot prefix defaults to a slugified product name', () {
    expect(config.resolvedScreenshotFilePrefix, 'netcrux');
    expect(
      const CruxIssueReporterConfig(
        productName: 'Wave Crux 2!',
        repositorySlug: 'a/b',
      ).resolvedScreenshotFilePrefix,
      'wave-crux-2',
    );
    expect(
      const CruxIssueReporterConfig(
        productName: '!!!',
        repositorySlug: 'a/b',
      ).resolvedScreenshotFilePrefix,
      'crux',
    );
  });

  test('an explicit screenshot prefix wins', () {
    expect(
      config
          .copyWith(screenshotFilePrefix: 'custom')
          .resolvedScreenshotFilePrefix,
      'custom',
    );
  });

  test('copyWith replaces only the named fields', () {
    final other = config.copyWith(
      productName: 'SimCrux',
      repositorySlug: 'Ferrite-Engineering/simcrux',
    );
    expect(other.productName, 'SimCrux');
    expect(other.repositorySlug, 'Ferrite-Engineering/simcrux');
    expect(other.host, config.host);
    expect(other.maxIssueUrlLength, config.maxIssueUrlLength);
  });

  test('value equality and hashCode', () {
    expect(
      config,
      const CruxIssueReporterConfig(
        productName: 'NetCrux',
        repositorySlug: 'Ferrite-Engineering/netcrux',
      ),
    );
    expect(
      config.hashCode,
      const CruxIssueReporterConfig(
        productName: 'NetCrux',
        repositorySlug: 'Ferrite-Engineering/netcrux',
      ).hashCode,
    );
    expect(config, isNot(config.copyWith(host: 'example.com')));
    expect(config, isNot(config.copyWith(defaultLabels: const ['bug'])));
  });

  test('toString names the product and target repository', () {
    expect(config.toString(), contains('NetCrux'));
    expect(config.toString(), contains('netcrux'));
  });

  test('rejects empty required fields and a non-positive URL cap', () {
    expect(
      () => CruxIssueReporterConfig(productName: '', repositorySlug: 'a/b'),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => CruxIssueReporterConfig(productName: 'X', repositorySlug: ''),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => CruxIssueReporterConfig(
        productName: 'X',
        repositorySlug: 'a/b',
        maxIssueUrlLength: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
