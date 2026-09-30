// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_theme/src/theme_pack.dart';
import 'package:crux_theme/src/theme_pack_service.dart';
import 'package:crux_theme/src/theme_pack_store.dart';

/// [ThemePackStore] backed by a directory on disk.
///
/// This is the production implementation on desktop and mobile. It is
/// deliberately kept in its own library so that `ThemePackBrowser` —
/// and therefore every consumer that only wants to *render* the
/// Appearance panel — does not transitively import `dart:io`, which
/// would make the widget unusable on web.
///
/// Writes go through [ThemePackService], which performs them
/// atomically (temp file, flush, rename).
class DirectoryThemePackStore implements ThemePackStore {
  /// Creates a store over [directory], created on demand by the
  /// service when a write needs it.
  const DirectoryThemePackStore({
    required this.directory,
    this.service = const ThemePackService(),
  });

  /// Directory where installed packs live. Typically
  /// `${appSupportDir}/themes/`.
  final Directory directory;

  /// Service performing the file-system operations.
  final ThemePackService service;

  @override
  Future<List<ThemePackHeader>> listPacks() => service.list(directory);

  @override
  Future<ThemePack> loadPack(String packId) =>
      service.load(service.fileFor(packId, directory));

  @override
  Future<ThemePack> installPack(String document) async {
    // Decode before touching the filesystem so an invalid id — a path
    // traversal payload, say — is rejected before any path is built.
    final parsed = service.codec.decode(document);
    final written = await service.save(parsed, directory);
    return parsed.copyWith(sourceUri: written.uri);
  }

  @override
  Future<bool> uninstallPack(String packId) =>
      service.uninstall(packId, directory);
}
