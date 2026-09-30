// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_window_chrome/src/widgets/window_title_bar.dart';
import 'package:crux_window_chrome/src/window_bounds.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Real (`dart:io`) implementation of the window-chrome facade. Selected by
/// the conditional export in `window_chrome.dart` on every platform that has
/// `dart:io` (desktop + mobile); never compiled for web.
///
/// All entry points are still only *invoked* on Windows/Linux — callers guard
/// with `useCustomWindowChrome`, and `buildWindowTitleBar` is only reached from
/// each host's `DesktopMenuBar` Windows/Linux branch.

/// Switches the window to frameless (`TitleBarStyle.hidden`) and shows it once
/// Flutter is ready. The matching [buildWindowFrame] restores the shadow and
/// drag-to-resize edges a frameless window loses.
///
/// When [restore] is supplied (the persisted geometry from the last session),
/// the window is sized and positioned to match *before* it is first shown, so
/// there is no visible jump. The bounds are sanitized first
/// ([WindowBounds.sanitizedForRestore]) so a stale, off-screen, or degenerate
/// snapshot falls back to a sane centered default rather than restoring the
/// window somewhere unreachable. A null [restore] (first launch, or restore
/// disabled) opens at the default 1280×720, centered.
Future<void> initWindowChrome({WindowBounds? restore}) async {
  await windowManager.ensureInitialized();
  final bounds = restore?.sanitizedForRestore();
  final windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    // Keep the same minimum the native runners requested (800x500) so the
    // chrome never collapses.
    minimumSize: const Size(800, 500),
    // Size before show to avoid a default-then-resize flash. Position can't be
    // set via WindowOptions, so it is applied via setBounds in the callback.
    size: bounds == null ? null : Size(bounds.width, bounds.height),
    center: bounds == null || !bounds.hasPosition,
  );
  unawaited(
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (bounds != null) {
        if (bounds.maximized) {
          await windowManager.maximize();
        } else if (bounds.hasPosition) {
          await windowManager.setBounds(
            Rect.fromLTWH(
              bounds.left!,
              bounds.top!,
              bounds.width,
              bounds.height,
            ),
          );
        }
      }
      await windowManager.show();
      await windowManager.focus();
    }),
  );
}

/// Reads the current OS window geometry (position, size, maximized) for
/// persistence. Returns null on any failure — a failed read just means this
/// change is not saved.
///
/// When maximized, [WindowBounds.maximized] is true and the returned rect is
/// the maximized (full-work-area) rect; the restorer re-maximizes and ignores
/// the rect, so an un-maximize after restore uses the OS default restore size.
Future<WindowBounds?> readCurrentWindowBounds() async {
  try {
    final maximized = await windowManager.isMaximized();
    final rect = await windowManager.getBounds();
    return WindowBounds(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      maximized: maximized,
    );
  } on Object {
    return null;
  }
}

/// Wraps [child] with a window-event listener that persists the window geometry
/// whenever the user resizes, moves, maximizes, or unmaximizes the window —
/// debounced so a single drag produces one save, and de-duplicated so identical
/// geometry is not re-written.
///
/// This is what makes geometry survive **reliably**: it is recorded *during the
/// session* via [onChanged] (which schedules the host's debounced persist),
/// instead of depending on a quit-time flush that a hard window-close or a
/// killed `flutter run` debug session may never complete. A quit flush remains
/// a best-effort final capture on top of this.
Widget buildWindowGeometryPersister({
  required Widget child,
  required Future<void> Function(WindowBounds bounds) onChanged,
}) => _WindowGeometryPersister(onChanged: onChanged, child: child);

class _WindowGeometryPersister extends StatefulWidget {
  const _WindowGeometryPersister({
    required this.child,
    required this.onChanged,
  });

  final Widget child;
  final Future<void> Function(WindowBounds bounds) onChanged;

  @override
  State<_WindowGeometryPersister> createState() =>
      _WindowGeometryPersisterState();
}

class _WindowGeometryPersisterState extends State<_WindowGeometryPersister>
    with WindowListener {
  Timer? _debounce;
  WindowBounds? _lastPersisted;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final bounds = await readCurrentWindowBounds();
    if (bounds == null || bounds == _lastPersisted) return;
    _lastPersisted = bounds;
    await widget.onChanged(bounds);
  }

  // Both the continuous (`onWindowResize`) and completed (`onWindowResized`)
  // variants are observed because platforms differ in which they emit; the
  // debounce collapses a burst into one save either way.
  @override
  void onWindowResize() => _schedule();
  @override
  void onWindowResized() => _schedule();
  @override
  void onWindowMove() => _schedule();
  @override
  void onWindowMoved() => _schedule();
  @override
  void onWindowMaximize() => _schedule();
  @override
  void onWindowUnmaximize() => _schedule();

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wraps the whole app in a [VirtualWindowFrame] so the frameless window keeps
/// a drop shadow and drag-to-resize edges.
Widget buildWindowFrame(Widget child) => VirtualWindowFrame(child: child);

/// Builds the VS Code-style custom title bar hosting [menuBar] inline with the
/// app [logo] and the min/maximize/close caption buttons.
Widget buildWindowTitleBar({
  required Widget menuBar,
  required Widget logo,
}) => WindowTitleBar(menuBar: menuBar, logo: logo);

/// Composes the complete in-window chrome: the VS Code-style title bar
/// ([logo] + [menuBar] + caption buttons) above [child], as a left-packed
/// full-width strip.
///
/// This is the single composition every product renders on Windows/Linux, so
/// the chrome behaves identically regardless of *where* the host mounts it in
/// its tree. In particular it provides its own [Overlay]: the in-window
/// `MnemonicMenuBar` renders a Material `MenuBar`, whose dropdowns require an
/// `Overlay` ancestor, and the chrome is frequently mounted above the app's
/// `Navigator` (e.g. from `MaterialApp.builder`) where none exists. A
/// full-screen `Overlay` here means the menu dropdowns are never clipped;
/// nesting under an existing route's `Overlay` is harmless.
Widget buildWindowChrome({
  required Widget menuBar,
  required Widget logo,
  required Widget child,
}) {
  final chrome = Column(
    // Stretch so the title strip fills the window width and its buttons pack
    // from the left edge (native convention), rather than the Column's default
    // center shrink-wrap.
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WindowTitleBar(menuBar: menuBar, logo: logo),
      Expanded(child: child),
    ],
  );
  return Builder(
    builder: (context) {
      // Adapt to the host: if the chrome is mounted inside a route (an Overlay
      // already exists above it, as when DesktopMenuBar wraps a screen), reuse
      // it — nesting a second Overlay changes build/flush timing and can
      // re-trigger a host's provider-rebuild cascade. Only when there is no
      // Overlay (mounted in MaterialApp.builder, above the Navigator) does the
      // chrome supply its own, so the Material MenuBar always has one.
      //
      // `Overlay.wrap`, not `Overlay(initialEntries: …)`: an Overlay reads
      // its initial entries once, so an entry built from `chrome` would keep
      // the first menu bar and child forever and every later rebuild would be
      // dropped, which froze each menu item's enabled state at launch.
      // `Overlay.wrap` rebuilds its entry whenever the chrome is rebuilt.
      if (Overlay.maybeOf(context) != null) return chrome;
      return Overlay.wrap(child: chrome);
    },
  );
}
