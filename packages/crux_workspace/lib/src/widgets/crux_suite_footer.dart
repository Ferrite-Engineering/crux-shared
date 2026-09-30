// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The suite-membership line rendered at the foot of every product's
/// empty-canvas (welcome) screen — "A member of the EDACrux suite of
/// products — edacrux.app".
///
/// Four products ship four separately-installable applications, and a user who
/// arrived at one of them has no reason to know the other three exist. This
/// line is the cheapest surface that says so: it sits below the recents, out of
/// the way of the work, and costs one tap to follow.
///
/// **The whole line is the target, not just the domain.** A tappable
/// `TextSpan` inside a paragraph cannot take keyboard focus and has no
/// semantics node of its own, so a keyboard or screen-reader user could read
/// this line but never follow it. Wrapping the line in an [InkWell] makes it
/// one focusable node announced as a link, at the cost of a slightly larger
/// hit area than the underlined domain suggests — which is the side to err on.
///
/// **No URL, and no launcher, live here.** The package stays free of
/// `url_launcher` (it is depended on by headless and test hosts that have no
/// plugin registrant), and the destination is per-product: each app points at
/// its own landing path so the site's page-view beacon — which records the
/// path and deliberately drops the query string — can attribute the visit to
/// the app that sent it. The host supplies both the localized [label] and the
/// [onTap] that opens its own URL.
class CruxSuiteFooter extends StatelessWidget {
  /// Creates the suite-membership footer line.
  const CruxSuiteFooter({
    required this.label,
    required this.onTap,
    this.linkText = defaultLinkText,
    super.key,
  });

  /// The full localized sentence, which must contain [linkText] verbatim —
  /// e.g. "A member of the EDACrux suite of products — edacrux.app".
  ///
  /// The sentence is split around [linkText] rather than assembled from an ICU
  /// placeholder so a translator sees, and can reorder, the whole line. A
  /// translation that drops the literal still renders and is still tappable;
  /// it simply carries no underlined segment.
  final String label;

  /// Called when the line is tapped or activated from the keyboard. The host
  /// opens its own suite URL here.
  final VoidCallback onTap;

  /// The portion of [label] rendered as a link. Locale-independent: the domain
  /// is spelled the same in every translation.
  final String linkText;

  /// The bare suite domain, which is what every product's [label] ends with.
  static const String defaultLinkText = 'edacrux.app';

  /// Key carried by the tappable row, so a widget test can find and activate
  /// the line without depending on the localized sentence.
  static const Key rowKey = Key('empty_canvas_suite_footer');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
    );
    final linkStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: colorScheme.primary,
    );

    final index = label.indexOf(linkText);
    final spans = index < 0
        // A translation without the literal domain still renders, and is still
        // followable — it just has nothing to underline.
        ? <InlineSpan>[TextSpan(text: label, style: linkStyle)]
        : <InlineSpan>[
            if (index > 0) TextSpan(text: label.substring(0, index)),
            TextSpan(text: linkText, style: linkStyle),
            if (index + linkText.length < label.length)
              TextSpan(text: label.substring(index + linkText.length)),
          ];

    // The `Semantics` sits inside the `Align`, wrapping the row rather than the
    // full-width band it is centred in: a node whose rect is the whole body
    // would let a touch-explore tap anywhere on the welcome screen follow the
    // link.
    return Align(
      child: Semantics(
        link: true,
        child: InkWell(
          key: rowKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            // 10 px above and below a 12 px line clears 32 px of height. Not
            // the 48 px a standalone control would want: the line is prose at
            // the bottom of a scrolling page, and a 48 px band of empty ink
            // under the recents reads as a layout bug.
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text.rich(
              TextSpan(style: baseStyle, children: spans),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
