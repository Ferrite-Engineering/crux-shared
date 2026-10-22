// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How an annotation relates to what is loaded now.
///
/// Computed fresh on every load rather than stored: the whole point is that
/// the answer can change when the design does.
enum CruxAnnotationStatus {
  /// The annotated element is on the canvas, and it still agrees with the
  /// witness recorded when the note was written (or there is nothing to
  /// compare).
  resolved,

  /// The annotated element is on the canvas, but it no longer agrees with the
  /// witness.
  ///
  /// **Not an error.** The note is intact and its claim may still be worth
  /// reading; what changed is the design underneath it. Drift is the feature
  /// working: it says a claim needs re-checking.
  drifted,

  /// The element exists in what is loaded but is not on the canvas, so there
  /// is nothing to draw against. Panels list these as "Not displayed" (or,
  /// where the canvas shows one scope at a time, "Outside the current scope").
  orphaned,

  /// No such element in what is loaded at all: a note written against a
  /// different design, or an element since renamed or removed. Panels list
  /// these as "Not in this file" (or "Missing").
  unresolved,

  /// The anchor names no single element (a span across every row, a note on a
  /// whole scope), so it can neither drift nor be orphaned.
  unanchoredToRow,
}

/// Whether the canvas draws an annotation with this status. Orphaned and
/// unresolved notes have nothing to draw against; the panel owns them.
extension CruxAnnotationStatusDrawing on CruxAnnotationStatus {
  /// True for [CruxAnnotationStatus.resolved], [CruxAnnotationStatus.drifted]
  /// and [CruxAnnotationStatus.unanchoredToRow].
  bool get isDrawable => switch (this) {
    CruxAnnotationStatus.resolved ||
    CruxAnnotationStatus.drifted ||
    CruxAnnotationStatus.unanchoredToRow => true,
    CruxAnnotationStatus.orphaned || CruxAnnotationStatus.unresolved => false,
  };
}

/// Classifies one annotation. The decision table both products share.
///
/// [anchoredToElement] — the anchor names one element
/// (`CruxAnnotationAnchor.elementId` is non-null).
/// [existsInFile] — that element exists in what is loaded.
/// [isDisplayed] — that element is on the canvas now.
/// [witnessMatches] — the product's comparison of the recorded witness with
/// the element as it is now: `true` or `false`, or `null` when there is
/// nothing to compare (no witness was recorded, or nothing can be read now).
///
/// Precedence: an unanchored note never drifts; a missing element outranks a
/// hidden one; a hidden one outranks drift; and with nothing to compare, the
/// note is resolved. Reporting drift without a comparison would flag every
/// note whose witness could not be captured, which is noise, not information.
CruxAnnotationStatus cruxAnnotationStatusOf({
  required bool anchoredToElement,
  required bool existsInFile,
  required bool isDisplayed,
  bool? witnessMatches,
}) {
  if (!anchoredToElement) return CruxAnnotationStatus.unanchoredToRow;
  if (!existsInFile) return CruxAnnotationStatus.unresolved;
  if (!isDisplayed) return CruxAnnotationStatus.orphaned;
  return witnessMatches == false
      ? CruxAnnotationStatus.drifted
      : CruxAnnotationStatus.resolved;
}

/// Annotations partitioned the way a panel groups them: the ones the canvas
/// draws, then "Not displayed" ([orphaned]), then "Not in this file"
/// ([unresolved]). Each list keeps the input order.
@immutable
final class CruxAnnotationStatusGroups<T> {
  /// Creates the partition.
  const CruxAnnotationStatusGroups({
    required this.displayed,
    required this.orphaned,
    required this.unresolved,
  });

  /// Everything the canvas can draw: resolved, drifted and unanchored notes,
  /// and any note whose status is not known.
  final List<T> displayed;

  /// Notes whose element exists but is not on the canvas.
  final List<T> orphaned;

  /// Notes whose element is not in what is loaded.
  final List<T> unresolved;

  /// True when all three groups are empty.
  bool get isEmpty =>
      displayed.isEmpty && orphaned.isEmpty && unresolved.isEmpty;
}

/// Partitions [items] by [statusOf] into a [CruxAnnotationStatusGroups].
///
/// An item with no status (`null`) is grouped with the displayed ones: an
/// unknown status is not evidence that a note is lost.
CruxAnnotationStatusGroups<T> cruxGroupByStatus<T>(
  Iterable<T> items,
  CruxAnnotationStatus? Function(T item) statusOf,
) {
  final displayed = <T>[];
  final orphaned = <T>[];
  final unresolved = <T>[];
  for (final item in items) {
    switch (statusOf(item)) {
      case CruxAnnotationStatus.orphaned:
        orphaned.add(item);
      case CruxAnnotationStatus.unresolved:
        unresolved.add(item);
      case _:
        displayed.add(item);
    }
  }
  return CruxAnnotationStatusGroups<T>(
    displayed: displayed,
    orphaned: orphaned,
    unresolved: unresolved,
  );
}
