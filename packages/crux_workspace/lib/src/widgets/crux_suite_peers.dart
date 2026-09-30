// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The four products of the EDACrux suite, as a welcome screen presents them.
///
/// Deliberately **not** `crux_license`'s `CruxProduct`, which is the licensing
/// identity — an entitlement code and the products a key unlocks. A welcome
/// screen needs a brand colour and a landing-path slug and must not drag a
/// licensing dependency into `crux_workspace` to get a display name. The two
/// enumerations are held to the same four names, in the same order, by
/// `test/widgets/crux_suite_peers_test.dart`, which takes `crux_license` as a
/// dev dependency so production code does not have to.
enum CruxSuiteProduct {
  /// WaveCrux — the waveform viewer.
  waveCrux('WaveCrux', 'wavecrux', Color(0xFF2EE89C)),

  /// NetCrux — the schematic and connectivity explorer.
  netCrux('NetCrux', 'netcrux', Color(0xFFFFB454)),

  /// LintCrux — the RTL lint front end.
  lintCrux('LintCrux', 'lintcrux', Color(0xFF4DA3FF)),

  /// SimCrux — the simulation runner.
  simCrux('SimCrux', 'simcrux', Color(0xFFA78BFA));

  const CruxSuiteProduct(this.displayName, this.slug, this.brandColor);

  /// Product name as written in prose and UI, e.g. `WaveCrux`.
  final String displayName;

  /// Lower-case identifier used in URLs and landing paths, e.g. `wavecrux`.
  final String slug;

  /// The product's brand accent, matching the marketing sites' `--color-*`
  /// tokens. Used only as a small identifying dot: it is not run through the
  /// theme, and nothing is rendered *on* it, so it carries no contrast
  /// requirement of its own.
  final Color brandColor;

  /// The other three products, in declaration order.
  Iterable<CruxSuiteProduct> get peers =>
      CruxSuiteProduct.values.where((p) => p != this);
}

/// One peer row: which product, and what it does for the user of the product
/// they are looking at right now.
@immutable
class CruxSuitePeerEntry {
  /// Creates a peer row.
  const CruxSuitePeerEntry({required this.product, required this.blurb});

  /// The peer being offered.
  final CruxSuiteProduct product;

  /// One localized line, written from the *host* product's point of view.
  ///
  /// What NetCrux does for a WaveCrux user is not what it does for a SimCrux
  /// user, so these are not interchangeable and do not belong in this package:
  /// each product supplies its own three.
  final String blurb;
}

/// The "More from EDACrux" section for the foot of a welcome screen.
///
/// The suite-membership line (`CruxSuiteFooter`) says a suite exists. This says
/// what is in it, in the only terms that move anyone: what each other tool does
/// for the user of this one. A user who has never heard of the other three has
/// no reason to care that they are "a suite", and every reason to care that
/// something can lint the RTL whose waveform they are staring at.
///
/// Rows are rendered in the package; the words are not. The host passes
/// [entries] built from its own localizations, and one [onOpenPeer] callback —
/// the package holds no URL and no `url_launcher`, for the same reasons
/// `CruxSuiteFooter` does not.
///
/// **Each row is one focusable link**, not a tappable paragraph: a row a
/// keyboard user can read but not follow is a row that does not exist for them.
class CruxSuitePeers extends StatelessWidget {
  /// Creates the peers section.
  const CruxSuitePeers({
    required this.heading,
    required this.entries,
    required this.onOpenPeer,
    super.key,
  });

  /// Localized section heading, e.g. "MORE FROM EDACRUX".
  final String heading;

  /// The peer rows, in the order they should appear.
  final List<CruxSuitePeerEntry> entries;

  /// Called with the tapped row's product. The host opens its own URL.
  final void Function(CruxSuiteProduct product) onOpenPeer;

  /// Key prefix for a row, so a widget test can find one without depending on
  /// the localized blurb: `Key('empty_canvas_peer_netcrux')`.
  static Key rowKeyFor(CruxSuiteProduct product) =>
      Key('empty_canvas_peer_${product.slug}');

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            heading,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final entry in entries)
          _PeerRow(entry: entry, onTap: () => onOpenPeer(entry.product)),
      ],
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.entry, required this.onTap});

  final CruxSuitePeerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      link: true,
      child: InkWell(
        key: CruxSuitePeers.rowKeyFor(entry.product),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The brand dot, not the product's app icon: four icons at the
              // foot of a welcome screen read as a second toolbar, and the
              // icons are not assets this package can reach anyway.
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: entry.product.brandColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.product.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.blurb,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
