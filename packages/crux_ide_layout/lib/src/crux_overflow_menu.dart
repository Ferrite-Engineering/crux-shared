// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/src/crux_desktop_tokens.dart';
import 'package:crux_ide_layout/src/platform_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One line of a Crux menu: a [CruxMenuItem] or a [CruxMenuDivider].
sealed class CruxMenuEntry {
  const CruxMenuEntry();
}

/// A menu command.
@immutable
final class CruxMenuItem extends CruxMenuEntry {
  /// Creates a command.
  const CruxMenuItem({
    required this.label,
    required this.onSelected,
    this.icon,
    this.enabled = true,
    this.destructive = false,
    this.key,
  });

  /// The localized label.
  final String label;

  /// Runs after the menu has closed.
  final VoidCallback onSelected;

  /// An optional leading icon.
  final IconData? icon;

  /// Whether the command can be chosen; a disabled one is shown greyed.
  final bool enabled;

  /// Whether the command destroys something; it is drawn in the error
  /// colour.
  final bool destructive;

  /// A key for the rendered row, for tests.
  final Key? key;
}

/// A separator between groups of commands.
@immutable
final class CruxMenuDivider extends CruxMenuEntry {
  /// Creates a separator.
  const CruxMenuDivider();
}

/// Opens [entries] as a context menu at [globalPosition] and runs the chosen
/// command after the menu closes. Resolves when the menu has closed.
///
/// The one menu [CruxOverflowMenu] and [CruxContextMenuRegion] both open,
/// so the "⋯" button, a right-click, Shift+F10 and the Menu key offer the
/// same commands.
Future<void> showCruxContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<CruxMenuEntry> entries,
}) async {
  final overlay =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  if (overlay == null || entries.isEmpty) return;
  final local = overlay.globalToLocal(globalPosition);
  final position = RelativeRect.fromRect(
    Rect.fromPoints(local, local),
    Offset.zero & overlay.size,
  );
  await _openMenu(context, position, entries);
}

Future<void> _openMenu(
  BuildContext context,
  RelativeRect position,
  List<CruxMenuEntry> entries,
) async {
  final theme = Theme.of(context);
  final height = CruxDesktopTokens.of(context)?.controlHeight;
  final items = <PopupMenuEntry<int>>[];
  for (var i = 0; i < entries.length; i++) {
    switch (entries[i]) {
      case CruxMenuDivider():
        items.add(const PopupMenuDivider(height: 9));
      case final CruxMenuItem item:
        final color = item.destructive ? theme.colorScheme.error : null;
        items.add(
          PopupMenuItem<int>(
            key: item.key,
            value: i,
            enabled: item.enabled,
            height: height ?? kMinInteractiveDimension,
            child: Row(
              children: <Widget>[
                if (item.icon case final IconData icon) ...<Widget>[
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: color == null ? null : TextStyle(color: color),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
  final chosen = await showMenu<int>(
    context: context,
    position: position,
    items: items,
  );
  if (chosen == null) return;
  final entry = entries[chosen];
  if (entry is CruxMenuItem && entry.enabled) entry.onSelected();
}

/// The visible overflow button: a "⋯" ([Icons.more_horiz]) that opens
/// [entries] below itself.
///
/// The suite never shows a vertical "⋮": row and item actions are on
/// right-click first, and a visible overflow is this horizontal glyph. Pair
/// it with a [CruxContextMenuRegion] around the row or item it belongs to,
/// over the same [entries], so the pointer and the keyboard reach the same
/// commands:
///
/// ```dart
/// CruxContextMenuRegion(
///   entries: entries,
///   child: Row(children: [Expanded(child: label), CruxOverflowMenu(
///     entries: entries, tooltip: l10n.moreActions)]),
/// )
/// ```
class CruxOverflowMenu extends StatelessWidget {
  /// Creates the button.
  const CruxOverflowMenu({
    required this.entries,
    required this.tooltip,
    this.iconSize = 16,
    this.color,
    super.key,
  });

  /// The commands.
  final List<CruxMenuEntry> entries;

  /// The localized tooltip, also the button's accessible name.
  final String tooltip;

  /// The glyph size.
  final double iconSize;

  /// The glyph colour; null keeps the icon theme's.
  final Color? color;

  void _open(BuildContext context) {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    final position = button != null && overlay != null
        ? RelativeRect.fromRect(
            Rect.fromPoints(
              button.localToGlobal(
                button.size.bottomLeft(Offset.zero),
                ancestor: overlay,
              ),
              button.localToGlobal(
                button.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          )
        : RelativeRect.fill;
    unawaited(_openMenu(context, position, entries));
  }

  @override
  Widget build(BuildContext context) {
    final height = CruxDesktopTokens.of(context)?.controlHeight;
    return IconButton(
      key: const ValueKey('cruxOverflowMenuButton'),
      icon: Icon(Icons.more_horiz, size: iconSize, color: color),
      tooltip: tooltip,
      constraints: height == null
          ? null
          : BoxConstraints.tightFor(width: height, height: height),
      padding: EdgeInsets.zero,
      onPressed: entries.isEmpty ? null : () => _open(context),
    );
  }
}

/// Makes [child] open [entries] as a context menu on right-click (and
/// long-press on touch, through [PlatformContextMenu]), and on Shift+F10 or
/// the Menu key while focus is anywhere inside it.
///
/// A keyboard-opened menu appears at the bottom-left of the focused control.
class CruxContextMenuRegion extends StatelessWidget {
  /// Wraps [child].
  const CruxContextMenuRegion({
    required this.entries,
    required this.child,
    this.isTouchLayout = false,
    super.key,
  });

  /// The commands.
  final List<CruxMenuEntry> entries;

  /// The row or item the menu belongs to.
  final Widget child;

  /// Whether the host's layout is touch-first; see [PlatformContextMenu].
  final bool isTouchLayout;

  KeyEventResult _onKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent || entries.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shiftF10 =
        key == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
    if (!shiftF10 && key != LogicalKeyboardKey.contextMenu) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.rect;
    final box = context.findRenderObject() as RenderBox?;
    final anchor =
        focused?.bottomLeft ??
        (box == null ? Offset.zero : box.localToGlobal(Offset.zero));
    unawaited(
      showCruxContextMenu(
        context,
        globalPosition: anchor,
        entries: entries,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (_, event) => _onKey(context, event),
      child: PlatformContextMenu(
        isTouchLayout: isTouchLayout,
        onContextMenu: (position) => unawaited(
          showCruxContextMenu(
            context,
            globalPosition: position,
            entries: entries,
          ),
        ),
        child: child,
      ),
    );
  }
}
