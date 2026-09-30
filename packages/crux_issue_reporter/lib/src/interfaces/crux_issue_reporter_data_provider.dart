// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/src/models/crux_issue_category.dart';
import 'package:crux_issue_reporter/src/models/crux_issue_session_context.dart';

/// Extension point through which an overlay build contributes extra categories
/// to the beta issue reporter.
///
/// This is the **overlay seam**, distinct from the product's own session
/// contributor (`cruxIssueSessionContextProvider`):
///
/// - the *product* (open-core) supplies the Session State snapshot;
/// - the *Pro overlay* supplies additional whole categories, e.g. a "Pro
///   State" section summarizing active Pro decoder bindings or Pro panel
///   layout, surfaced only when at least one Pro feature is in use.
///
/// The package default — [NoopCruxIssueReporterDataProvider] — returns an
/// empty list, so open-core builds show only the built-in categories. The
/// overlay replaces `cruxIssueReporterDataProviderProvider` in its overrides
/// list.
///
/// Pure-Dart interface: no Flutter imports. A data provider that needs to
/// localize its category title resolves it from
/// [CruxIssueSessionContext.localeTag], so this package never depends on the
/// overlay's ARB.
abstract interface class CruxIssueReporterDataProvider {
  /// Returns the additional categories to append to the issue report given
  /// the current privacy-scrubbed [context]. Return `const []` to contribute
  /// nothing.
  List<CruxIssueCategory> extraCategories(CruxIssueSessionContext context);
}

/// The package default that contributes no extra categories.
class NoopCruxIssueReporterDataProvider
    implements CruxIssueReporterDataProvider {
  /// Creates the no-op data provider.
  const NoopCruxIssueReporterDataProvider();

  @override
  List<CruxIssueCategory> extraCategories(CruxIssueSessionContext context) =>
      const [];
}
