// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_ide_layout/src/crux_control_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One choice of a [CruxSegmentedControl].
@immutable
class CruxSegment<T> {
  /// Creates a segment.
  const CruxSegment({
    required this.value,
    required this.label,
    this.icon,
    this.iconOnly = false,
    this.tooltip,
    this.enabled = true,
  }) : assert(!iconOnly || icon != null, 'An icon-only segment needs an icon.');

  /// The value the segment selects.
  final T value;

  /// The localized label. Always required: drawn beside the icon, or, for an
  /// [iconOnly] segment, not drawn but kept as the accessible name and as
  /// the tooltip.
  final String label;

  /// An optional glyph before the label, or alone when [iconOnly].
  final IconData? icon;

  /// Whether the segment draws only [icon]. Its width is the 16 px icon plus
  /// the icon-button padding (7 px each side, 6 px when dense), so three fit
  /// in 96 px; [label] is its semantic name and, unless
  /// [tooltip] says otherwise, its tooltip (on hover and on keyboard focus).
  final bool iconOnly;

  /// An optional hover explanation. Not part of the accessible name. An
  /// [iconOnly] segment falls back to [label] when this is null.
  final String? tooltip;

  /// Whether the segment can be chosen.
  final bool enabled;
}

/// The Crux Desktop segmented control: one choice of a few, drawn by the
/// suite rather than Material's `SegmentedButton`.
///
/// - **Look.** 28 px tall (`CruxDesktopTokens.controlHeight`), or 24 px
///   with [dense] in dock strips and panel headers; a 4 px radius; one flat
///   track with a 1 px border; segments flush inside it with 1 px dividers
///   that hide beside the selected segment; the selected segment filled, its
///   label semibold. No check glyph.
/// - **Keyboard.** The control is one Tab stop, landing on the selected
///   segment. The arrow keys, Home and End move focus between segments
///   (skipping disabled ones); Space and Enter select the focused one. The
///   focus ring is drawn around the focused segment only, inside its edges,
///   so it never overlaps a neighbour.
/// - **Screen reader.** One group named [semanticLabel] holding one button
///   per segment, named by its label, with the selected state on the
///   selected one.
/// - **Hover, press, disabled and high contrast** states. A null
///   [onChanged] disables every segment.
///
/// Single-select only; [selected] may be null when nothing is chosen yet.
class CruxSegmentedControl<T> extends StatefulWidget {
  /// Creates a segmented control.
  const CruxSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    this.dense = false,
    super.key,
  });

  /// The choices, in order.
  final List<CruxSegment<T>> segments;

  /// The chosen value, or null for none.
  final T? selected;

  /// Called with the value of the segment chosen; null disables the
  /// control. Not called when the selected segment is chosen again.
  final ValueChanged<T>? onChanged;

  /// The accessible name of the group, normally its row label.
  final String? semanticLabel;

  /// Whether the control takes the dense height of dock strips.
  final bool dense;

  @override
  State<CruxSegmentedControl<T>> createState() =>
      _CruxSegmentedControlState<T>();
}

class _CruxSegmentedControlState<T> extends State<CruxSegmentedControl<T>> {
  final List<FocusNode> _nodes = <FocusNode>[];
  final List<GlobalKey<TooltipState>> _tips = <GlobalKey<TooltipState>>[];

  /// The segment that is the group's Tab stop.
  int _current = 0;

  bool get _enabled => widget.onChanged != null;

  bool _usable(int i) => _enabled && widget.segments[i].enabled;

  int get _selectedIndex =>
      widget.segments.indexWhere((s) => s.value == widget.selected);

  @override
  void initState() {
    super.initState();
    _syncNodes();
    _current = _restingStop();
  }

  @override
  void didUpdateWidget(CruxSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNodes();
    final focusedInside = _nodes.any((n) => n.hasFocus);
    if (!focusedInside || _current >= _nodes.length || !_usable(_current)) {
      _current = _restingStop();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncNodes() {
    while (_nodes.length < widget.segments.length) {
      final i = _nodes.length;
      _nodes.add(FocusNode(debugLabel: 'CruxSegment $i'));
      _tips.add(GlobalKey<TooltipState>());
    }
    while (_nodes.length > widget.segments.length) {
      _nodes.removeLast().dispose();
      _tips.removeLast();
    }
  }

  /// Where Tab lands: the selected segment, else the first usable one.
  int _restingStop() {
    final selected = _selectedIndex;
    if (selected >= 0 && _usable(selected)) return selected;
    for (var i = 0; i < widget.segments.length; i++) {
      if (_usable(i)) return i;
    }
    return 0;
  }

  String? _tooltipFor(CruxSegment<T> s) =>
      s.tooltip ?? (s.iconOnly ? s.label : null);

  void _choose(int i) {
    final onChanged = widget.onChanged;
    if (onChanged == null || !widget.segments[i].enabled) return;
    if (i == _selectedIndex) return;
    onChanged(widget.segments[i].value);
  }

  void _moveTo(int i) {
    if (i < 0 || i >= _nodes.length) return;
    setState(() => _current = i);
    _nodes[i].requestFocus();
  }

  int? _next(int from, int step) {
    for (var i = from + step; i >= 0 && i < _nodes.length; i += step) {
      if (_usable(i)) return i;
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = _nodes.indexWhere((n) => n.hasFocus);
    if (focused < 0) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = event.logicalKey;
    int? target;
    if (key == LogicalKeyboardKey.arrowRight) {
      target = _next(focused, rtl ? -1 : 1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      target = _next(focused, rtl ? 1 : -1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      target = _next(focused, 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      target = _next(focused, -1);
    } else if (key == LogicalKeyboardKey.home) {
      target = _next(-1, 1);
    } else if (key == LogicalKeyboardKey.end) {
      target = _next(_nodes.length, -1);
    } else {
      return KeyEventResult.ignored;
    }
    if (target != null) _moveTo(target);
    // Handled at the ends too, so an arrow never leaves the group.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final style = CruxControlStyle.of(context, dense: widget.dense);
    final selected = _selectedIndex;
    final inner = style.radius - 1;
    final segmentHeight = style.height - 2;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    for (var i = 0; i < _nodes.length; i++) {
      _nodes[i].skipTraversal = i != _current;
    }

    Widget segment(int i) {
      final s = widget.segments[i];
      final on = i == selected;
      final usable = _usable(i);
      final first = i == 0;
      final last = i == widget.segments.length - 1;
      final start = Radius.circular(first ? inner : 0);
      final end = Radius.circular(last ? inner : 0);
      final radius = BorderRadius.horizontal(
        left: rtl ? end : start,
        right: rtl ? start : end,
      );
      Widget child = CruxPressable(
        key: ValueKey<String>('cruxSegment-$i'),
        focusNode: _nodes[i],
        onPressed: usable ? () => _choose(i) : null,
        semanticLabel: s.label,
        selected: on,
        onFocusChange: (focused) {
          if (focused && _current != i) setState(() => _current = i);
          if (_tooltipFor(s) == null) return;
          if (!focused) {
            Tooltip.dismissAllToolTips();
          } else if (FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional) {
            _tips[i].currentState?.ensureTooltipVisible();
          }
        },
        builder: (context, state) {
          final base = on ? style.selectedFill : style.face;
          var face = state.pressed
              ? style.pressed(base)
              : state.hovered && !on
              ? style.hover(base)
              : base;
          var text = on ? style.onSelected : style.label;
          if (!state.enabled) {
            face = style.disabled(face);
            text = style.labelDisabled;
          }
          final labelStyle = style.button.copyWith(
            color: text,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          );
          return CruxFocusRing(
            focused: state.focused,
            color: style.focus,
            radius: inner,
            inset: true,
            child: Container(
              height: segmentHeight,
              padding: EdgeInsets.symmetric(
                horizontal: s.iconOnly
                    ? (widget.dense ? 6 : 7)
                    : (widget.dense ? 10 : 12),
              ),
              decoration: BoxDecoration(color: face, borderRadius: radius),
              child: Center(
                widthFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.iconOnly)
                      Icon(s.icon, size: 16, color: text)
                    else ...[
                      if (s.icon case final IconData icon) ...[
                        Icon(icon, size: 16, color: text),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (_tooltipFor(s) case final String tooltip) {
        child = Tooltip(
          key: _tips[i],
          message: tooltip,
          excludeFromSemantics: true,
          child: child,
        );
      }
      return child;
    }

    Widget divider(int i) {
      final hidden = i == selected || i + 1 == selected;
      return SizedBox(
        width: 1,
        height: segmentHeight,
        child: ColoredBox(color: hidden ? Colors.transparent : style.border),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: Container(
          height: style.height,
          decoration: BoxDecoration(
            color: _enabled ? style.face : style.disabled(style.face),
            borderRadius: BorderRadius.circular(style.radius),
            border: Border.all(color: style.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.segments.length; i++) ...[
                if (i > 0) divider(i - 1),
                segment(i),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
