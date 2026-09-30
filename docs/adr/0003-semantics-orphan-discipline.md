# ADR 0003 — Overlay-anchored widgets in routes go through crux_a11y, and every dialog is orphan-guarded

**Status:** Accepted (2026-09-13)
**Scope:** Cross-suite — every product's dialogs, pushed routes, menus and
tooltips on the three desktop platforms.
**Related:** flutter/flutter#190357, #182444, #175041.

## Context

The desktop accessibility bridge in the Flutter engine
(`shell/platform/common/accessibility_bridge.cc`, shared by macOS, Windows and
Linux) accepts a semantics update only if every serialized node is either the
root or listed in some node's `childrenInTraversalOrder`. It rejects the whole
update otherwise, and because it also discards the pending node data, the
native tree stops following the app for the rest of the session: a screen
reader keeps describing the screen as it was before the offending widget
appeared. In release builds the same file dereferences a null parent when a
node it has crowned as root is later re-listed as a child, which terminates
the process.

Two framework widgets produce an unclaimed node in ordinary use: `Slider`
(its value indicator is an `OverlayPortal` whose child loses its traversal
parent when the slider sits in a pushed route or dialog) and a `Tooltip`
hosted directly inside a `MenuAnchor` builder (the two portal anchors merge
into one node and one identifier is dropped). Both defects are open upstream
with no merged fix, and the suite has sliders at seven dialog-hosted sites
(two of them in shared packages every product mounts) and the
menu-plus-tooltip shape in NetCrux Pro's collaboration chip.

## Decision

1. A `Slider` that can appear inside a dialog or pushed route is written as
   `CruxSlider` from `crux_a11y`, which hosts the slider in its own
   `Overlay`. This is a one-word substitution for the parameters it forwards
   (value, range, divisions, label, colours, callbacks, focus and semantic
   formatting), with the same look, keyboard handling and screen-reader
   announcements.
2. A `MenuAnchor` whose builder returns a `Tooltip` places a
   `Semantics(container: true)` between them. The boundary is the fix; no
   widget wraps it.
3. Every dialog, pushed route and menu surface a product ships carries a
   widget test that opens it with semantics enabled and calls
   `SemanticsOrphanGuard.instance.check()` from `crux_a11y_testing.dart`.
   The guard re-implements the bridge's invariant in Dart, so the class of
   defect fails `flutter test` on any platform instead of being found by a
   screen-reader user.
4. `crux_a11y` depends on `flutter_test` from its regular dependencies. That
   is deliberate: the harness is the product, and the barrel that products
   compile into their binaries (`crux_a11y.dart`) does not import it.

## Consequences

- The workarounds are removable the day the upstream fixes ship in the
  pinned Flutter: `CruxSlider` becomes an alias for `Slider`, and the boundary
  in rule 2 becomes harmless. The guard in rule 3 stays, because it protects
  against every future widget with the same shape.
- A new shared widget that anchors an `OverlayPortal` (menus, tooltips,
  autocompletes, dropdowns) is expected to ship with an orphan-guard test in
  the same change.
- The guard cannot see the engine's second, timing-dependent failure — a
  bridge created while a partial update from a previous semantics owner is
  still in flight. That one is closed at the native layer, not in Dart.
