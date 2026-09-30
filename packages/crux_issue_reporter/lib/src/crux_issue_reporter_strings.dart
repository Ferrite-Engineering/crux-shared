// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Localized strings consumed by the shared beta issue reporter.
///
/// crux-shared packages never contain ARB files. Each product supplies an
/// `AppLocalizations`-backed subclass mapping every getter to the matching
/// ARB-generated string, mirroring the `LicenseBadgeStrings` /
/// `CruxAboutStrings` pattern the suite already uses. The English-only
/// [CruxIssueReporterStringsEn] default lets prototypes, tests and demos
/// render the dialog without wiring localization first.
///
/// **Scope note.** These are the strings the *user* sees: the dialog chrome,
/// the category tiles, the buttons and the toasts. The markdown field labels
/// inside the generated issue body (`**App version:**`, `**Build SHA:**`, …)
/// are deliberately *not* localized — the body is authored for the
/// maintainers reading it in the GitHub repository, and a mixed-language body
/// makes triage harder rather than easier. That matches the behaviour of the
/// WaveCrux implementation this package was lifted from.
@immutable
abstract class CruxIssueReporterStrings {
  /// Const constructor for subclasses.
  const CruxIssueReporterStrings();

  /// Dialog title and the fallback issue title when the user leaves the
  /// summary field blank (e.g. "Submit Issue").
  String get dialogTitle;

  /// Label for the free-text issue-summary field.
  String get titleFieldLabel;

  /// Hint shown inside the empty issue-summary field.
  String get titleFieldHint;

  /// Privacy callout above the category tiles, telling the user they can
  /// toggle off anything they would rather not share.
  String get privacyNotice;

  /// Header of the collapsible markdown preview disclosure.
  String get previewHeader;

  /// Title of the always-on App & Environment category tile.
  String get categoryAppEnv;

  /// One-line summary of what the App & Environment category contributes.
  String get categoryAppEnvDescription;

  /// Title of the Session State category tile.
  String get categorySession;

  /// One-line summary of what the Session State category contributes.
  String get categorySessionDescription;

  /// Title of the Diagnostic Log category tile.
  String get categoryLog;

  /// One-line summary of what the Diagnostic Log category contributes.
  String get categoryLogDescription;

  /// Title of the Screenshot category tile (desktop only).
  String get categoryScreenshot;

  /// One-line summary of what the Screenshot category contributes.
  String get categoryScreenshotDescription;

  /// Screen-reader description of the lock icon on the always-on
  /// App & Environment tile.
  String get lockedCategorySemantics;

  /// Label of the submit action.
  String get submitButton;

  /// Label of the cancel action.
  String get cancelButton;

  /// Toast shown after submission when the body did **not** fit in the
  /// new-issue URL and the user must paste it from the clipboard.
  String get openedToast;

  /// Toast shown after submission when the body was pre-filled into the
  /// new-issue URL and there is nothing to paste.
  String get openedToastPrefilled;

  /// Confirmation appended to the submission toast naming where the
  /// screenshot PNG was written. Only shown when a screenshot was saved.
  String screenshotSaved(String path);

  /// Placeholder rendered in the Diagnostic Log category when the ring buffer
  /// captured nothing at all.
  String get emptyLogPlaceholder;

  /// Placeholder rendered under the "Session log" heading of the combined
  /// diagnostics category when nothing was logged this session.
  String get emptySessionLogPlaceholder;
}

/// Default English [CruxIssueReporterStrings] used by tests, prototypes and
/// demos, and by the package default of `cruxIssueReporterStringsProvider`.
class CruxIssueReporterStringsEn extends CruxIssueReporterStrings {
  /// Creates the default English string set.
  const CruxIssueReporterStringsEn();

  @override
  String get dialogTitle => 'Submit Issue';

  @override
  String get titleFieldLabel => 'Issue summary';

  @override
  String get titleFieldHint => 'Briefly describe what went wrong';

  @override
  String get privacyNotice =>
      'More context helps reproduce your issue. Review and toggle off '
      "anything you'd rather not share. No file contents or file paths are "
      'ever included.';

  @override
  String get previewHeader => 'Preview issue body';

  @override
  String get categoryAppEnv => 'App & Environment';

  @override
  String get categoryAppEnvDescription =>
      'Version, build SHA, platform, OS, screen DPI, locale, SDK versions.';

  @override
  String get categorySession => 'Session State';

  @override
  String get categorySessionDescription =>
      'Counts and format names only — never file paths or file contents.';

  @override
  String get categoryLog => 'Diagnostic Log';

  @override
  String get categoryLogDescription =>
      'Recent warnings and errors captured this session.';

  @override
  String get categoryScreenshot => 'Screenshot';

  @override
  String get categoryScreenshotDescription =>
      'A picture of the app window, saved so you can attach it.';

  @override
  String get lockedCategorySemantics => 'Always included';

  @override
  String get submitButton => 'Submit';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get openedToast =>
      'GitHub issue opened — paste the report from your clipboard into the '
      'body.';

  @override
  String get openedToastPrefilled =>
      'GitHub issue opened with the report pre-filled.';

  @override
  String screenshotSaved(String path) => 'Screenshot saved to $path';

  @override
  String get emptyLogPlaceholder => '(no log entries captured)';

  @override
  String get emptySessionLogPlaceholder =>
      '(no errors or warnings logged this session)';
}
