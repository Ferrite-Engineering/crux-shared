// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart'
    show formatShortcutLabel;
import 'package:crux_toolbar/src/toolbar_metrics.dart';
import 'package:flutter/material.dart';

/// One labelled block of actions in a [CruxToolbarOverflowMenu].
///
/// Deliberately not typed to `ActionCategory`: the overflow menu is a
/// presentation, and keeping it to a plain label + list lets a product group
/// however it likes without this package depending on the action taxonomy.
@immutable
class CruxOverflowGroup<A extends Object> {
  /// Creates a labelled group.
  const CruxOverflowGroup({required this.label, required this.actions});

  /// The group heading, e.g. the localized category name.
  final String label;

  /// The actions in this group, in display order.
  final List<A> actions;
}

/// How the overflow list is presented.
enum CruxOverflowPresentation {
  /// A popup anchored to the button — the desktop and tablet affordance.
  menu,

  /// A modal bottom sheet with a drag handle — the phone affordance, where a
  /// popup anchored near the top edge would be unreachable one-handed.
  sheet,
}

/// The trailing overflow affordance for a `CruxToolbar`.
///
/// A three-dot button that opens the product's full action list, grouped and
/// labelled. It is the answer to "the strip is too narrow to show everything":
/// three of the four products previously had no such answer at all, so their
/// trailing buttons simply disappeared on a narrow window.
///
/// On mobile it doubles as the menu bar, which Flutter does not bridge to iOS
/// or Android.
class CruxToolbarOverflowMenu<A extends Object> extends StatelessWidget {
  /// Creates an overflow menu.
  const CruxToolbarOverflowMenu({
    required this.groups,
    required this.labelOf,
    required this.isEnabled,
    required this.shortcutOf,
    required this.onAction,
    required this.tooltip,
    this.metrics = CruxToolbarMetrics.desktop,
    this.presentation = CruxOverflowPresentation.menu,
    this.trailingBuilder,
    super.key,
  });

  /// The action list, already grouped and filtered by the product's
  /// descriptor table. Empty groups are skipped.
  final List<CruxOverflowGroup<A>> groups;

  /// Localized label for an action.
  final String Function(A) labelOf;

  /// Whether an action is currently invocable. Disabled rows render greyed
  /// and do not dispatch.
  final bool Function(A) isEnabled;

  /// The user's current binding, rendered as a trailing accelerator.
  final ShortcutActivator? Function(A) shortcutOf;

  /// Invoked after the menu or sheet closes.
  final void Function(A) onAction;

  /// Tooltip for the three-dot button.
  final String tooltip;

  /// Geometry tokens, so the button matches the rest of the strip.
  final CruxToolbarMetrics metrics;

  /// Which presentation to use.
  final CruxOverflowPresentation presentation;

  /// Optional trailing widget per action — products use it for tier badges.
  final Widget? Function(A)? trailingBuilder;

  List<CruxOverflowGroup<A>> get _nonEmpty =>
      groups.where((g) => g.actions.isNotEmpty).toList();

  Future<void> _open(BuildContext context) async {
    // The presentation is chosen before the await; `context` is not used
    // afterwards, so there is no across-gap use to guard.
    final future = switch (presentation) {
      CruxOverflowPresentation.sheet => _openSheet(context),
      CruxOverflowPresentation.menu => _openMenu(context),
    };
    final selected = await future;
    if (selected != null) onAction(selected);
  }

  Future<A?> _openMenu(BuildContext context) {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = button != null && overlay != null
        ? RelativeRect.fromRect(
            Rect.fromPoints(
              button.localToGlobal(Offset.zero, ancestor: overlay),
              button.localToGlobal(
                button.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          )
        : RelativeRect.fill;

    return showMenu<A>(
      context: context,
      position: position,
      items: [
        for (final group in _nonEmpty) ...[
          PopupMenuItem<A>(
            enabled: false,
            height: 32,
            child: _GroupHeading(label: group.label),
          ),
          for (final action in group.actions)
            PopupMenuItem<A>(
              value: action,
              enabled: isEnabled(action),
              child: _Row(
                label: labelOf(action),
                shortcut: formatShortcutLabel(shortcutOf(action)),
                trailing: trailingBuilder?.call(action),
              ),
            ),
        ],
      ],
    );
  }

  Future<A?> _openSheet(BuildContext context) => showModalBottomSheet<A>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final group in _nonEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _GroupHeading(label: group.label),
            ),
            for (final action in group.actions)
              ListTile(
                key: ValueKey<A>(action),
                dense: true,
                enabled: isEnabled(action),
                title: _Row(
                  label: labelOf(action),
                  shortcut: formatShortcutLabel(shortcutOf(action)),
                  trailing: trailingBuilder?.call(action),
                ),
                onTap: () => Navigator.of(sheetContext).pop(action),
              ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: metrics.buttonSize,
    height: metrics.buttonSize,
    child: IconButton(
      icon: Icon(Icons.more_vert, size: metrics.iconSize),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: _nonEmpty.isEmpty ? null : () => _open(context),
    ),
  );
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.shortcut, this.trailing});

  final String label;
  final String shortcut;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (trailing case final Widget badge) ...[
          const SizedBox(width: 8),
          badge,
        ],
        if (shortcut.isNotEmpty) ...[
          const SizedBox(width: 12),
          Text(
            shortcut,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}
