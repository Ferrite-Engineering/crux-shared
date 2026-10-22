# Changelog

## Unreleased

- Initial release (0.1.0), lifted from WaveCrux's annotation layer so NetCrux can draw
  the same callouts on its schematic. The package boundary and the anchor
  contract are recorded in ADR 0006.
- `CruxAnnotationAnchor` and `CruxAnnotationWitness`: the anchor in the
  product's data coordinates and the witness slot (`kCruxAnnotationWitnessKey`).
- `CruxAnnotationStatus`, `cruxAnnotationStatusOf`, `isDrawable`,
  `kCruxAnnotationDriftedColor`, `CruxAnnotationStatusGroups` and
  `cruxGroupByStatus`. The value names are WaveCrux's, so its exports keep
  their vocabulary.
- `CruxCalloutPlacement`: label offset and fold, with a tolerant record codec
  in the shape WaveCrux documents already carry.
- `CruxCalloutGeometry`, `CruxCalloutDetail` and the size constants.
- `crux_annotations_core.dart`: the `dart:ui`-free subset for domain models
  and headless builds.
- Widgets: `CruxCalloutBalloon`, `CruxCalloutNumberDot`, `CruxCalloutAnchorDot`,
  `CruxCalloutInlineEditor`, `CruxCalloutDraggable`,
  `CruxCalloutDoubleTapRegion`, `CruxCalloutLeader`,
  `CruxCalloutLeadersPainter` and `CruxAnnotationGroup`.
