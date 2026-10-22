// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A LibreLane release number, as `resolved.json` records it in
/// `meta.librelane_version` (`3.0.16`).
///
/// Only the numeric `major.minor.patch` head is compared; anything after it
/// (`3.0.17.dev4`, `3.1.0rc1`) is kept in [raw] and makes the version a
/// pre-release of, or a build beside, that number.
@immutable
class LibreLaneVersion implements Comparable<LibreLaneVersion> {
  /// Creates a version.
  const LibreLaneVersion(this.major, this.minor, this.patch, {String? raw})
    : raw = raw ?? '$major.$minor.$patch';

  /// The version [text] names, or null when it does not start with
  /// `major.minor.patch` (or `major.minor`, read as patch 0).
  static LibreLaneVersion? tryParse(String? text) {
    if (text == null || text.isEmpty || text.length > 64) return null;
    final match = _head.firstMatch(text.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = match.group(3) == null ? 0 : int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return LibreLaneVersion(major, minor, patch, raw: text.trim());
  }

  static final RegExp _head = RegExp(
    r'^v?(\d{1,4})\.(\d{1,4})(?:\.(\d{1,6}))?',
  );

  /// The major number.
  final int major;

  /// The minor number.
  final int minor;

  /// The patch number.
  final int patch;

  /// The text the version was read from.
  final String raw;

  /// The minor line, `major.minor`.
  String get line => '$major.$minor';

  /// Whether [raw] is exactly `major.minor.patch`, with nothing after it.
  bool get isRelease => raw == '$major.$minor.$patch';

  @override
  int compareTo(LibreLaneVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is LibreLaneVersion && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => raw;
}
