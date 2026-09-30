// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The service is an async wrapper over dart:io and is meant to be called
// from app-level async code. The avoid_slow_async_io lint prefers the
// synchronous *Sync() counterparts; we deliberately stay on the async
// API so callers (theme picker UI, settings panel) never have to
// reach into a sync IO call from inside an event-loop frame.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_theme/src/theme_pack.dart';
import 'package:crux_theme/src/theme_pack_codec.dart';
import 'package:path/path.dart' as p;

/// File-system service for reading, writing, and managing
/// `.crux-theme.json` theme packs in a user theme directory.
///
/// The service is a thin layer over [ThemePackCodec]: callers pass a
/// destination [Directory] (typically `${appSupportDir}/themes/`) and
/// the service translates that to read/write operations on the
/// filename convention `<pack.id>.crux-theme.json`.
///
/// Failure modes:
/// - [load] / [list] / [install] surface IO errors as exceptions from
///   the underlying `dart:io` operations; format errors as
///   [FormatException] from the codec.
/// - [validate] catches both and returns a [ThemePackValidation] with
///   a human-readable error list, so callers can drive a non-throwing
///   "pre-flight" UI before activation.
class ThemePackService {
  /// Creates a service. The optional [codec] override is useful in
  /// tests; the default singleton-style instance works for production.
  const ThemePackService({ThemePackCodec? codec})
    : codec = codec ?? const ThemePackCodec();

  /// Codec used to encode and decode pack documents.
  final ThemePackCodec codec;

  /// Canonical extension for theme pack files on disk.
  static const String themePackExtension = '.crux-theme.json';

  /// Reads and decodes a theme pack from [file].
  ///
  /// Throws [FileSystemException] if the file does not exist and
  /// [FormatException] if its contents are not a valid theme pack.
  Future<ThemePack> load(File file) async {
    final source = await file.readAsString();
    return codec.decode(source, sourceUri: file.uri);
  }

  /// Synchronous counterpart to [load]. Useful when iterating a small
  /// known directory in tests.
  ThemePack loadSync(File file) {
    final source = file.readAsStringSync();
    return codec.decode(source, sourceUri: file.uri);
  }

  /// Writes [pack] to [destination], using the canonical filename
  /// `<pack.id>.crux-theme.json`. Creates the destination directory if
  /// it does not exist. Returns the [File] written.
  ///
  /// Overwrites any existing file at the same path. The caller is
  /// responsible for confirming the overwrite if applicable.
  Future<File> save(ThemePack pack, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    final file = File(p.join(destination.path, _fileNameFor(pack.id)));
    await _writeAtomically(file, codec.encode(pack));
    return file;
  }

  /// Enumerates the headers of every well-formed `.crux-theme.json`
  /// file in [directory], without loading the full token table.
  ///
  /// Malformed files are silently skipped — the typical UX is a
  /// preset grid where one bad file shouldn't block the rest. Use
  /// [validate] when caller-side error reporting is required.
  Future<List<ThemePackHeader>> list(Directory directory) async {
    if (!await directory.exists()) return const [];
    final headers = <ThemePackHeader>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith(themePackExtension)) continue;
      try {
        final source = await entity.readAsString();
        // Header-only decode: the list view renders id / display name /
        // brightness, so building (and allocating) the whole color
        // table for every installed pack was pure waste.
        headers.add(codec.decodeHeader(source, sourceUri: entity.uri));
      } on FormatException {
        // Skip malformed packs.
      } on FileSystemException {
        // Skip unreadable files.
      }
    }
    return headers;
  }

  /// Copies [source] into [destination] and parses the result.
  ///
  /// The destination file name follows the canonical convention based
  /// on the pack's id (not the source filename), so a user-supplied
  /// `themes/whatever.json` becomes `<id>.crux-theme.json` after
  /// install. Returns the freshly decoded pack with `sourceUri` set to
  /// the destination path.
  ///
  /// Throws [FormatException] if [source] is not a valid theme pack.
  /// Throws [FileSystemException] if [source] does not exist or
  /// [destination] cannot be created.
  Future<ThemePack> install(File source, Directory destination) async {
    final raw = await source.readAsString();
    final parsed = codec.decode(raw, sourceUri: source.uri);
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    final destFile = File(p.join(destination.path, _fileNameFor(parsed.id)));
    await _writeAtomically(destFile, codec.encode(parsed));
    return parsed.copyWith(sourceUri: destFile.uri);
  }

  /// Removes the pack with [packId] from [directory] if present.
  ///
  /// No-ops if the file does not exist. Returns `true` when a file was
  /// removed.
  Future<bool> uninstall(String packId, Directory directory) async {
    final file = File(p.join(directory.path, _fileNameFor(packId)));
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// Validates [source] as a theme pack without writing anything.
  ///
  /// Returns [ThemePackValidation.ok] on success and
  /// [ThemePackValidation.failed] with the parser's error message on
  /// failure. Useful as a pre-flight check before [install] when the
  /// caller wants to render errors inline rather than catch a thrown
  /// exception.
  Future<ThemePackValidation> validate(File source) async {
    try {
      final raw = await source.readAsString();
      final pack = codec.decode(raw, sourceUri: source.uri);
      return ThemePackValidation.ok(pack);
    } on FormatException catch (e) {
      return ThemePackValidation.failed([e.message]);
    } on FileSystemException catch (e) {
      return ThemePackValidation.failed([
        'Unable to read theme pack: ${e.message}',
      ]);
    }
  }

  /// Resolves the canonical file path the service would use to store
  /// the pack with [packId] in [directory]. Public so callers can
  /// surface destination paths in the UI before calling [save] or
  /// [install].
  File fileFor(String packId, Directory directory) =>
      File(p.join(directory.path, _fileNameFor(packId)));

  /// Writes [contents] to [file] atomically: the bytes go to a sibling
  /// temporary file which is flushed to disk and then renamed over the
  /// destination.
  ///
  /// Rename is atomic within a filesystem, so a crash or power loss
  /// leaves either the previous pack or the new one, never a truncated
  /// document. That matters more here than the "it's only a theme"
  /// framing suggests, because [list] *silently skips* unparseable
  /// files — a torn write would make the user's theme simply vanish
  /// from Settings with no error to explain it.
  ///
  /// Delegates to `crux_io`, the suite's single atomic-write helper: unique
  /// scratch name, `fsync` before the rename, scratch cleanup on failure.
  ///
  /// A theme pack is a **user-authored, shareable artifact** — someone spent
  /// real time on it and may be the only person who has it — so it takes the
  /// durable default without hesitation. Writes are also rare (install,
  /// export, save), so there is no throughput argument on the other side.
  Future<void> _writeAtomically(File file, String contents) =>
      writeStringAtomic(file, contents);

  /// Validates a pack id the same way [ThemePackCodec] does on decode.
  ///
  /// Defense in depth: [save] and [fileFor] accept ids from callers
  /// that did not come through the codec (e.g. an id derived from the
  /// active in-memory theme), and both interpolate into a path.
  String _fileNameFor(String packId) {
    if (!ThemePackCodec.isValidPackId(packId)) {
      throw ArgumentError.value(
        packId,
        'packId',
        'Theme pack id is not usable as a filename (path separator, "..", '
            'drive prefix, leading "." or "~", or control character).',
      );
    }
    return '$packId$themePackExtension';
  }
}
