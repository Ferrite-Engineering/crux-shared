// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-product configuration for the shared beta issue reporter.
///
/// Everything that differs between WaveCrux, NetCrux, LintCrux and SimCrux —
/// the product name shown in the fallback issue title, the GitHub repository
/// reports are filed against, the issue template, the default labels — lives
/// here rather than being hardcoded in the service. Supplied through
/// `cruxIssueReporterConfigProvider`, whose package default throws so an
/// unwired product fails loudly at first use instead of silently filing issues
/// against the wrong repository.
///
/// Typical wiring:
///
/// ```dart
/// cruxIssueReporterConfigProvider.overrideWithValue(
///   const CruxIssueReporterConfig(
///     productName: 'NetCrux',
///     repositorySlug: 'Ferrite-Engineering/netcrux',
///   ),
/// )
/// ```
///
/// Products that retarget the repository at the post-beta open-core flip
/// select the slug at the override site (e.g. from `kBetaPeriod`), keeping the
/// flag dependency out of this package.
@immutable
class CruxIssueReporterConfig {
  /// Creates a reporter configuration.
  ///
  /// [repositorySlug] must be an `owner/repo` pair with no leading or trailing
  /// slash — it is interpolated straight into the new-issue URL path.
  const CruxIssueReporterConfig({
    required this.productName,
    required this.repositorySlug,
    this.issueTemplate,
    this.defaultLabels = const ['bug', 'user-report'],
    this.host = 'github.com',
    this.screenshotFilePrefix,
    this.maxIssueUrlLength = 6000,
  }) : assert(productName.length > 0, 'productName must not be empty'),
       assert(
         repositorySlug.length > 0,
         'repositorySlug must not be empty',
       ),
       assert(
         maxIssueUrlLength > 0,
         'maxIssueUrlLength must be positive',
       );

  /// The product display name (e.g. `'NetCrux'`). Used for the fallback issue
  /// title when the user leaves the summary field blank, and as the default
  /// screenshot filename prefix.
  final String productName;

  /// The GitHub `owner/repo` slug reports are filed against (e.g.
  /// `'Ferrite-Engineering/netcrux'`).
  final String repositorySlug;

  /// Optional GitHub issue-template file name (e.g. `'bug.yml'`). When set it
  /// is passed as the `template` query parameter so GitHub opens the matching
  /// issue form. `null` opens the plain new-issue form.
  final String? issueTemplate;

  /// Labels applied to every report, before the platform label is appended.
  ///
  /// The default `user-report` marks a report as filed through the in-app
  /// reporter by someone using the product, which is what separates it from
  /// an issue a maintainer opened. It replaced `beta-feedback` at the 1.0
  /// launch; the label must exist in the target repository or GitHub drops
  /// it from the URL silently.
  final List<String> defaultLabels;

  /// The GitHub host. Overridable for GitHub Enterprise deployments.
  final String host;

  /// Filename prefix for the screenshot PNG written to the OS temp directory.
  /// Defaults to a slugified [productName] via [resolvedScreenshotFilePrefix].
  final String? screenshotFilePrefix;

  /// Maximum total length of the GitHub new-issue GET URL the reporter is
  /// willing to emit. Browsers and GitHub's server start truncating or
  /// rejecting query strings past roughly this size, so when embedding the
  /// body would exceed it the body is dropped from the URL and the clipboard
  /// copy carries it instead.
  final int maxIssueUrlLength;

  /// The screenshot filename prefix actually used: [screenshotFilePrefix] when
  /// set, otherwise [productName] lowercased with non-alphanumerics collapsed
  /// to `-` (e.g. `'NetCrux'` → `'netcrux'`).
  String get resolvedScreenshotFilePrefix {
    final explicit = screenshotFilePrefix;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final slug = productName
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'crux' : slug;
  }

  /// The GitHub new-issue endpoint, without any query parameters.
  Uri get newIssueUrl => Uri.https(host, '/$repositorySlug/issues/new');

  /// Returns a copy of this configuration with the given fields replaced.
  CruxIssueReporterConfig copyWith({
    String? productName,
    String? repositorySlug,
    String? issueTemplate,
    List<String>? defaultLabels,
    String? host,
    String? screenshotFilePrefix,
    int? maxIssueUrlLength,
  }) => CruxIssueReporterConfig(
    productName: productName ?? this.productName,
    repositorySlug: repositorySlug ?? this.repositorySlug,
    issueTemplate: issueTemplate ?? this.issueTemplate,
    defaultLabels: defaultLabels ?? this.defaultLabels,
    host: host ?? this.host,
    screenshotFilePrefix: screenshotFilePrefix ?? this.screenshotFilePrefix,
    maxIssueUrlLength: maxIssueUrlLength ?? this.maxIssueUrlLength,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxIssueReporterConfig &&
          runtimeType == other.runtimeType &&
          productName == other.productName &&
          repositorySlug == other.repositorySlug &&
          issueTemplate == other.issueTemplate &&
          _listEquals(defaultLabels, other.defaultLabels) &&
          host == other.host &&
          screenshotFilePrefix == other.screenshotFilePrefix &&
          maxIssueUrlLength == other.maxIssueUrlLength;

  @override
  int get hashCode => Object.hash(
    productName,
    repositorySlug,
    issueTemplate,
    Object.hashAll(defaultLabels),
    host,
    screenshotFilePrefix,
    maxIssueUrlLength,
  );

  @override
  String toString() =>
      'CruxIssueReporterConfig($productName → $host/$repositorySlug)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
