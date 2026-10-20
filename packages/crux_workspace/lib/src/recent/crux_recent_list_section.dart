// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show showCruxErrorSnack, showCruxInfoSnack;
import 'package:crux_workspace/src/recent/crux_recent_list.dart';
import 'package:crux_workspace/src/recent/crux_recent_list_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// A welcome screen's Recent section, for `EmptyCanvasState`'s
/// `recentFilesSection` or `recentWorkspacesSection` slot.
///
/// The heading, then one [CruxRecentTile] per entry, most recent first, and
/// a Clear Recent button under them while the list is not empty. A row whose
/// file is gone is greyed and says so; it stays openable (opening it drops
/// it and reports why) and removable.
class CruxRecentListSection extends ConsumerWidget {
  /// Creates the section for [list].
  const CruxRecentListSection({
    required this.list,
    required this.strings,
    required this.onOpen,
    this.icon = Icons.insert_drive_file_outlined,
    this.missingIcon = Icons.do_not_disturb_on_outlined,
    this.reportFailure = true,
    super.key,
  });

  /// Whether a failed open is reported here; false when [onOpen] reports
  /// its own failure.
  final bool reportFailure;

  /// The list shown.
  final CruxRecentList list;

  /// Its words, usually `CruxRecentListStrings.of(context, kind)`.
  final CruxRecentListStrings strings;

  /// Opens an entry; returns whether it opened. Wire it to
  /// [openCruxRecentEntry] so a failed open drops the entry.
  final Future<bool> Function(String path) onOpen;

  /// The leading icon of a present entry.
  final IconData icon;

  /// The leading icon of a missing entry.
  final IconData missingIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(list.provider);
    final exists = ref.watch(list.existsProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            strings.heading,
            style: theme.textTheme.labelLarge?.copyWith(color: muted),
          ),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            strings.empty,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          )
        else ...[
          for (final path in entries)
            CruxRecentTile(
              key: ValueKey('cruxRecent:${list.name}:$path'),
              path: path,
              exists: exists(path),
              strings: strings,
              icon: icon,
              missingIcon: missingIcon,
              onOpen: () => unawaited(
                openCruxRecentEntry(
                  context,
                  ref,
                  list: list,
                  strings: strings,
                  path: path,
                  open: onOpen,
                  reportFailure: reportFailure,
                ),
              ),
              onRemove: () => ref.read(list.provider.notifier).remove(path),
            ),
          const SizedBox(height: 4),
          TextButton(
            key: ValueKey('cruxRecentClear:${list.name}'),
            onPressed: () => clearCruxRecentList(
              context,
              ref,
              list: list,
              strings: strings,
            ),
            child: Text(strings.clearCommand),
          ),
        ],
      ],
    );
  }
}

/// One Recent row: the file name, its full path under it, and a remove
/// button.
///
/// A missing entry is greyed, with "File not found" in place of the path's
/// line (the path stays in the row's tooltip), and keeps both actions. The
/// row is one Tab stop named by the file name and its second line; the
/// remove button is the next, named by its tooltip.
class CruxRecentTile extends StatelessWidget {
  /// Creates a row for [path].
  const CruxRecentTile({
    required this.path,
    required this.exists,
    required this.strings,
    required this.onOpen,
    required this.onRemove,
    this.icon = Icons.insert_drive_file_outlined,
    this.missingIcon = Icons.do_not_disturb_on_outlined,
    super.key,
  });

  /// The entry's absolute path.
  final String path;

  /// Whether the file is still on disk.
  final bool exists;

  /// The list's words.
  final CruxRecentListStrings strings;

  /// Opens the entry.
  final VoidCallback onOpen;

  /// Removes the entry from the list.
  final VoidCallback onRemove;

  /// The leading icon of a present entry.
  final IconData icon;

  /// The leading icon of a missing entry.
  final IconData missingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final name = p.basename(path).isEmpty ? path : p.basename(path);
    final second = exists ? path : strings.missing;
    final tile = ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(exists ? icon : missingIcon, color: exists ? null : muted),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: exists ? null : TextStyle(color: muted),
      ),
      subtitle: Text(
        second,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: muted),
      ),
      onTap: onOpen,
      trailing: IconButton(
        key: const ValueKey('cruxRecentRemove'),
        icon: const Icon(Icons.close, size: 16),
        tooltip: strings.removeTooltip,
        color: muted,
        visualDensity: VisualDensity.compact,
        onPressed: onRemove,
      ),
    );
    if (exists) return tile;
    return Tooltip(message: path, excludeFromSemantics: true, child: tile);
  }
}

/// Opens a Recent entry through [open] and, when it does not open, drops it
/// from [list] and reports it with an error toast naming the file.
///
/// The one path every Recent row, menu entry and palette entry opens
/// through, so a missing file never fails silently and never stays listed.
/// Returns what happened. An [open] that reports its own, more specific
/// failure passes [reportFailure] false so the user is not told twice.
Future<CruxRecentOpenResult> openCruxRecentEntry(
  BuildContext context,
  WidgetRef ref, {
  required CruxRecentList list,
  required CruxRecentListStrings strings,
  required String path,
  required Future<bool> Function(String path) open,
  bool reportFailure = true,
}) async {
  // Read before the await: the open usually replaces the welcome screen that
  // holds this context.
  final notifier = ref.read(list.provider.notifier);
  final result = await notifier.open(path, open);
  if (reportFailure &&
      result == CruxRecentOpenResult.removed &&
      context.mounted) {
    final name = p.basename(path).isEmpty ? path : p.basename(path);
    showCruxErrorSnack(context, strings.removedMissing(name));
  }
  return result;
}

/// The Clear Recent command: empties [list] and confirms with a toast (which
/// is also announced). Bind the palette entry, the File menu item and the
/// welcome screen's button to it.
void clearCruxRecentList(
  BuildContext context,
  WidgetRef ref, {
  required CruxRecentList list,
  required CruxRecentListStrings strings,
}) {
  ref.read(list.provider.notifier).clear();
  showCruxInfoSnack(context, strings.cleared);
}
