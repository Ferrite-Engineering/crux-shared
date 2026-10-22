# ADR 0006 — Annotations are one shared layer, anchored in each product's data coordinates

**Status:** Accepted (2026-10-22)
**Scope:** Cross-suite — the on-canvas annotation layer WaveCrux draws over its
waveform and NetCrux draws over its schematic, through `crux_annotations`.

## Context

WaveCrux draws its annotations on the canvas: a balloon with a leader line to an
anchor, a numbered dot when folded, a label that can be dragged without moving
the anchor, and a **drifted** state when the trace no longer reads what it read
when the note was written. NetCrux keeps annotations too, pinned to a cell, pin,
boundary port, net or scope, but showed them only in its Annotations panel and as
a corner badge on the element.

NetCrux needs the same callouts. Building them a second time would give the suite
two annotation layers that agree on day one and drift apart afterwards, which is
the failure the suite rule "WaveCrux is the reference implementation for a pattern
both products need" exists to prevent. The two products disagree on everything
about *where* a note is (a tick and a trace row against an element of a module)
and on *what* proves it still holds (a value at a tick against the element's
structure), and agree on everything about *how* a note is drawn, moved, folded
and flagged.

The decision somebody will want to re-litigate is the line between those two
halves, and the anchor contract in particular: a shared layer that let an anchor
be expressed in pixels would work in a demo and lose every note on the first pan.

## Decision

1. **One package, `crux_annotations`, owns the shared half.** It is a Flutter
   package in crux-shared, consumed by WaveCrux and NetCrux.
2. **Anchors are product data coordinates, never pixels and never indices.** The
   shared contract is `CruxAnnotationAnchor`: a product type that serialises
   itself (`toJson`) and names the one element it is pinned to (`elementId`), or
   `null` when it is pinned to no single element (a full-height span, a note on a
   whole scope). The package never resolves an anchor; how an anchor becomes a
   point on screen (a trace row and a tick, an element of a laid-out module) is
   the product's, and is recomputed on every frame from the product's own
   viewport.
3. **The label lives in a second coordinate space.** `CruxCalloutPlacement` holds
   the label's offset from the anchor's projected point in logical pixels, and
   whether the note is folded to a numbered dot. Dragging a label changes the
   placement and never the anchor; only an explicit re-anchor gesture, which is a
   product's, changes the anchor. The fold is a fold, not a hide: a folded note
   is still listed and still navigable.
4. **The status vocabulary and its decision table are shared.**
   `CruxAnnotationStatus` is `resolved`, `drifted`, `orphaned` (the element
   exists but is not on the canvas: shown as "Not displayed", or in NetCrux
   "Outside the current scope"), `unresolved` (no such element: "Not in this
   file", or in NetCrux "Missing") and `unanchoredToRow` (pinned to no single
   element). `cruxAnnotationStatusOf` decides it, in that precedence: an
   unanchored note never drifts, a missing element outranks a hidden one, a
   hidden one outranks drift, and with nothing to compare the note is resolved.
   Drift is drawn the same way in both products: a dashed leader, the amber
   `kCruxAnnotationDriftedColor`, italic text. Orphaned and unresolved notes draw
   nothing on the canvas; the panel lists them in their own groups.
5. **The witness is the product's; the comparison feeds the shared table.** A
   product records a witness when the note is written (WaveCrux: the trace's
   canonical bits at the tick; NetCrux: the element's type and parameters, and
   for a net its driver) and decides whether the current design agrees with it.
   The package only receives that answer.
6. **The persistence shape is WaveCrux's.** An annotation record is a JSON object
   whose product fields sit beside the shared ones: `labelDx`, `labelDy` (each
   omitted at its default, `0` and `-32`), `collapsed` (omitted when false) and
   `witness` (the product's witness object, omitted when none was captured).
   `CruxCalloutPlacement.fromJson` reads the label fields tolerantly: a missing
   or malformed value is the default, never an exception, because one bad note
   must not fail a session load.
7. **The drawing and the drag model are shared widgets**: the leader painter,
   the balloon, the numbered dot, the inline editor, the draggable that claims
   the pointer from the canvas underneath, the double-tap recogniser that does
   not enter the gesture arena, the crowding rule (at most
   `kCruxCalloutMaxExpanded` open balloons, the rest fold), and the level of
   detail a product maps its zoom onto (`CruxCalloutDetail`: balloon, dot,
   hidden). The panel shell is the group header and the status partition the
   panels group by.
8. **What stays per product:** anchor resolution to the screen, the witness and
   its comparison, the gestures that create a note, the shapes only one product
   has (WaveCrux's time bands and arrows), the panel rows and their menus, and
   every string. The package carries no localizations; callers pass labels in.
9. **Tier is the consumer's.** The package gates nothing (ADR 0002). WaveCrux
   ships its annotations in open core; NetCrux decides its own tier for drawing
   them on the schematic, and moving that tier is a change to NetCrux's gate,
   never to this package.

## Consequences

- WaveCrux moves onto the package with no change in behaviour: its anchor types
  implement `CruxAnnotationAnchor`, its status enum is `CruxAnnotationStatus`
  under its old name, and its overlay draws with the shared widgets. Its
  `.wavecrux` and `.wavecruxpack` documents are unchanged byte for byte, because
  the shared persistence shape is the one they already wrote.
- NetCrux adds `labelDx`, `labelDy`, `collapsed` and `witness` to its annotation
  records. Older NetCrux builds ignore the unknown fields on load.
- A third product that wants on-canvas notes implements an anchor, a projection
  and a witness, and gets the drawing, the drag model, drift and the panel
  grouping without writing them.
- The status value names are WaveCrux's, including `unanchoredToRow`, so WaveCrux
  could adopt the enum without renaming a value its tests and exports use.
- **Considered and rejected:** a generic `CruxAnnotation<A>` model class shared
  by both products. The two models differ in nearly every field (WaveCrux has
  shapes, layers and a time sort; NetCrux has titles, Markdown bodies, modules
  and session attribution), and a shared class would either carry both sets or
  force one product's records into the other's shape. The shared fields are the
  placement and the witness slot, and those are what is shared.
- **Considered and rejected:** letting the shared layer project anchors through
  a product callback inside the package. The projection reads each product's
  live viewport providers every frame; hiding that behind a callback would move
  no code and would make the per-frame cost invisible at the call site.
