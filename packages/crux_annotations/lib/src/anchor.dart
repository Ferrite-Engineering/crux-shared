// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Where an annotation is attached, in the product's **data coordinates**.
///
/// Never screen pixels, and never a list index: pixels move with every pan and
/// zoom, and indices move whenever the product reorders, groups or hides what
/// it shows. A product implements this with whatever names its data: a tick
/// and a trace row, an element of a module. The shared layer never resolves an
/// anchor; how one becomes a point on screen is the product's, recomputed from
/// its own viewport on every frame.
abstract interface class CruxAnnotationAnchor {
  /// Stable identity of the one element this anchor is pinned to, or `null`
  /// when it is pinned to no single element (a span across every row, a note
  /// on a whole scope).
  ///
  /// It is the key a product's status computation looks the element up by,
  /// and the value the panel searches.
  String? get elementId;

  /// The anchor as JSON, under the record's `anchor` key or flattened into
  /// it, as the product's persistence format already does.
  Map<String, Object?> toJson();
}

/// What the annotated element *was* when the note was written.
///
/// Captured once, by the product, at creation (and again when the note is
/// re-anchored), and compared against the element as it is now on every load.
/// The comparison is the product's too: a trace's value at a tick and an
/// element's structure have nothing in common but the question they answer,
/// which is whether the claim the note makes may no longer hold. The answer
/// feeds `cruxAnnotationStatusOf`.
abstract interface class CruxAnnotationWitness {
  /// The witness as JSON, stored under the record's `witness` key
  /// ([kCruxAnnotationWitnessKey]).
  Map<String, Object?> toJson();
}

/// The record key a product's witness is persisted under. Absent when none
/// was captured.
const String kCruxAnnotationWitnessKey = 'witness';
