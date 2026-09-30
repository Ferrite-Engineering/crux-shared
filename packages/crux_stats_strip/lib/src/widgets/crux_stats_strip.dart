// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/src/models/crux_stat_segment.dart';
import 'package:crux_stats_strip/src/widgets/crux_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height of the expanded strip in logical pixels.
const double kCruxStatsStripHeight = 96;

/// Height of the collapsed disclosure row.
const double kCruxStatsStripCollapsedHeight = 24;

/// Whether the live statistics strip is expanded.
///
/// Hosts persist this in their workspace document so the choice survives a
/// restart — a user who wants an ambient monitor wants it every session,
/// and one who does not should not have to collapse it daily.
class CruxStatsStripVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Whether the strip is expanded. Mirrors [state] so the setter below
  /// has a matching getter.
  bool get expanded => state;

  /// Expands or collapses the strip.
  set expanded(bool value) => state = value;

  /// Flips the current state.
  void toggle() => state = !state;
}

/// Expanded / collapsed state of the strip.
final NotifierProvider<CruxStatsStripVisibilityNotifier, bool>
cruxStatsStripExpandedProvider =
    NotifierProvider<CruxStatsStripVisibilityNotifier, bool>(
      CruxStatsStripVisibilityNotifier.new,
    );

/// Ambient real-time performance monitor that docks above the status bar.
///
/// The strip renders the [segments] the host supplies and nothing else — it
/// has no knowledge of waveforms, regressions or netlists. App-level
/// segments (memory, FPS) and product-specific ones (queue depth, layout
/// time) are the same type; the host decides the order.
///
/// **Collapsed by default.** An ambient monitor that appears uninvited
/// takes 96 px from the surface the user actually came for. The disclosure
/// row stays visible so the feature is discoverable.
///
/// The strip does not gate its own platform visibility — the host decides
/// whether to render it at all (desktop only, in every current product).
class CruxStatsStrip extends ConsumerWidget {
  /// Creates the strip.
  const CruxStatsStrip({
    required this.segments,
    required this.label,
    this.semanticLabel,
    this.expandTooltip,
    this.collapseTooltip,
    this.expanded,
    this.onToggle,
    super.key,
  });

  /// Readings to display, left to right.
  final List<CruxStatSegment> segments;

  /// Caption on the disclosure row, e.g. `Stats`.
  final String label;

  /// The disclosure control's accessible name, e.g. `Statistics`.
  ///
  /// The control is announced under this one name, as a button with an
  /// expanded or collapsed state. The visible caption and the tooltips are
  /// kept out of the accessibility tree: a screen reader otherwise reads all
  /// three in a row, and the state already says what the tooltip says.
  /// Null uses [label].
  final String? semanticLabel;

  /// Tooltip on the disclosure control when collapsed.
  final String? expandTooltip;

  /// Tooltip on the disclosure control when expanded.
  final String? collapseTooltip;

  /// Host-supplied disclosure state, overriding
  /// [cruxStatsStripExpandedProvider].
  ///
  /// The provider is the default because most hosts have nowhere better to
  /// keep the bit. A host that already persists it — WaveCrux stores the
  /// strip's disclosure per tab in its session sidecar, and drives it from a
  /// keyboard shortcut — passes its own value here with [onToggle], so the
  /// shared row and the host's state cannot disagree.
  ///
  /// Null (the default) reads the provider. Supply both or neither.
  final bool? expanded;

  /// Called when the disclosure row is tapped. Null toggles
  /// [cruxStatsStripExpandedProvider].
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A host-supplied value means the provider is not this strip's state and
    // must not be watched — an unread provider is one fewer place for the
    // two to drift.
    // The explicit type argument matters: `expanded` makes the context type
    // `bool?`, which inference would otherwise push into `watch`.
    final isExpanded =
        expanded ?? ref.watch<bool>(cruxStatsStripExpandedProvider);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DisclosureRow(
            label: label,
            semanticLabel: semanticLabel ?? label,
            expanded: isExpanded,
            tooltip: isExpanded ? collapseTooltip : expandTooltip,
            onToggle:
                onToggle ??
                () =>
                    ref.read(cruxStatsStripExpandedProvider.notifier).toggle(),
          ),
          if (isExpanded)
            SizedBox(
              height: kCruxStatsStripHeight,
              child: _SegmentRow(segments: segments),
            ),
        ],
      ),
    );
  }
}

class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({
    required this.label,
    required this.semanticLabel,
    required this.expanded,
    required this.onToggle,
    this.tooltip,
  });

  final String label;
  final String semanticLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One node: the button role, the expanded state and the name come from
    // the Semantics annotation; the InkWell contributes focus and tap. The
    // caption text is excluded so it is not appended to the name.
    final row = MergeSemantics(
      child: Semantics(
        button: true,
        expanded: expanded,
        label: semanticLabel,
        child: InkWell(
          onTap: onToggle,
          child: ExcludeSemantics(
            child: SizedBox(
              height: kCruxStatsStripCollapsedHeight,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 8),
                  Icon(
                    expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final message = tooltip;
    return message == null
        ? row
        : Tooltip(message: message, excludeFromSemantics: true, child: row);
  }
}

/// Horizontally scrollable so a product with many segments degrades by
/// scrolling rather than by overflowing — a RenderFlex overflow in an
/// ambient monitor would be a permanent yellow-and-black stripe across the
/// bottom of the app.
class _SegmentRow extends StatelessWidget {
  const _SegmentRow({required this.segments});

  final List<CruxStatSegment> segments;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final segment in segments) ...<Widget>[
            _SegmentCell(segment: segment),
            const SizedBox(width: 20),
          ],
        ],
      ),
    );
  }
}

class _SegmentCell extends StatelessWidget {
  const _SegmentCell({required this.segment});

  final CruxStatSegment segment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final valueColor = switch (segment.emphasis) {
      CruxStatEmphasis.normal => scheme.onSurface,
      CruxStatEmphasis.dimmed => scheme.onSurfaceVariant.withValues(alpha: 0.6),
      CruxStatEmphasis.warning => scheme.error,
    };

    final cell = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          segment.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (segment.leading != null) ...<Widget>[
              segment.leading!,
              const SizedBox(width: 4),
            ],
            Text(
              segment.value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ],
        ),
        if (segment.sparkline.length >= 2) ...<Widget>[
          const SizedBox(height: 4),
          CruxSparkline(
            values: segment.sparkline,
            height: 20,
            lineColor: segment.emphasis == CruxStatEmphasis.warning
                ? scheme.error
                : null,
            semanticLabel: '${segment.label} history',
          ),
        ],
      ],
    );

    final message = segment.tooltip;
    return message == null ? cell : Tooltip(message: message, child: cell);
  }
}
