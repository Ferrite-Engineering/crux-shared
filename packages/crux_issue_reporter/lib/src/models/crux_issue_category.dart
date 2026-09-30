// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One toggleable section of a beta issue report.
///
/// Each category carries a stable [id] (used by the dialog to track its
/// on/off toggle state and by tests to find a specific tile), a localized
/// [title] for the tile header, and the [markdownBody] that will be appended
/// to the GitHub issue body when the category is enabled.
///
/// The package builds the App & Environment, Session State and Diagnostic Log
/// categories; the `CruxIssueReporterDataProvider` extension point contributes
/// any additional categories (e.g. a Pro overlay's "Pro State" summary).
/// The Screenshot category is *not* a [CruxIssueCategory] — it is an image
/// attachment handled separately by the dialog, since its content is a PNG
/// file rather than markdown text.
///
/// Pure-Dart model: no Flutter imports.
@immutable
class CruxIssueCategory {
  /// Creates an issue-report category.
  const CruxIssueCategory({
    required this.id,
    required this.title,
    required this.markdownBody,
    this.description,
  });

  /// Stable identifier for this category (e.g. `'appEnv'`, `'session'`,
  /// `'log'`, `'proState'`). Used for toggle-state keys and widget-test
  /// lookups; never shown to the user.
  final String id;

  /// Localized human-readable title rendered as the tile header.
  final String title;

  /// Optional localized one-line summary of what the category contributes,
  /// rendered under the tile title. `null` hides the subtitle.
  final String? description;

  /// The markdown content appended to the GitHub issue body when this
  /// category is enabled. Does not include the leading `## <title>` heading —
  /// the service writes that around the body when assembling the document.
  final String markdownBody;

  /// Returns a copy of this category with the given fields replaced.
  CruxIssueCategory copyWith({
    String? id,
    String? title,
    String? description,
    String? markdownBody,
  }) => CruxIssueCategory(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    markdownBody: markdownBody ?? this.markdownBody,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxIssueCategory &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          markdownBody == other.markdownBody;

  @override
  int get hashCode => Object.hash(id, title, description, markdownBody);

  @override
  String toString() => 'CruxIssueCategory(id: $id, title: $title)';
}
