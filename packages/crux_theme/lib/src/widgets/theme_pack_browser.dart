// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/providers.dart';
import 'package:crux_theme/src/theme_pack.dart';
import 'package:crux_theme/src/theme_pack_codec.dart';
import 'package:crux_theme/src/theme_pack_store.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists installed theme packs and lets the user import, export, and
/// uninstall them.
///
/// Storage is supplied by the caller as a [ThemePackStore] — use
/// `DirectoryThemePackStore` on desktop/mobile. The widget itself never
/// imports `dart:io`, so it renders on web, and a test can drive every
/// state through an in-memory store instead of a real filesystem.
///
/// File-picking is likewise caller-supplied, via [pickPackDocument] and
/// [savePackDocument], so `crux_theme` stays `flutter_riverpod`-only.
/// Both exchange document *text* rather than file handles.
///
/// Pack list refreshes automatically after install and uninstall; the
/// active theme is read from [cruxColorThemeProvider] so that
/// activation flows through the same notifier the rest of the
/// Appearance section uses.
class ThemePackBrowser extends ConsumerStatefulWidget {
  /// Creates a theme pack browser.
  const ThemePackBrowser({
    required this.store,
    required this.pickPackDocument,
    required this.savePackDocument,
    this.strings = const ThemeAppearanceStringsEn(),
    super.key,
  });

  /// Storage backing the installed-pack list.
  final ThemePackStore store;

  /// Caller-supplied picker used by the "Import…" action. Returns the
  /// picked document's contents, or `null` on cancel.
  final PickPackDocument pickPackDocument;

  /// Caller-supplied exporter used by the "Export…" action. Returns a
  /// display string for where the document landed, or `null` on cancel.
  final SavePackDocument savePackDocument;

  /// Localized strings.
  final ThemeAppearanceStrings strings;

  @override
  ConsumerState<ThemePackBrowser> createState() => _ThemePackBrowserState();
}

class _ThemePackBrowserState extends ConsumerState<ThemePackBrowser> {
  late Future<List<ThemePackHeader>> _headersFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _headersFuture = widget.store.listPacks();
    });
  }

  Future<void> _onImport() async {
    final document = await widget.pickPackDocument();
    if (document == null) return;
    try {
      final installed = await widget.store.installPack(document);
      if (!mounted) return;
      _refresh();
      _showSnack(widget.strings.importSucceededMessage(installed.id));
    } on FormatException catch (e) {
      _showSnack(widget.strings.importFailedMessage(e.message));
    } on Exception catch (e) {
      // Storage-layer failures (IO, permissions, quota) are
      // implementation-specific by design — the store abstraction
      // deliberately does not name dart:io types.
      _showSnack(widget.strings.importFailedMessage('$e'));
    }
  }

  Future<void> _onExport() async {
    try {
      final activeTheme = ref.read(cruxColorThemeProvider);
      final pack = ThemePack(
        id: activeTheme.id,
        displayName: activeTheme.displayName,
        brightness: activeTheme.brightness,
        tokens: activeTheme.tokens,
      );
      final document = const ThemePackCodec().encode(pack);
      final where = await widget.savePackDocument(document);
      if (where == null) return;
      _showSnack(widget.strings.exportSucceededMessage(where));
    } on Exception catch (e) {
      _showSnack(widget.strings.exportFailedMessage('$e'));
    }
  }

  Future<void> _onActivate(ThemePackHeader header) async {
    try {
      final pack = await widget.store.loadPack(header.id);
      if (!mounted) return;
      ref.read(cruxColorThemeProvider.notifier).activate(pack.toTheme());
    } on FormatException catch (e) {
      _showSnack(widget.strings.importFailedMessage(e.message));
    } on Exception catch (e) {
      _showSnack(widget.strings.importFailedMessage('$e'));
    }
  }

  Future<void> _onUninstall(ThemePackHeader header) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.strings.confirmUninstallDialogTitle),
        content: Text(
          widget.strings.confirmUninstallDialogBody(header.id),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(widget.strings.confirmUninstallCancelLabel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(widget.strings.confirmUninstallConfirmLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.uninstallPack(header.id);
    } on Exception catch (e) {
      _showSnack(widget.strings.importFailedMessage('$e'));
      return;
    }
    if (!mounted) return;
    _refresh();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wrap rather than Row so the two action buttons fall onto a second
        // line instead of overflowing when the host lays this out in a
        // narrow column (compact Settings panels, mobile, the desktop
        // Settings dialog's grouped cards).
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _onImport,
              icon: const Icon(Icons.file_open),
              label: Text(widget.strings.importThemePackButtonLabel),
            ),
            OutlinedButton.icon(
              onPressed: _onExport,
              icon: const Icon(Icons.save_alt),
              label: Text(widget.strings.exportCurrentThemeButtonLabel),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.strings.installedPacksHeading,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        FutureBuilder<List<ThemePackHeader>>(
          future: _headersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final headers = snapshot.data ?? const <ThemePackHeader>[];
            if (headers.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  widget.strings.noInstalledPacksMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return Column(
              children: [
                for (final header in headers)
                  _InstalledPackRow(
                    header: header,
                    strings: widget.strings,
                    onActivate: () => _onActivate(header),
                    onUninstall: () => _onUninstall(header),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InstalledPackRow extends StatelessWidget {
  const _InstalledPackRow({
    required this.header,
    required this.strings,
    required this.onActivate,
    required this.onUninstall,
  });

  final ThemePackHeader header;
  final ThemeAppearanceStrings strings;
  final VoidCallback onActivate;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final isDark = header.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Tooltip(
            message: strings.brightnessLabel(isDark: isDark),
            child: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header.displayName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  header.id,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onActivate,
            child: Text(strings.activatePackButtonLabel),
          ),
          TextButton(
            onPressed: onUninstall,
            child: Text(strings.uninstallPackButtonLabel),
          ),
        ],
      ),
    );
  }
}
