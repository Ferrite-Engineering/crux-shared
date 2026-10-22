// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:meta/meta.dart';

/// Why [SingleInstanceLinkPolicy.check] refused a link.
enum SingleInstanceLinkRejection {
  /// Empty, or longer than [SingleInstanceLinkPolicy.maxLinkBytes] in UTF-8.
  badLength,

  /// White space or a control character: what arrives is one URL or nothing.
  forbiddenCharacter,

  /// Does not parse as an absolute URL.
  notAUrl,

  /// A URL, but not of a scheme the application declared.
  schemeNotDeclared,
}

final RegExp _schemePattern = RegExp(r'^[a-z][a-z0-9+.\-]*$');

/// What a running instance accepts from another process: exactly one
/// well-formed URL of a declared scheme, no longer than [maxLinkBytes].
///
/// The same policy runs on both sides. The launching process checks its link
/// before it connects, so a link the running instance would refuse is opened
/// (and reported) by the process that received it; the running instance
/// checks again, because what arrives on a socket is never trusted.
///
/// Passing the policy says nothing about what the link asks for. The
/// application still parses it strictly and decides what to do with it.
@immutable
class SingleInstanceLinkPolicy {
  /// Creates a policy accepting links of [schemes].
  ///
  /// Each scheme is lowercase RFC 3986 syntax without `:` or `//`, for example
  /// `example`. Throws [ArgumentError] when [schemes] is empty, when a scheme
  /// is malformed, or when [maxLinkBytes] is not positive.
  SingleInstanceLinkPolicy({
    required Iterable<String> schemes,
    this.maxLinkBytes = defaultMaxLinkBytes,
  }) : schemes = Set.unmodifiable(schemes) {
    if (this.schemes.isEmpty) {
      throw ArgumentError.value(schemes, 'schemes', 'declare at least one');
    }
    for (final scheme in this.schemes) {
      if (!_schemePattern.hasMatch(scheme)) {
        throw ArgumentError.value(
          scheme,
          'schemes',
          'a scheme is a lowercase letter followed by letters, digits, '
              '"+", "-" or "."',
        );
      }
    }
    if (maxLinkBytes <= 0) {
      throw ArgumentError.value(maxLinkBytes, 'maxLinkBytes', 'must be > 0');
    }
  }

  /// The default bound on a link, in UTF-8 bytes.
  static const int defaultMaxLinkBytes = 8192;

  /// The schemes accepted, lowercase.
  final Set<String> schemes;

  /// The longest link accepted, in UTF-8 bytes.
  final int maxLinkBytes;

  /// Null when [link] is acceptable; otherwise why it is not.
  SingleInstanceLinkRejection? check(String link) {
    if (link.isEmpty || utf8.encode(link).length > maxLinkBytes) {
      return SingleInstanceLinkRejection.badLength;
    }
    for (final rune in link.runes) {
      if (_isForbidden(rune)) {
        return SingleInstanceLinkRejection.forbiddenCharacter;
      }
    }
    final colon = link.indexOf(':');
    if (colon <= 0) return SingleInstanceLinkRejection.notAUrl;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme) {
      return SingleInstanceLinkRejection.notAUrl;
    }
    final scheme = link.substring(0, colon).toLowerCase();
    if (!schemes.contains(scheme) || uri.scheme.toLowerCase() != scheme) {
      return SingleInstanceLinkRejection.schemeNotDeclared;
    }
    return null;
  }

  /// Whether [link] passes [check].
  bool accepts(String link) => check(link) == null;

  static bool _isForbidden(int rune) {
    if (rune <= 0x20 || rune == 0x7F) return true;
    if (rune >= 0x80 && rune <= 0xA0) return true;
    if (rune == 0x1680 || rune == 0x3000 || rune == 0xFEFF) return true;
    if (rune >= 0x2000 && rune <= 0x200F) return true;
    if (rune >= 0x2028 && rune <= 0x202F) return true;
    if (rune >= 0x205F && rune <= 0x206F) return true;
    return false;
  }
}
