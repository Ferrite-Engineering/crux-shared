// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite VS Code-style command palette widget for the EDACrux suite.
///
/// Exports `CommandPalette<T extends CruxAction>` (the generic widget) and
/// its `ScrollWrapperBuilder` / `ShortcutActivatorLabel` typedefs.
///
/// See the package README for the canonical usage pattern.
library;

// The `debug*ScoreCount` diagnostics and the key-handler `debugLabel` are
// test-only instrumentation and are deliberately not part of the public
// surface; the package's own tests import them from src.
export 'src/command_palette.dart'
    hide
        commandPaletteKeyHandlerDebugLabel,
        debugCommandPaletteScoreCount,
        debugResetCommandPaletteScoreCount;
