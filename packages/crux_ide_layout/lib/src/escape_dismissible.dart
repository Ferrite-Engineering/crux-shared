// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Makes a Dialog-hosted, Scaffold-bearing screen dismissible with the
/// Escape key.
///
/// A hosted Scaffold captures focus and prevents Escape from bubbling
/// up to Flutter's default route-pop binding, so a `Dialog(child:
/// SomeScaffoldScreen())` silently loses Escape-to-close. Wrapping the
/// screen in this widget intercepts Escape on the dialog's root focus
/// scope and pops via [NavigatorState.maybePop], regardless of which
/// child currently holds focus — the suite-standard fix for this
/// mismatch (first wired in SimCrux Pro's `showDesktopScreenDialog`).
class EscapeDismissible extends StatelessWidget {
  /// Creates the wrapper around the dialog-hosted [child].
  const EscapeDismissible({required this.child, super.key});

  /// The Scaffold-bearing screen the enclosing Dialog hosts.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
