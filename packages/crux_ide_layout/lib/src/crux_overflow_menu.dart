// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/src/crux_desktop_tokens.dart';
import 'package:crux_ide_layout/src/platform_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One line of a Crux menu: a [CruxMenuItem], a [CruxSubmenu] or a
/// [CruxMenuDivider].
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
    this.tooltip,
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

  /// An optional hover explanation, typically why a disabled command cannot
  /// be chosen. Not part of the item's accessible name.
  final String? tooltip;

  /// A key for the rendered row, for tests.
  final Key? key;
}

/// A command that opens a second menu of [entries] beside the first, such
/// as "Cross-probe to" with one item per target.
///
/// Choosing it (click, Enter, or the Right arrow key) closes the menu it is
/// in and opens [entries] at its right edge, so the pair reads as a cascade
/// to the pointer and to the keyboard. With no [entries] it is disabled.
@immutable
final class CruxSubmenu extends CruxMenuEntry {
  /// Creates a submenu.
  const CruxSubmenu({
    required this.label,
    required this.entries,
    this.icon,
    this.enabled = true,
    this.tooltip,
    this.key,
  });

  /// The localized label. The submenu chevron is drawn, never written into
  /// the label.
  final String label;

  /// The second menu's commands.
  final List<CruxMenuEntry> entries;

  /// An optional leading icon.
  final IconData? icon;

  /// Whether the submenu can be opened; false or empty [entries] shows it
  /// greyed.
  final bool enabled;

  /// An optional hover explanation, typically why it is disabled.
  final String? tooltip;

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
  // Where each submenu row sat when it was chosen, so its menu opens beside
  // it after the parent has closed.
  final submenuRects = <int, Rect>{};
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
            child: _withTooltip(
              item.tooltip,
              _MenuRow(icon: item.icon, label: item.label, color: color),
            ),
          ),
        );
      case final CruxSubmenu submenu:
        final rowKey = GlobalKey();
        void record() {
          final box = rowKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          submenuRects[i] = box.localToGlobal(Offset.zero) & box.size;
        }

        items.add(
          _SubmenuItem(
            key: submenu.key,
            value: i,
            enabled: submenu.enabled && submenu.entries.isNotEmpty,
            height: height ?? kMinInteractiveDimension,
            onTap: record,
            child: _withTooltip(
              submenu.tooltip,
              _SubmenuRow(
                rowKey: rowKey,
                icon: submenu.icon,
                label: submenu.label,
              ),
            ),
          ),
        );
    }
  }
  // Looked up before the menu opens: a submenu opens against the same
  // overlay, and its state's context is not to be used across the await.
  final overlayBox =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox?;
  final chosen = await showMenu<int>(
    context: context,
    position: position,
    items: items,
  );
  if (chosen == null) return;
  final entry = entries[chosen];
  if (entry is CruxMenuItem) {
    if (entry.enabled) entry.onSelected();
    return;
  }
  if (entry is! CruxSubmenu || !entry.enabled || entry.entries.isEmpty) {
    return;
  }
  if (!context.mounted) return;
  final overlay = overlayBox;
  final rect = submenuRects[chosen];
  final next = overlay != null && rect != null
      ? RelativeRect.fromRect(
          Rect.fromPoints(
            overlay.globalToLocal(rect.topRight),
            overlay.globalToLocal(rect.topRight),
          ),
          Offset.zero & overlay.size,
        )
      : position;
  await _openMenu(context, next, entry.entries);
}

Widget _withTooltip(String? tooltip, Widget child) => tooltip == null
    ? child
    : Tooltip(message: tooltip, excludeFromSemantics: true, child: child);

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData? icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (icon case final IconData icon) ...<Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

/// A submenu's menu item: Right arrow opens it as Enter does. The key
/// handler sits above the item's own focus node, where a key event bubbles.
class _SubmenuItem extends PopupMenuItem<int> {
  const _SubmenuItem({
    required super.value,
    required super.child,
    super.enabled,
    super.height,
    super.onTap,
    super.key,
  });

  @override
  PopupMenuItemState<int, _SubmenuItem> createState() => _SubmenuItemState();
}

class _SubmenuItemState extends PopupMenuItemState<int, _SubmenuItem> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (_, event) {
        if (!widget.enabled ||
            event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.ignored;
        }
        handleTap();
        return KeyEventResult.handled;
      },
      child: super.build(context),
    );
  }
}

/// A submenu row: the label and a drawn chevron.
class _SubmenuRow extends StatelessWidget {
  const _SubmenuRow({
    required this.rowKey,
    required this.icon,
    required this.label,
  });

  final GlobalKey rowKey;
  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: rowKey,
      children: <Widget>[
        Expanded(
          child: _MenuRow(icon: icon, label: label),
        ),
        const SizedBox(width: 12),
        const ExcludeSemantics(child: Icon(Icons.chevron_right, size: 16)),
      ],
    );
  }
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
