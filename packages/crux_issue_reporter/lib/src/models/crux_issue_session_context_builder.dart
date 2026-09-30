// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/src/models/crux_issue_session_context.dart';
import 'package:meta/meta.dart';

/// The canonical placeholder values a session field uses when it has nothing
/// to report.
///
/// Before these existed the four products had each invented their own, and had
/// drifted: WaveCrux rendered `(no file loaded)` where SimCrux rendered
/// `(none loaded)` for the same idea, and only SimCrux had a marker for a value
/// deliberately withheld for privacy. A bug report is read by a human
/// comparing four products' reports side by side, so the vocabulary is worth
/// fixing in one place.
abstract final class CruxIssueFallback {
  /// The collection is empty — no decoders active, no engines enabled.
  static const String none = '(none)';

  /// Nothing is loaded yet — no file, no project, no design.
  static const String noneLoaded = '(none loaded)';

  /// The value could not be determined (a probe failed, a version lookup
  /// returned nothing). Distinct from [none]: this is "we do not know",
  /// not "there are zero".
  static const String unavailable = '(unavailable)';

  /// No filter is narrowing the view — everything is included.
  static const String all = '(all)';

  /// Deliberately withheld. Use for anything that would otherwise carry a
  /// filesystem path, a credential, or user design data into a bug report.
  static const String redacted = '(redacted)';
}

/// Accumulates a product's privacy-scrubbed [CruxIssueSessionContext].
///
/// Each product's session-context function was independently hand-rolling the
/// same four moves — add a labelled field, substitute a placeholder when the
/// value is missing, record a machine-readable attribute alongside it, and wrap
/// the provider reads in a degrade-on-failure guard. This collects those moves
/// so the products supply only their own field list.
///
/// ### The privacy contract this helps you keep
///
/// Every value that reaches a field is rendered into a bug report the user
/// will paste somewhere public. Counts, format names, enum labels and display
/// names are safe; filesystem paths, signal values, credentials and design
/// content are not. The builder cannot enforce that — only the product knows
/// which is which — but [redact] gives the intent a name, and each product's
/// sibling test asserting "no path separator appears in the rendered body"
/// remains the real guard.
///
/// ### Degrading rather than failing
///
/// [guard] runs a block and swallows anything it throws. That is deliberate
/// and matches what all four products already did by hand: the issue reporter
/// exists to let a user report a broken state, so it must open even when the
/// state it wants to describe is the broken thing. A bare unit-test container
/// with no workspace plumbing is the common case.
class CruxIssueSessionContextBuilder {
  /// Creates an empty builder.
  CruxIssueSessionContextBuilder({this.localeTag = ''});

  /// Active locale tag, forwarded to the built [CruxIssueSessionContext].
  final String localeTag;

  final List<CruxIssueField> _fields = <CruxIssueField>[];
  final Map<String, Object?> _attributes = <String, Object?>{};

  /// Adds a field whose value is already a rendered string.
  ///
  /// When [value] is null or empty, [fallback] is rendered instead.
  void addText(
    String label,
    String? value, {
    String fallback = CruxIssueFallback.none,
    String? attributeKey,
  }) {
    final rendered = (value == null || value.isEmpty) ? fallback : value;
    _fields.add(CruxIssueField(label: label, value: rendered));
    if (attributeKey != null) _attributes[attributeKey] = value;
  }

  /// Adds a numeric field, recording the number itself as the attribute so a
  /// downstream consumer does not have to re-parse the rendered string.
  void addCount(String label, int value, {String? attributeKey}) {
    _fields.add(CruxIssueField(label: label, value: '$value'));
    if (attributeKey != null) _attributes[attributeKey] = value;
  }

  /// Adds a field rendering [values] as a comma-separated list.
  ///
  /// The attribute records the list itself, not the joined string. Sort before
  /// passing when the order is not itself meaningful — a report that reorders
  /// between runs is harder to diff.
  void addList(
    String label,
    List<String> values, {
    String fallback = CruxIssueFallback.none,
    String? attributeKey,
  }) {
    _fields.add(
      CruxIssueField(
        label: label,
        value: values.isEmpty ? fallback : values.join(', '),
      ),
    );
    if (attributeKey != null) _attributes[attributeKey] = values;
  }

  /// Adds a boolean field rendered as `yes` / `no`.
  void addFlag(String label, {required bool value, String? attributeKey}) {
    _fields.add(CruxIssueField(label: label, value: value ? 'yes' : 'no'));
    if (attributeKey != null) _attributes[attributeKey] = value;
  }

  /// Adds a field whose value exists but is deliberately withheld.
  ///
  /// Records no attribute — a redacted value must not leak through the
  /// machine-readable channel either.
  void redact(String label) {
    _fields.add(
      CruxIssueField(label: label, value: CruxIssueFallback.redacted),
    );
  }

  /// Records a machine-readable attribute with no corresponding visible field.
  void attribute(String key, Object? value) => _attributes[key] = value;

  /// Runs [block], swallowing anything it throws.
  ///
  /// Returns true when the block completed. Use it around provider reads that
  /// depend on workspace plumbing which may not exist yet.
  bool guard(void Function() block) {
    try {
      block();
      return true;
    } on Object {
      return false;
    }
  }

  /// The accumulated snapshot.
  CruxIssueSessionContext build() => CruxIssueSessionContext(
    localeTag: localeTag,
    fields: List<CruxIssueField>.unmodifiable(_fields),
    attributes: Map<String, Object?>.unmodifiable(_attributes),
  );

  /// The fields added so far. Exposed for tests that assert ordering.
  @visibleForTesting
  List<CruxIssueField> get fields => List<CruxIssueField>.unmodifiable(_fields);
}
