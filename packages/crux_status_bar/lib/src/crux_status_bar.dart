// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';

/// Default desktop height of a [CruxStatusBar], in logical pixels.
///
/// Matches WaveCrux's canonical desktop status-bar height. Hosts that scale
/// their chrome for touch (e.g. WaveCrux's `MobileMetrics`) pass their own
/// [CruxStatusBar.height].
const double kCruxStatusBarHeight = 24;

/// Default monospace font size for status-bar text, in logical pixels.
///
/// Matches WaveCrux's canonical desktop status-bar typography.
const double kCruxStatusBarFontSize = 11;

/// Shared bottom-of-window **status bar** for the EDACrux suite.
///
/// Every product (WaveCrux, NetCrux, LintCrux, SimCrux) mounts this at the
/// window bottom so the suite's bottom chrome is consistent: one fixed height,
/// one background/border treatment, one typography baseline, all theme-aware
/// (light/dark) via the ambient [Theme]. WaveCrux is the canonical reference
/// for the look.
///
/// The bar never hard-codes per-app content. Instead the host contributes
/// widgets into ordered slots, laid out left → right:
///
/// ```text
/// [ …leading ] [ segments joined by | (scrolls) ][ …segmentsTrailing ]
///                              … flex … [ center ] … flex …
///                                            [ …trailing ]
/// ```
///
/// - [leading] — flush-left widgets before the segment strip (no dividers).
///   Typically a file/context affordance or a panel chevron.
/// - [segments] — metric segments joined by a `|` divider, wrapped in a
///   horizontally scrollable, left-aligned [Flexible] region so a long set
///   never pushes the trailing slot off-screen. Use [CruxStatusSegment] for
///   plain text, or pass any widget.
/// - [segmentsTrailing] — fixed widgets immediately after the scrolling strip,
///   still in the left group (e.g. a statistics toggle that must not scroll).
/// - [center] — an optional widget pinned to the geometric center of the bar
///   (placed between two equal-flex gaps, as WaveCrux centers its bottom-panel
///   chevron). When null the left group simply expands to push [trailing] to
///   the right edge.
/// - [trailing] — right-pinned widgets: app metrics, a load indicator, and the
///   open-core/Pro extension slot generalized from WaveCrux's
///   `statusBarTrailingWidgetsProvider` — the host reads its provider and
///   passes the resulting widgets here.
///
/// The bar clamps text scaling to [maxTextScaleFactor] so large accessibility
/// text never blows out the fixed height.
///
/// ## Theme
///
/// The surface and the baseline text follow the active theme's
/// `statusBar.background` and `statusBar.foreground` chrome tokens, which
/// `applyChromeTokens` resolves into [CruxChromeColors]. A theme that leaves
/// them unset gets `ColorScheme.surfaceContainerHighest` and
/// `ColorScheme.onSurface` at 75 % opacity. An explicit [backgroundColor] or
/// [textStyle] outranks the theme, so a host that styles its own segments
/// should start from [resolveTextStyle] to keep the theme's text colour.
///
/// ## The suite grammar — what goes in which slot, in what order
///
/// The slots above say *where* a widget can go. This says where it **should**,
/// so a user moving between the four products finds the same kind of fact in
/// the same place. Reading left to right:
///
/// 1. **[leading] — navigation affordances.** Panel chevrons and the phone
///    drawer handle. Never information.
/// 2. **[segments] — identity, then state, then transients.**
///    - *Identity* comes first, always: the one string answering "what am I
///      looking at" (waveform file, netlist source, project, `simcrux.yaml`).
///      With nothing open, either an explicit empty label or no segment at all
///      — never a stale one.
///    - *State* follows: facts derived from the open thing (cursor position,
///      top module, cell count, violation tally, run totals).
///    - *Transients* come last and are **zero-suppressed**: a segment earns
///      its width by having something to say. WaveCrux's secondary cursor,
///      delta and frequency render only with a second cursor placed; SimCrux's
///      skipped / timed-out / error counts render only when non-zero.
/// 3. **[segmentsTrailing] — fixed toggles** that must stay put while the
///    segment strip scrolls (WaveCrux's statistics-strip toggle).
/// 4. **[center] — the bottom-panel chevron**, in products that have a bottom
///    panel.
/// 5. **[trailing], in this order:**
///    - *Progress* first — a [CruxStatusBusyIndicator] or a determinate
///      indicator. Right-aligned progress is the suite's "the app is working"
///      signal and must not move as segments grow.
///    - *Extension slot* next — the widgets a Pro overlay injects through
///      the host's `statusBarTrailingWidgetsProvider`. Each renders
///      `SizedBox.shrink()` when idle, so the slot is weightless.
///    - *Panel chevron* last, hard against the right edge.
///
/// A product that has nothing for a slot omits it rather than filling it.
@immutable
class CruxStatusBar extends StatelessWidget {
  /// Creates a shared status bar from host-contributed slots.
  const CruxStatusBar({
    this.leading = const <Widget>[],
    this.segments = const <Widget>[],
    this.segmentsTrailing = const <Widget>[],
    this.center,
    this.trailing = const <Widget>[],
    this.height,
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.dividerColor,
    this.semanticsLabel,
    this.maxTextScaleFactor = 1.3,
    super.key,
  });

  /// Flush-left widgets rendered before the segment strip, with no dividers.
  final List<Widget> leading;

  /// Metric segments joined by a `|` divider inside a horizontally scrollable,
  /// left-aligned region. Prefer [CruxStatusSegment] for plain text.
  final List<Widget> segments;

  /// Fixed widgets rendered immediately after the (scrolling) segment strip,
  /// still within the left group.
  final List<Widget> segmentsTrailing;

  /// Optional widget pinned to the geometric center of the bar.
  final Widget? center;

  /// Right-pinned widgets, including the open-core/Pro trailing extension slot.
  final List<Widget> trailing;

  /// Bar height in logical pixels. Defaults to [kCruxStatusBarHeight].
  final double? height;

  /// Baseline text style for status text and the `|` dividers. When null
  /// [resolveTextStyle] derives it from the ambient theme. Individual
  /// [segments] may override their own style; this drives the dividers and
  /// the default segment look.
  final TextStyle? textStyle;

  /// Bar background. Defaults to the theme's `statusBar.background` chrome
  /// token ([CruxChromeColors.statusBarBackground]), then to
  /// [ColorScheme.surfaceContainerHighest].
  final Color? backgroundColor;

  /// Color of the 0.5 dp top border. Defaults to the theme's
  /// [ThemeData.dividerColor].
  final Color? borderColor;

  /// Color of the `|` segment dividers. Defaults to the theme's
  /// [ThemeData.dividerColor].
  final Color? dividerColor;

  /// Accessibility label announced for the status-bar region.
  final String? semanticsLabel;

  /// Upper bound on text scaling applied inside the bar so large accessibility
  /// text never overflows its fixed height.
  final double maxTextScaleFactor;

  /// Resolves the baseline status-bar [TextStyle] for [context], honoring an
  /// explicit [textStyle] override. Exposed so hosts can style their own
  /// [CruxStatusSegment]s with the exact baseline the bar uses.
  ///
  /// The baseline is a monospace [TextTheme.bodySmall] at
  /// [kCruxStatusBarFontSize], coloured with the theme's
  /// `statusBar.foreground` chrome token ([CruxChromeColors]) when it sets
  /// one, and otherwise with [ColorScheme.onSurface] at 75 % opacity.
  static TextStyle? resolveTextStyle(
    BuildContext context, {
    TextStyle? textStyle,
  }) {
    if (textStyle != null) return textStyle;
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: kCruxStatusBarFontSize,
      color:
          CruxChromeColors.of(context)?.statusBarForeground ??
          theme.colorScheme.onSurface.withValues(alpha: 0.75),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = CruxChromeColors.of(context);
    final resolvedTextStyle = resolveTextStyle(context, textStyle: textStyle);
    final resolvedDivider = dividerColor ?? theme.dividerColor;

    // The scrolling, left-aligned segment strip with `|` dividers between
    // adjacent segments.
    final segmentStrip = Flexible(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < segments.length; i++) ...<Widget>[
              if (i > 0)
                // Decorative, and marked as such. The `|` carries no
                // information — the segments either side do — so a screen
                // reader announcing "pipe" between every one is pure noise,
                // and it is deliberately low-contrast because a separator
                // should recede.
                //
                // ExcludeSemantics settles both at once. It also takes the
                // glyph out of the contrast assertion, correctly: WCAG's
                // contrast minimum applies to text that conveys meaning, and
                // this conveys none. Without the exclusion the accessibility
                // guard measured it at 3.92:1 (light) / 3.47:1 (dark) and
                // demanded a darker separator than the design wants.
                ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '|',
                      style: resolvedTextStyle?.copyWith(
                        color: resolvedDivider,
                      ),
                    ),
                  ),
                ),
              segments[i],
            ],
          ],
        ),
      ),
    );

    // Left group: leading widgets, then an Expanded strip so the segments sit
    // hard-left and any [center]/[trailing] are pushed to the right.
    final content = Row(
      children: <Widget>[
        ...leading,
        Expanded(
          child: Row(
            children: <Widget>[
              const SizedBox(width: 8),
              segmentStrip,
              ...segmentsTrailing,
            ],
          ),
        ),
        if (center != null) ...<Widget>[
          center!,
          const Expanded(child: SizedBox.shrink()),
        ],
        ...trailing,
      ],
    );

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScaleFactor,
        child: SizedBox(
          height: height ?? kCruxStatusBarHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  backgroundColor ??
                  chrome?.statusBarBackground ??
                  theme.colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(
                  color: borderColor ?? theme.dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// The suite's "working on it" indicator for a [CruxStatusBar]'s trailing
/// slot — a small indeterminate ring at the bar's scale.
///
/// Shared rather than hand-rolled per product: LintCrux, NetCrux and SimCrux
/// each need one for a different long operation (an engine run, Yosys
/// elaboration, a regression), and three hand-rolled spinners drift in size
/// and padding the moment one of them is touched. Sits first in
/// [CruxStatusBar.trailing] per the suite grammar, so it holds a fixed
/// position as segments grow.
@immutable
class CruxStatusBusyIndicator extends StatelessWidget {
  /// Creates the busy indicator.
  const CruxStatusBusyIndicator({
    this.semanticsLabel,
    this.size = 12,
    super.key,
  });

  /// Accessibility label announced while the indicator is on screen. Products
  /// should name the operation ("Running lint engines").
  final String? semanticsLabel;

  /// Diameter of the ring in logical pixels. The default keeps it inside the
  /// 24 dp bar with room to breathe.
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: semanticsLabel,
        ),
      ),
    ),
  );
}

/// A single plain-text segment for a [CruxStatusBar].
///
/// Ellipsizes on overflow. When [style] is null it inherits the bar's baseline
/// style ([CruxStatusBar.resolveTextStyle]) via the ambient default text style,
/// so hosts get consistent typography for free.
@immutable
class CruxStatusSegment extends StatelessWidget {
  /// Creates a text segment showing [label].
  const CruxStatusSegment(this.label, {this.style, super.key});

  /// The text shown in the segment.
  final String label;

  /// Optional style override. When null, the bar's baseline style is used.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolved = style ?? CruxStatusBar.resolveTextStyle(context);
    return Text(label, style: resolved, overflow: TextOverflow.ellipsis);
  }
}
