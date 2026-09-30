// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Self-description a CXP peer announces during the handshake.
///
/// Every server start writes a manifest containing this identity, and
/// every Hello message embeds it so the peer on the other end of the
/// socket knows who it's talking to.
@immutable
class PeerIdentity {
  /// Creates a peer identity.
  const PeerIdentity({
    required this.peerId,
    required this.productName,
    required this.productVersion,
    this.capabilities = const <String>{},
  });

  /// Decodes a [PeerIdentity] from its JSON form. Throws [FormatException]
  /// on missing required fields.
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
    return PeerIdentity(
      peerId: peerId,
      productName: productName,
      productVersion: productVersion,
      capabilities: capabilities,
    );
  }

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
  /// Capability strings let peers gate optional protocol extensions. The v1
  /// protocol defines no required capabilities; peers MAY advertise their
  /// own strings (typically namespaced, e.g. `wavecrux.signal_value`).
  final Set<String> capabilities;

  /// JSON encoding suitable for inclusion in a `Hello` or manifest.
  Map<String, Object?> toJson() => <String, Object?>{
    'peer_id': peerId,
    'product_name': productName,
    'product_version': productVersion,
    'capabilities': capabilities.toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerIdentity &&
          other.peerId == peerId &&
          other.productName == productName &&
          other.productVersion == productVersion &&
          _setEquals(other.capabilities, capabilities));

  @override
  int get hashCode => Object.hash(
    peerId,
    productName,
    productVersion,
    Object.hashAllUnordered(capabilities),
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
