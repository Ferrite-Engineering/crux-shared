// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal product-style adapter, mirroring how a consuming product maps its
/// generated `AppLocalizations` onto the package's strings interface.
class _AdapterStrings extends CruxIssueReporterStrings {
  const _AdapterStrings(this._prefix);

  final String _prefix;

  @override
  String get dialogTitle => '$_prefix.dialogTitle';
  @override
  String get titleFieldLabel => '$_prefix.titleFieldLabel';
  @override
  String get titleFieldHint => '$_prefix.titleFieldHint';
  @override
  String get privacyNotice => '$_prefix.privacyNotice';
  @override
  String get previewHeader => '$_prefix.previewHeader';
  @override
  String get categoryAppEnv => '$_prefix.categoryAppEnv';
  @override
  String get categoryAppEnvDescription => '$_prefix.categoryAppEnvDescription';
  @override
  String get categorySession => '$_prefix.categorySession';
  @override
  String get categorySessionDescription =>
      '$_prefix.categorySessionDescription';
  @override
  String get categoryLog => '$_prefix.categoryLog';
  @override
  String get categoryLogDescription => '$_prefix.categoryLogDescription';
  @override
  String get categoryScreenshot => '$_prefix.categoryScreenshot';
  @override
  String get categoryScreenshotDescription =>
      '$_prefix.categoryScreenshotDescription';
  @override
  String get lockedCategorySemantics => '$_prefix.lockedCategorySemantics';
  @override
  String get submitButton => '$_prefix.submitButton';
  @override
  String get cancelButton => '$_prefix.cancelButton';
  @override
  String get openedToast => '$_prefix.openedToast';
  @override
  String get openedToastPrefilled => '$_prefix.openedToastPrefilled';
  @override
  String screenshotSaved(String path) => '$_prefix.screenshotSaved:$path';
  @override
  String get emptyLogPlaceholder => '$_prefix.emptyLogPlaceholder';
  @override
  String get emptySessionLogPlaceholder =>
      '$_prefix.emptySessionLogPlaceholder';
}

void main() {
  group('CruxIssueReporterStringsEn', () {
    const strings = CruxIssueReporterStringsEn();

    test('every getter is non-empty', () {
      for (final value in <String>[
        strings.dialogTitle,
        strings.titleFieldLabel,
        strings.titleFieldHint,
        strings.privacyNotice,
        strings.previewHeader,
        strings.categoryAppEnv,
        strings.categoryAppEnvDescription,
        strings.categorySession,
        strings.categorySessionDescription,
        strings.categoryLog,
        strings.categoryLogDescription,
        strings.categoryScreenshot,
        strings.categoryScreenshotDescription,
        strings.lockedCategorySemantics,
        strings.submitButton,
        strings.cancelButton,
        strings.openedToast,
        strings.openedToastPrefilled,
        strings.emptyLogPlaceholder,
        strings.emptySessionLogPlaceholder,
        strings.screenshotSaved('/tmp/x.png'),
      ]) {
        expect(value, isNotEmpty);
      }
    });

    test('the privacy notice states the file-content guarantee', () {
      expect(strings.privacyNotice.toLowerCase(), contains('file'));
    });

    test('screenshotSaved interpolates the path', () {
      expect(strings.screenshotSaved('/tmp/a.png'), contains('/tmp/a.png'));
    });

    test('is const-constructible so it can be a provider default', () {
      expect(
        const CruxIssueReporterStringsEn(),
        isA<CruxIssueReporterStrings>(),
      );
    });
  });

  group('product adapter', () {
    test('a subclass can supply every string', () {
      const adapter = _AdapterStrings('l10n');
      expect(adapter.dialogTitle, 'l10n.dialogTitle');
      expect(adapter.categorySession, 'l10n.categorySession');
      expect(adapter.screenshotSaved('p'), 'l10n.screenshotSaved:p');
    });

    test('a subclass may override only part of the English defaults', () {
      // `CruxIssueReporterStringsEn` is a normal class, so a product may
      // extend it and override selectively while a translation lands.
      expect(const _PartialStrings().dialogTitle, 'Report a bug');
      expect(
        const _PartialStrings().cancelButton,
        const CruxIssueReporterStringsEn().cancelButton,
      );
    });
  });
}

class _PartialStrings extends CruxIssueReporterStringsEn {
  const _PartialStrings();

  @override
  String get dialogTitle => 'Report a bug';
}
