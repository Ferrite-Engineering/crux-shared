// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:crux_license/src/edu_notice.dart';
import 'package:crux_license/src/license_panel_providers.dart';
import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/widgets/edition_badge.dart';
import 'package:crux_license/src/widgets/license_badge_strings.dart';
import 'package:crux_license/src/widgets/license_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The status-bar statement that this copy runs on an educational licence:
/// the EDU chip, `Non-commercial use`, and the holder's address.
///
/// Renders `SizedBox.shrink()` unless `licenseStatusProvider` resolves to the
/// Educational tier, so it can be mounted unconditionally in the status bar's
/// trailing slot, before the panel chevron. Open core and the paid tiers
/// never see it.
///
/// The address is on screen on purpose. A self-issued educational licence is
/// read offline and holds no machine count, so a shared key would go
/// unnoticed; a key that puts its owner's address on every screen it runs on
/// is one people do not post.
class CruxEduStatusChip extends ConsumerWidget {
  /// Creates the chip.
  const CruxEduStatusChip({
    this.onTap,
    this.strings = const CruxEduNoticeStringsEn(),
    this.badgeStrings = const LicenseBadgeStringsEn(),
    this.textStyle,
    this.maxTextWidth = 320,
    super.key,
  });

  /// Called on a click, typically to open Settings → License. `null` leaves
  /// the chip informational.
  final VoidCallback? onTap;

  /// The label and tooltip.
  final CruxEduNoticeStrings strings;

  /// The EDU chip's label and screen-reader phrase.
  final LicenseBadgeStrings badgeStrings;

  /// The label's style. Defaults to the ambient text style, which inside a
  /// `CruxStatusBar` is the bar's.
  final TextStyle? textStyle;

  /// The widest the label may grow before it is ellipsized, so a long address
  /// never pushes the rest of the bar's trailing slot off screen.
  final double maxTextWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(licenseStatusProvider);
    if (!cruxIsEduLicense(status)) return const SizedBox.shrink();

    final email = status.grant?.email?.trim();
    final hasEmail = email != null && email.isNotEmpty;
    final expiry = status.grant?.expiry;
    final tooltip = strings.statusTooltip(
      email: hasEmail ? email : null,
      validUntil: expiry == null ? null : formatLicenseDate(expiry),
    );
    final label = hasEmail
        ? '${strings.statusLabel} · $email'
        : strings.statusLabel;

    Widget chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EditionBadge(tier: LicenseTier.edu, strings: badgeStrings),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxTextWidth),
          child: Text(
            label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.longestLine,
          ),
        ),
      ],
    );

    if (onTap != null) {
      chip = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: chip,
        ),
      );
    }

    return Semantics(
      label: tooltip,
      button: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(message: tooltip, child: chip),
      ),
    );
  }
}

/// Paint [mark] in the bottom-right corner of a raster export of [size],
/// small and quiet, on a translucent plate so it reads on any background.
///
/// For exports drawn through a `Canvas` (PNG snapshots, PDF pages rendered
/// from a picture). Pair with `cruxEduExportMark`, which returns `null` when
/// nothing should be painted. Exports produced as text (SVG, HTML) write the
/// same string their own way.
void paintCruxEduExportMark(
  ui.Canvas canvas,
  ui.Size size,
  String mark, {
  Color color = const Color(0xFF5F6368),
  Color plate = const Color(0xD9FFFFFF),
  double fontSize = 11,
  double margin = 6,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: mark,
      style: TextStyle(color: color, fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: (size.width - 4 * margin).clamp(0, double.infinity));
  final padH = fontSize * 0.5;
  final padV = fontSize * 0.25;
  final right = size.width - margin;
  final bottom = size.height - margin;
  final rect = Rect.fromLTRB(
    right - painter.width - 2 * padH,
    bottom - painter.height - 2 * padV,
    right,
    bottom,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(fontSize * 0.3)),
    Paint()..color = plate,
  );
  painter
    ..paint(canvas, Offset(rect.left + padH, rect.top + padV))
    ..dispose();
}
