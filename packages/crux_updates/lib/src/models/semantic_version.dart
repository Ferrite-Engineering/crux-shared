// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A parsed [Semantic Versioning 2.0.0](https://semver.org) version.
///
/// Package-internal: it backs `UpdateInfo.isNewerThan` and
/// `UpdateInfo.meetsMinSupported` and is deliberately **not** exported from the
/// `crux_updates` barrel. Products already carry their own version-string
/// helpers, and exporting a name this generic from a shared barrel would
/// collide with them on import.
///
/// Build metadata (`+abc`) is parsed but, per the spec, ignored for precedence.
/// Pre-release identifiers (`-beta.1`) participate in ordering: a pre-release
/// has *lower* precedence than the otherwise-equal release (`1.0.0-beta` is
/// older than `1.0.0`).
///
/// Construct from a string with [tryParse], which returns `null` on any
/// malformed input rather than throwing — the same fail-soft discipline the
/// `crux_license` `parseBetaExpiryDate` parser uses.
@immutable
final class SemanticVersion implements Comparable<SemanticVersion> {
  /// Creates a version from its already-parsed components.
  const SemanticVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const <String>[],
  });

  /// Parses a semver string such as `1.2.3`, `v1.2.3`, `1.2.3-beta.1`, or
  /// `1.2.3-rc.2+build.7`. Returns `null` when [input] is not a well-formed
  /// `major.minor.patch[-prerelease][+build]` string. A leading `v` is
  /// tolerated; build metadata is parsed away and ignored for ordering.
  static SemanticVersion? tryParse(String input) {
    final match = _pattern.firstMatch(input.trim());
    if (match == null) return null;

    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;

    final pre = match.group(4);
    final preRelease = (pre == null || pre.isEmpty)
        ? const <String>[]
        : pre.split('.');

    return SemanticVersion(major, minor, patch, preRelease: preRelease);
  }

  static final RegExp _pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  /// Major component — incremented for incompatible API changes.
  final int major;

  /// Minor component — incremented for backward-compatible additions.
  final int minor;

  /// Patch component — incremented for backward-compatible fixes.
  final int patch;

  /// Dot-separated pre-release identifiers (empty for a normal release).
  final List<String> preRelease;

  /// Whether this version carries any pre-release identifiers.
  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(SemanticVersion other) {
    final byCore = _cmpInt(major, other.major) != 0
        ? _cmpInt(major, other.major)
        : _cmpInt(minor, other.minor) != 0
        ? _cmpInt(minor, other.minor)
        : _cmpInt(patch, other.patch);
    if (byCore != 0) return byCore;

    // Equal core version: a release outranks any pre-release of it.
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1; // this is the full release
    if (other.preRelease.isEmpty) return -1; // other is the full release

    return _comparePreRelease(preRelease, other.preRelease);
  }

  static int _cmpInt(int a, int b) => a.compareTo(b);

  /// Compares two pre-release identifier lists per semver §11.4.
  static int _comparePreRelease(List<String> a, List<String> b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final cmp = _comparePreReleaseIdentifier(a[i], b[i]);
      if (cmp != 0) return cmp;
    }
    // All shared identifiers equal: the longer set has higher precedence.
    return _cmpInt(a.length, b.length);
  }

  static int _comparePreReleaseIdentifier(String a, String b) {
    final na = int.tryParse(a);
    final nb = int.tryParse(b);
    if (na != null && nb != null) return na.compareTo(nb);
    // Numeric identifiers always have lower precedence than alphanumeric.
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.compareTo(b);
  }

  /// Whether this version is strictly greater than [other].
  bool operator >(SemanticVersion other) => compareTo(other) > 0;

  /// Whether this version is strictly less than [other].
  bool operator <(SemanticVersion other) => compareTo(other) < 0;

  /// Whether this version is greater than or equal to [other].
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;

  /// Whether this version is less than or equal to [other].
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemanticVersion &&
          runtimeType == other.runtimeType &&
          compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease.join('.'));

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return preRelease.isEmpty ? core : '$core-${preRelease.join('.')}';
  }
}
