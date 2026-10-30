// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The longest [PeerIdentity.activeDocument] kept, in characters (CXP §8.1).
const int kCxpActiveDocumentMaxLength = 120;

/// Self-description a CXP peer announces during the handshake.
///
/// Every server start writes a manifest containing this identity, and
/// every Hello message embeds it so the peer on the other end of the
/// socket knows who it's talking to.
@immutable
class PeerIdentity {
  /// Creates a peer identity.
  ///
  /// [activeDocument] is display text; [withActiveDocument] and
  /// [PeerIdentity.fromJson]
  /// reduce a value to it with [normalizeActiveDocument], and [toJson]
  /// writes only the reduced form, so a directory never travels in it.
  const PeerIdentity({
    required this.peerId,
    required this.productName,
    required this.productVersion,
    this.capabilities = const <String>{},
    this.activeDocument,
  });

  /// Decodes a [PeerIdentity] from its JSON form. Throws [FormatException]
  /// on missing required fields.
  ///
  /// An `active_document` that is not a string, or is empty once reduced
  /// to display text, is read as absent.
  factory PeerIdentity.fromJson(Map<String, Object?> json) {
    final peerId = json['peer_id'];
    final productName = json['product_name'];
    final productVersion = json['product_version'];
    if (peerId is! String) {
      throw const FormatException('PeerIdentity.fromJson: missing "peer_id"');
    }
    if (productName is! String) {
      throw const FormatException(
        'PeerIdentity.fromJson: missing "product_name"',
      );
    }
    if (productVersion is! String) {
      throw const FormatException(
        'PeerIdentity.fromJson: missing "product_version"',
      );
    }
    final rawCaps = json['capabilities'];
    final capabilities = <String>{};
    if (rawCaps is List) {
      for (final entry in rawCaps) {
        if (entry is String) capabilities.add(entry);
      }
    }
    final rawDocument = json['active_document'];
    return PeerIdentity(
      peerId: peerId,
      productName: productName,
      productVersion: productVersion,
      capabilities: capabilities,
      activeDocument: rawDocument is String
          ? normalizeActiveDocument(rawDocument)
          : null,
    );
  }

  /// Reduces [raw] to what [activeDocument] may hold: its last path
  /// component (a directory never travels or shows), with control and
  /// bidirectional-override characters removed, trimmed, and cut to
  /// [kCxpActiveDocumentMaxLength] characters. Null when nothing is left.
  static String? normalizeActiveDocument(String? raw) {
    if (raw == null) return null;
    final segments = raw
        .split(RegExp(r'[/\\]'))
        .where((segment) => segment.trim().isNotEmpty);
    if (segments.isEmpty) return null;
    final cleaned = String.fromCharCodes(
      segments.last.runes.where((rune) => !_isHiddenControl(rune)),
    ).trim();
    if (cleaned.isEmpty) return null;
    final runes = cleaned.runes.toList(growable: false);
    if (runes.length <= kCxpActiveDocumentMaxLength) return cleaned;
    return String.fromCharCodes(
      runes.take(kCxpActiveDocumentMaxLength),
    ).trimRight();
  }

  static bool _isHiddenControl(int rune) =>
      rune < 0x20 ||
      (rune >= 0x7f && rune <= 0x9f) ||
      (rune >= 0x200b && rune <= 0x200f) ||
      (rune >= 0x202a && rune <= 0x202e) ||
      (rune >= 0x2066 && rune <= 0x2069) ||
      rune == 0xfeff;

  /// Globally unique identifier for this running peer process.
  ///
  /// Conventionally `<product>-<pid>-<startedAtMillis>` to give every peer a
  /// stable but readable ID.
  final String peerId;

  /// The product short name (`wavecrux`, a future Crux product's short name,
  /// or a third-party identifier).
  final String productName;

  /// The product's version string (semver).
  final String productVersion;

  /// Optional set of capability strings the peer advertises.
  ///
  /// Advisory strings (CXP §8.1): message kinds, product-namespaced strings
  /// (`wavecrux.signal_value`), and strings the specification registers
  /// under the reserved `cxp.` prefix, such as `cxp.accepts:<element kind>`
  /// for each element kind the peer's highlight handler honours.
  final Set<String> capabilities;

  /// The design this peer's active window has open, for display only: a
  /// file name or a design's display name, never a directory (CXP §8.1).
  ///
  /// Optional and ignorable. A receiver shows it as text beside the peer's
  /// name and never opens, resolves, matches or routes on it. It changes
  /// while the peer runs, so the current value is the one in the peer's
  /// manifest, not the copy its `hello` carried.
  final String? activeDocument;

  /// A copy with [activeDocument] replaced by [document] reduced to display
  /// text with [normalizeActiveDocument] (null, or nothing left, removes
  /// it).
  PeerIdentity withActiveDocument(String? document) => PeerIdentity(
    peerId: peerId,
    productName: productName,
    productVersion: productVersion,
    capabilities: capabilities,
    activeDocument: normalizeActiveDocument(document),
  );

  /// JSON encoding suitable for inclusion in a `Hello` or manifest.
  /// `active_document` is written reduced to display text, and only when
  /// something is left of it.
  Map<String, Object?> toJson() => <String, Object?>{
    'peer_id': peerId,
    'product_name': productName,
    'product_version': productVersion,
    'capabilities': capabilities.toList(growable: false),
    'active_document': ?normalizeActiveDocument(activeDocument),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerIdentity &&
          other.peerId == peerId &&
          other.productName == productName &&
          other.productVersion == productVersion &&
          other.activeDocument == activeDocument &&
          _setEquals(other.capabilities, capabilities));

  @override
  int get hashCode => Object.hash(
    peerId,
    productName,
    productVersion,
    Object.hashAllUnordered(capabilities),
    activeDocument,
  );

  @override
  String toString() =>
      'PeerIdentity($productName $productVersion, peerId=$peerId)';
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final v in a) {
    if (!b.contains(v)) return false;
  }
  return true;
}
