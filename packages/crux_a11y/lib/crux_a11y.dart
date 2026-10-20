// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Accessibility workarounds for the EDACrux suite.
///
/// The desktop accessibility bridge (`shell/platform/common` in the Flutter
/// engine, shared by macOS, Windows and Linux) rejects any semantics update
/// that serializes a node no other node claims as a child, and once it has
/// rejected one update the native tree stops following the app. Two framework
/// widgets produce such a node in an incremental update: a [Slider] whose
/// route was pushed (its value indicator lives in an `OverlayPortal`), and a
/// `Tooltip` hosted directly inside a `MenuAnchor` builder. This library holds
/// the drop-in replacements; the matching test harness lives in
/// `crux_a11y_testing.dart`.
///
/// It also holds the pieces a modal surface needs when it cannot be a route —
/// a licence agreement or consent disclosure mounted above the app's
/// `Navigator`: [CruxModalGate] keeps focus and semantics off the app behind
/// the surface and hands focus back when it closes, [CruxModalSurface] traps
/// focus in the dialog and names it, and [CruxScrollRegion] makes a block of
/// scrolling text a Tab stop the keyboard can scroll.
///
/// [CruxRegionHintHost] and [CruxRegionHint] let a region's content describe
/// the region without renaming it: an empty dock keeps its title as its name
/// and gains its empty message as its description.
///
/// [CruxSwitch] is the suite's desktop switch, drawn at its 32×18 size rather
/// than a scaled Material switch, with Space and Enter, a toggled semantics
/// node named by its row, and an always-visible focus ring.
library;

import 'package:crux_a11y/crux_a11y.dart'
    show
        CruxModalGate,
        CruxModalSurface,
        CruxRegionHint,
        CruxRegionHintHost,
        CruxScrollRegion,
        CruxSwitch;
import 'package:flutter/material.dart' show Slider;

export 'src/crux_slider.dart';
export 'src/crux_switch.dart';
export 'src/modal_gate.dart';
export 'src/region_hint.dart';
export 'src/scroll_region.dart';
