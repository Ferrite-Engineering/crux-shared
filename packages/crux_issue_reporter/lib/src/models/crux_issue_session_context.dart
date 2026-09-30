// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One label/value pair in the Session State category, rendered as a markdown
/// bullet (`- **<label>:** <value>`).
///
/// **Privacy contract.** A field's [value] must be a count, a format name, a
/// display name or another piece of non-identifying metadata. It must never
/// contain a filesystem path, a signal value, a design identifier taken from
/// the user's own source, or any other private file content. See
/// [CruxIssueSessionContext].
@immutable
class CruxIssueField {
  /// Creates a session field.
  const CruxIssueField({required this.label, required this.value});

  /// The localized human-readable label (e.g. `'Open tabs'`).
  final String label;

  /// The rendered value (e.g. `'3'`, `'VCD'`, `'SPI #1, UART #2'`).
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxIssueField &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          value == other.value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => 'CruxIssueField($label: $value)';
}

/// A privacy-scrubbed snapshot of the host product's current session.
///
/// This is the **product seam** of the issue reporter. The package knows
/// nothing about tabs, waveforms, netlists, lint findings or simulations, so
/// each product overrides `cruxIssueSessionContextProvider` to assemble the
/// [fields] it wants in the Session State category, plus any structured
/// [attributes] a Pro overlay's `CruxIssueReporterDataProvider` wants to
/// read when building its own extra categories.
///
/// **Privacy contract.** Carries **no file paths, no private file contents and
/// no signal values** — only counts, format names, display names and
/// environment metadata. More context helps reproduce a bug, but never at the
/// cost of leaking a user's filesystem layout or design data. A test in this
/// package asserts that a rendered Session State body contains no path
/// separators; the equivalent assertion belongs in every consuming product's
/// own suite, over its real contributor.
///
/// Pure-Dart model: no Flutter imports.
@immutable
class CruxIssueSessionContext {
  /// Creates a session snapshot.
  const CruxIssueSessionContext({
    this.localeTag = '',
    this.fields = const [],
    this.attributes = const {},
  });

  /// The empty snapshot contributed by the package default — a product that
  /// has not wired `cruxIssueSessionContextProvider` gets no Session State
  /// category at all rather than an empty one.
  static const CruxIssueSessionContext empty = CruxIssueSessionContext();

  /// The active locale tag (`'en'`, `'zh_CN'`, `'ja'`, `'ko'`). Lets a data
  /// provider localize its category title without a `BuildContext`. Filled in
  /// by the dialog from the ambient `Localizations` locale; the empty string
  /// when unknown.
  final String localeTag;

  /// Ordered label/value pairs rendered as the Session State bullets. Empty
  /// means the product contributed nothing and the category is omitted.
  final List<CruxIssueField> fields;

  /// Structured, non-rendered attributes carried alongside [fields] for the
  /// benefit of a `CruxIssueReporterDataProvider`. Values should be primitives
  /// or collections of primitives, and are subject to the same privacy
  /// contract as [fields].
  final Map<String, Object?> attributes;

  /// Whether this snapshot contributes nothing to the report.
  bool get isEmpty => fields.isEmpty;

  /// Whether this snapshot contributes at least one field.
  bool get isNotEmpty => fields.isNotEmpty;

  /// Returns a copy of this snapshot with the given fields replaced.
  CruxIssueSessionContext copyWith({
    String? localeTag,
    List<CruxIssueField>? fields,
    Map<String, Object?>? attributes,
  }) => CruxIssueSessionContext(
    localeTag: localeTag ?? this.localeTag,
    fields: fields ?? this.fields,
    attributes: attributes ?? this.attributes,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxIssueSessionContext &&
          runtimeType == other.runtimeType &&
          localeTag == other.localeTag &&
          _listEquals(fields, other.fields) &&
          _mapEquals(attributes, other.attributes);

  @override
  int get hashCode => Object.hash(
    localeTag,
    Object.hashAll(fields),
    Object.hashAllUnordered(attributes.keys),
  );

  @override
  String toString() =>
      'CruxIssueSessionContext(locale: $localeTag, '
      'fields: ${fields.length}, attributes: ${attributes.length})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
