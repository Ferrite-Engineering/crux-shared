# crux_annotations

The on-canvas annotation layer WaveCrux draws over its traces and NetCrux draws
over its schematic. The boundary between this package and the products is
[ADR 0006](../../docs/adr/0006-annotations-anchor-in-data-coordinates.md).

## What is here

- **The anchor contract.** `CruxAnnotationAnchor`: a product type in the
  product's data coordinates, never pixels and never an index, naming the one
  element it is pinned to (`elementId`) or none.
- **The witness slot.** `CruxAnnotationWitness` and `kCruxAnnotationWitnessKey`:
  what the element was when the note was written, captured and compared by the
  product.
- **Status.** `CruxAnnotationStatus` (`resolved`, `drifted`, `orphaned`,
  `unresolved`, `unanchoredToRow`), the decision table
  `cruxAnnotationStatusOf`, `isDrawable`, the drift amber
  `kCruxAnnotationDriftedColor`, and `cruxGroupByStatus`, the partition a panel
  groups by.
- **Placement.** `CruxCalloutPlacement`: the label's pixel offset from the
  anchor's projected point and whether it is folded, with the record codec
  (`labelDx`, `labelDy`, `collapsed`, each omitted at its default).
- **Geometry.** `CruxCalloutGeometry` (fold rule, label origin, leader end),
  `kCruxCalloutMaxExpanded`, `kCruxCalloutBalloonWidth`,
  `kCruxCalloutDotRadius`, and `CruxCalloutDetail`, the three levels of detail
  a product maps its zoom onto.
- **Widgets.** `CruxCalloutBalloon`, `CruxCalloutNumberDot`,
  `CruxCalloutAnchorDot`, `CruxCalloutInlineEditor`, `CruxCalloutDraggable`
  (claims the pointer from the canvas through `onClaim`),
  `CruxCalloutDoubleTapRegion` (outside the gesture arena),
  `CruxCalloutLeader` with `CruxCalloutLeadersPainter`, and the panel's
  `CruxAnnotationGroup`.

`crux_annotations_core.dart` exports the `dart:ui`-free part (anchor, witness,
placement, status) for domain models and headless builds; a test holds it to
that.

## What is not

Anchor resolution to the screen, the witness and its comparison, the gestures
that create a note, shapes only one product has, the panel rows and their
menus, and every string. The package carries no localizations and gates
nothing: tier is the consumer's.

## Using it

1. Implement `CruxAnnotationAnchor` on the product's anchor type.
2. Project each anchor to a point in the overlay's coordinates every frame,
   from the product's own viewport.
3. Compute each note's status with `cruxAnnotationStatusOf`, feeding it the
   product's own witness comparison.
4. Draw drawable notes with the widgets: leaders in one
   `CruxCalloutLeadersPainter` under an `IgnorePointer`, then a
   `CruxCalloutAnchorDot` and a balloon or numbered dot per note, positioned
   with `CruxCalloutGeometry`, each label inside a `CruxCalloutDraggable`
   whose `onClaim` sets the flag the product's canvas gesture handler reads.
5. Persist the placement with `CruxCalloutPlacement.writeInto` and read it with
   `CruxCalloutPlacement.fromJson`.
