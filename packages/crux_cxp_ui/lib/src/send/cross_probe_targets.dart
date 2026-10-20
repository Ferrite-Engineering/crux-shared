// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_product_binding.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_providers.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// The suite's products in the order every cross-probe list shows them.
const List<String> kCrossProbeSuiteOrder = <String>[
  'wavecrux',
  'netcrux',
  'lintcrux',
  'simcrux',
];

/// What a product sends a cross-probe about: the selection, named in every
/// element kind the product can express it in.
///
/// A violation row, for example, is both a design scope and a source line;
/// its [candidates] carry both, and the element-kind table picks the one the
/// target product can show. Most precise first.
@immutable
class CrossProbeSelection {
  /// Creates a selection.
  const CrossProbeSelection({
    required this.candidates,
    this.displayName,
    this.metadata = const <String, Object?>{},
    this.coordinate,
  });

  /// The selection in each kind the source can name it in.
  final List<ElementId> candidates;

  /// A human-readable name for the event log; the first candidate's path
  /// when null.
  final String? displayName;

  /// Product-local metadata forwarded with the request.
  final Map<String, Object?> metadata;

  /// A decoded-stream coordinate, when the selection is one.
  final CxpStreamCoordinate? coordinate;

  /// Whether there is anything to send.
  bool get isEmpty => candidates.isEmpty;
}

/// The element kinds each suite product shows when asked, in the order a
/// sender prefers them. The shared answer to "what do I send to WaveCrux?":
/// the first kind the selection has, and the target accepts, wins.
const Map<String, List<ElementKind>> kCrossProbeTargetKinds =
    <String, List<ElementKind>>{
      'wavecrux': <ElementKind>[
        ElementKind.signal,
        ElementKind.net,
        ElementKind.port,
        ElementKind.source,
        ElementKind.scope,
        ElementKind.instance,
        ElementKind.marker,
        ElementKind.test,
      ],
      'netcrux': <ElementKind>[
        ElementKind.net,
        ElementKind.port,
        ElementKind.instance,
        ElementKind.scope,
        ElementKind.signal,
        ElementKind.source,
      ],
      'lintcrux': <ElementKind>[
        ElementKind.rule,
        ElementKind.scope,
        ElementKind.source,
        ElementKind.instance,
        ElementKind.net,
        ElementKind.port,
        ElementKind.signal,
      ],
      'simcrux': <ElementKind>[
        ElementKind.test,
        ElementKind.source,
        ElementKind.scope,
        ElementKind.instance,
        ElementKind.signal,
      ],
    };

/// The kinds offered to a product outside the suite that advertises none.
const List<ElementKind> kCrossProbeFallbackKinds = <ElementKind>[
  ElementKind.scope,
  ElementKind.source,
  ElementKind.signal,
  ElementKind.net,
  ElementKind.instance,
  ElementKind.port,
];

/// The element to send [selection] to [target] as, or null when the target
/// can show none of the selection's kinds.
///
/// The order is the target product's row of [kCrossProbeTargetKinds]. When
/// the target advertises `cxp.accepts:<kind>` capabilities, only those kinds
/// are offered, in the same order (and any accepted kind the table does not
/// list comes after, in the selection's own order).
ElementId? crossProbeElementFor(
  CrossProbeSelection selection,
  PeerIdentity target,
) {
  final accepted = <String>{
    for (final capability in target.capabilities)
      if (capability.startsWith(kCxpAcceptsCapabilityPrefix))
        capability.substring(kCxpAcceptsCapabilityPrefix.length),
  };
  final preferred =
      kCrossProbeTargetKinds[target.productName.toLowerCase()] ??
      kCrossProbeFallbackKinds;
  bool allowed(ElementKind kind) =>
      accepted.isEmpty || accepted.contains(kind.name);
  for (final kind in preferred) {
    if (!allowed(kind)) continue;
    for (final candidate in selection.candidates) {
      if (candidate.kind == kind) return candidate;
    }
  }
  if (accepted.isEmpty) return null;
  for (final candidate in selection.candidates) {
    if (accepted.contains(candidate.kind.name)) return candidate;
  }
  return null;
}

/// One product a cross-probe can go to, with each of its running windows.
@immutable
class CrossProbeTarget {
  /// Creates a target.
  const CrossProbeTarget({
    required this.productName,
    required this.label,
    required this.instances,
  });

  /// The wire product name.
  final String productName;

  /// The display name: WaveCrux.
  final String label;

  /// Its running instances, oldest first. Never empty.
  final List<PeerIdentity> instances;

  /// Whether the product runs in more than one window, so the menu shows
  /// each as a sub-item.
  bool get hasSeveralInstances => instances.length > 1;
}

/// Groups [peers] into targets: one per product, the suite's four in
/// [kCrossProbeSuiteOrder], any other after them by name; instances oldest
/// first by the start time in their peer id.
List<CrossProbeTarget> crossProbeTargetsFor(List<PeerIdentity> peers) {
  final byProduct = <String, List<PeerIdentity>>{};
  for (final peer in peers) {
    byProduct.putIfAbsent(peer.productName.toLowerCase(), () => []).add(peer);
  }
  int rank(String product) {
    final index = kCrossProbeSuiteOrder.indexOf(product);
    return index < 0 ? kCrossProbeSuiteOrder.length : index;
  }

  final products = byProduct.keys.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return <CrossProbeTarget>[
    for (final product in products)
      CrossProbeTarget(
        productName: product,
        label: cxpProductDisplayName(product),
        instances: List<PeerIdentity>.unmodifiable(
          byProduct[product]!..sort(_byStartTime),
        ),
      ),
  ];
}

int _byStartTime(PeerIdentity a, PeerIdentity b) {
  final byTime = _startedAt(a.peerId).compareTo(_startedAt(b.peerId));
  return byTime != 0 ? byTime : a.peerId.compareTo(b.peerId);
}

/// The start time a `<product>-<pid>-<ms>` peer id carries; 0 otherwise.
int _startedAt(String peerId) {
  final dash = peerId.lastIndexOf('-');
  if (dash < 0) return 0;
  return int.tryParse(peerId.substring(dash + 1)) ?? 0;
}

/// The cross-probe targets for the connected peers. Empty when the server
/// is off or no peer runs.
final Provider<List<CrossProbeTarget>> crossProbeTargetsProvider =
    Provider<List<CrossProbeTarget>>(
      (ref) => crossProbeTargetsFor(ref.watch(cxpPeersProvider)),
      name: 'crossProbeTargetsProvider',
    );
