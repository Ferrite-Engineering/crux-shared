// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Derives the shared CXP `design_id` token for the design that owns
/// [fileOrDirPath] — the suite's derivation convention; CXP §9.10.1
/// (<https://edacrux.app/cxp#sec-9-10-1>) states what a `design_id` must be.
///
/// The `design_id` keys the shared-workspace manifest
/// (`CxpWorkspaceStore`, `workspace/<design_id>.json`) that lets a receiver
/// open the right artifact when it has none matching. **All four Crux apps
/// MUST use this one helper** — four re-implementations that diverge by a
/// single normalization detail would silently fail to join, because the
/// producer, sender, and consumer would key the same folder differently.
///
/// The identity is the **directory containing the design's files**, not any
/// single file: pointing at any file inside a design folder, or at the folder
/// itself, yields the same token. Each app passes its *primary design input*:
/// SimCrux the loaded `simcrux.yaml` (→ its dir), NetCrux the top
/// source/netlist file (→ its dir), WaveCrux the loaded waveform (→ its dir),
/// LintCrux the `project.lintcrux` dir.
///
/// Derivation:
/// 1. Normalize [fileOrDirPath] and strip any trailing separator.
/// 2. Resolve to the **containing directory** — the path itself when it is a
///    directory, otherwise its parent.
/// 3. Canonicalize that directory against the filesystem (resolving symlinks)
///    when it exists, else fall back to [p.canonicalize] so the function is
///    still total for a not-yet-created design.
/// 4. Return the first 16 hex characters of the `sha256` of the canonical
///    directory path.
///
/// The result is a **filesystem-safe token** (`[0-9a-f]{16}`), legal as the
/// `<design_id>.json` filename `CxpWorkspaceStore` writes, and byte-identical
/// across apps and processes for the same folder on the same machine.
String cxpDesignIdForPath(String fileOrDirPath) {
  final canonicalDir = _canonicalDesignDirectory(fileOrDirPath);
  final digest = sha256.convert(utf8.encode(canonicalDir));
  return digest.toString().substring(0, 16);
}

/// Resolves [input] to the canonical absolute path of the directory that
/// contains the design's files. Exposed package-privately so tests can assert
/// the pre-hash canonicalization independently of the digest.
String _canonicalDesignDirectory(String input) {
  // Strip a trailing separator first so `/foo/bar/` and `/foo/bar` agree, then
  // normalize `.`/`..` segments.
  final normalized = p.normalize(input);
  final String dir;
  if (FileSystemEntity.typeSync(normalized) == FileSystemEntityType.directory) {
    dir = normalized;
  } else {
    // A file (or a not-yet-existent path): the containing directory is the
    // parent.
    dir = p.dirname(normalized);
  }
  try {
    // Resolves symlinks and yields an absolute path with no trailing slash.
    return Directory(dir).resolveSymbolicLinksSync();
  } on FileSystemException {
    // Directory does not exist yet: canonicalize lexically (absolute +
    // normalized; on case-insensitive hosts also case-folded) so the token is
    // still deterministic for the same lexical folder.
    return p.canonicalize(dir);
  }
}
