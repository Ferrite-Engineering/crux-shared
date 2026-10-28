// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// The app's routed content, as `MaterialApp.builder` receives it, kept in
/// its own semantics container so the strips drawn around it stay readable.
///
/// A product mounts its notices (the beta expiry strip, the update strip, the
/// licence expiry strip) and its window chrome in `MaterialApp.builder`,
/// around the `Navigator` rather than inside a route. Every route the
/// `Navigator` shows, a page included, puts a modal barrier under its content,
/// and a modal barrier blocks the semantics of everything painted before it in
/// the same semantics container. Without a boundary that container is the
/// window's, so a strip above the `Navigator` vanished from the semantics
/// tree: Tab still reached its buttons, but each one was a silent stop and a
/// screen reader could not find the strip by reading the screen either.
///
/// Wrap the builder's `child` in this widget, innermost, directly around the
/// `Navigator`:
///
/// ```dart
/// builder: (context, child) => UpdateBanner(
///   child: CruxRoutedContent(child: child),
/// ),
/// ```
///
/// The barrier then blocks only what lies under it inside the `Navigator`.
///
/// **Keyboard.** The router's `Navigator` (go_router's, and
/// `MaterialApp.router`'s generally) hands Tab to the enclosing scope at a
/// route's first and last control (`TraversalEdgeBehavior.parentScope`), and
/// the enclosing scope is the window's, so Tab and Shift+Tab run from the
/// page through every strip and back without a strip ever taking focus on its
/// own. `MaterialApp(home: ...)` is different: it wraps its `Navigator` in a
/// closed-loop scope of its own, which keeps Tab inside the routes.
///
/// **Dialogs.** A dialog keeps Tab inside itself
/// (`TraversalEdgeBehavior.closedLoop`, which `showDialog` and
/// `showCruxDialog` both set). Its barrier still hides the page under it from
/// a screen reader. The strips around the `Navigator` stay readable while it
/// is open, but focus does not reach them until it closes.
class CruxRoutedContent extends StatelessWidget {
  /// Wraps [child], the routed content from `MaterialApp.builder`.
  const CruxRoutedContent({required this.child, super.key});

  /// The routed content: the builder's `child`. Null before the router has
  /// built, as the builder's `child` can be.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: child ?? const SizedBox.shrink(),
    );
  }
}
