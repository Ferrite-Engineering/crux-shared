// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The suite-standard empty state for a dock panel (or any panel-like
/// region) with nothing to show yet.
///
/// Canonical form (WaveCrux transaction table): centered, 24 px padding,
/// `bodyMedium` text in `onSurfaceVariant`. Hosts may add an [icon] above
/// the message and/or an [action] below it (e.g. an outlined "Open …"
/// button) — both are optional so the plain-text form stays the default.
///
/// The [message] is caller-supplied and already localized.
class CruxPanelEmptyState extends StatelessWidget {
  /// Creates a panel empty state.
  const CruxPanelEmptyState({
    required this.message,
    this.icon,
    this.action,
    super.key,
  });

  /// The localized explanation of why the panel is empty (and, ideally,
  /// what the user can do about it).
  final String message;

  /// Optional icon rendered above the message.
  final IconData? icon;

  /// Optional call-to-action rendered below the message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 32, color: mutedColor.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: mutedColor),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );

    // Centre when the region is tall enough, scroll when it is not.
    //
    // This stack has a fixed natural height (icon + message + action + 48 px of
    // padding) but lives in a region the user can drag arbitrarily short — a
    // dock dragged up, a pane collapsed toward its floor. A bare `Center` would
    // overflow and, because `Column` clips from the bottom, the first thing to
    // disappear is [action]: the one part the user needs to click. WaveCrux hit
    // exactly that (integration run 30591309796: `RenderFlex overflowed by 11
    // pixels` in a 53 px dock region), and in release builds there is no
    // debug stripe to notice — the call to action is simply gone.
    //
    // The scroll view keeps everything reachable at any height without a
    // magic-number breakpoint. `minHeight` makes it inert at normal sizes:
    // content exactly fills the viewport, so there is nothing to scroll.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return Center(child: content);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
