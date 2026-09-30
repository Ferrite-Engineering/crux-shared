// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Widget-test harnesses for what a desktop screen reader actually receives.
///
/// Two harnesses live here. The focus walk ([walkFocus], [FocusWalk],
/// [expectFocusAnnounced], [expectFocusWalkGolden], [AnnouncementRecorder])
/// presses Tab through a surface and records each stop the way the desktop
/// bridge hands it to NVDA or VoiceOver: name, role, states, and the named
/// containers entered. It fails on silent and nameless stops, one control
/// under two names, and focus that lands nowhere, and it keeps a plain-text
/// transcript per surface so an unintended change in what is heard shows up
/// as a diff.
///
/// The orphan guard below catches semantics updates the desktop
/// accessibility bridge would reject.
///
/// The engine's `ui::AXTree` accepts an update only if every serialized node
/// is either the root or listed in some node's `childrenInTraversalOrder`. A
/// node that fails that test is rejected with "N will not be in the tree and
/// is not the new root", the update is dropped, and the native tree stops
/// following the app for the rest of the session. This library re-implements
/// that invariant in Dart so a plain `flutter test` — on any platform, with
/// no assistive client — fails when a widget produces such a node.
///
/// Install [SemanticsOrphanTestBinding] (or mix [SemanticsOrphanRecording]
/// into an existing test binding) before the first `testWidgets`, enable
/// semantics with `tester.ensureSemantics()`, drive the UI, then call
/// [SemanticsOrphanGuard.check].
library;

import 'package:crux_a11y/crux_a11y_testing.dart'
    show
        AnnouncementRecorder,
        FocusWalk,
        SemanticsOrphanGuard,
        SemanticsOrphanRecording,
        SemanticsOrphanTestBinding,
        expectFocusAnnounced,
        expectFocusWalkGolden,
        walkFocus;

export 'src/testing/focus_walk.dart';
export 'src/testing/semantics_orphan_guard.dart';
