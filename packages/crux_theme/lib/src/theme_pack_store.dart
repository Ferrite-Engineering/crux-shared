// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/theme_pack.dart';
import 'package:crux_theme/src/theme_pack_codec.dart';
import 'package:flutter/foundation.dart';

/// Storage seam for installed theme packs, expressed without `dart:io`.
///
/// `ThemePackBrowser` used to take a `Directory` and `Future<File?>`
/// picker callbacks directly, which meant a consumer had to construct a
/// `dart:io` `Directory` just to *render a widget* — impossible on web,
/// where three of the four suite products ship a `web/` target. It also
/// made the widget untestable without a real filesystem: every test had
/// to pump exactly one frame, because `pumpAndSettle` hangs on a
/// genuinely pending FS future.
///
/// The interface is deliberately document-shaped rather than
/// file-shaped: packs move in and out as decoded [ThemePack]s and raw
/// JSON strings, so an implementation may be a directory
/// (`DirectoryThemePackStore`), browser local storage, an in-memory
/// map, or a network service.
abstract class ThemePackStore {
  /// Enumerates the headers of every installed, well-formed pack.
  ///
  /// Malformed entries are skipped rather than surfaced: the typical UX
  /// is a list where one bad pack must not hide the rest.
  Future<List<ThemePackHeader>> listPacks();

  /// Loads the full token table for [packId].
  ///
  /// Throws [FormatException] if the stored document is malformed, and
  /// an implementation-specific exception if it is missing.
  Future<ThemePack> loadPack(String packId);

  /// Decodes [document] and installs it, keyed by the pack's own id.
  ///
  /// Throws [FormatException] if [document] is not a valid pack —
  /// including when its id is unusable (see
  /// `ThemePackCodec.isValidPackId`).
  Future<ThemePack> installPack(String document);

  /// Removes [packId]. Returns `true` when something was removed.
  Future<bool> uninstallPack(String packId);
}

/// Returns a theme-pack JSON document chosen by the user, or `null` if
/// the user cancelled.
///
/// The host product owns the picker (`file_picker` on desktop, a
/// share-sheet bridge on mobile, an `<input type="file">` on web) and
/// hands back the *contents*, so the widget never touches a file
/// handle.
typedef PickPackDocument = Future<String?> Function();

/// Writes [document] to a user-chosen destination and returns a
/// human-readable description of where it landed (a path, a filename, a
/// URL) for the confirmation message — or `null` if the user cancelled.
typedef SavePackDocument = Future<String?> Function(String document);

/// In-memory [ThemePackStore], for tests and for hosts with no
/// persistent storage.
///
/// Every operation completes on the microtask queue, so widget tests
/// can `pumpAndSettle` normally instead of asserting on pre-resolution
/// chrome.
@visibleForTesting
class InMemoryThemePackStore implements ThemePackStore {
  /// Creates a store optionally pre-seeded with [initialPacks].
  InMemoryThemePackStore({List<ThemePack> initialPacks = const []}) {
    for (final pack in initialPacks) {
      _packs[pack.id] = pack;
    }
  }

  final Map<String, ThemePack> _packs = <String, ThemePack>{};

  /// Set to make every operation fail, to exercise error paths.
  Exception? failWith;

  /// Documents passed to [installPack], in call order.
  final List<String> installedDocuments = <String>[];

  /// Pack ids passed to [uninstallPack], in call order.
  final List<String> uninstalledIds = <String>[];

  @override
  Future<List<ThemePackHeader>> listPacks() async {
    _maybeFail();
    return [for (final pack in _packs.values) pack.toHeader()];
  }

  @override
  Future<ThemePack> loadPack(String packId) async {
    _maybeFail();
    final pack = _packs[packId];
    if (pack == null) {
      throw FormatException('No installed theme pack with id "$packId".');
    }
    return pack;
  }

  @override
  Future<ThemePack> installPack(String document) async {
    _maybeFail();
    installedDocuments.add(document);
    // Decode with the real codec so tests exercise the same validation
    // (schema version, id safety, color syntax) production does.
    final pack = const ThemePackCodec().decode(document);
    _packs[pack.id] = pack;
    return pack;
  }

  @override
  Future<bool> uninstallPack(String packId) async {
    _maybeFail();
    uninstalledIds.add(packId);
    return _packs.remove(packId) != null;
  }

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) throw failure;
  }
}
