// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The gap between a control's edge and its focus ring.
const double kCruxFocusRingGap = 2;

/// The focus ring width: 1.5 px, or 2.5 px when the platform asks for high
/// contrast.
double cruxFocusRingWidth(BuildContext context) =>
    MediaQuery.highContrastOf(context) ? 2.5 : 1.5;

/// What a drawn control paints: whether it is pressed, hovered, showing
/// keyboard focus, and enabled.
@immutable
class CruxPressState {
  /// Creates a state.
  const CruxPressState({
    this.pressed = false,
    this.hovered = false,
    this.focused = false,
    this.enabled = true,
  });

  /// A pointer is down on the control.
  final bool pressed;

  /// A mouse pointer is over the control.
  final bool hovered;

  /// The control has keyboard focus and the focus highlight is showing
  /// (keyboard navigation, not a click).
  final bool focused;

  /// The control can be used.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is CruxPressState &&
      other.pressed == pressed &&
      other.hovered == hovered &&
      other.focused == focused &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(pressed, hovered, focused, enabled);

  @override
  String toString() =>
      'CruxPressState(pressed: $pressed, hovered: $hovered, '
      'focused: $focused, enabled: $enabled)';
}

/// Builds a drawn control for its [CruxPressState].
typedef CruxPressBuilder =
    Widget Function(BuildContext context, CruxPressState state);

/// The interaction core every owned Crux Desktop control is drawn on.
///
/// - **Pointer.** A click activates it; [CruxPressState.pressed] is true
///   between tap down and tap up. The cursor is the click cursor on Windows
///   and Linux and the arrow on macOS, as the platforms draw their own.
/// - **Keyboard.** A Tab stop (unless its [focusNode] skips traversal);
///   Space, Enter and numpad Enter activate it. [CruxPressState.focused] is
///   true only while the keyboard focus highlight shows, so a click never
///   draws the ring.
/// - **Screen reader.** One node: a button named [semanticLabel], with
///   [semanticValue], and the [selected] and [expanded] states when they are
///   given. What [builder] draws is excluded, so a visible label is not read
///   a second time.
/// - **Disabled** when [onPressed] is null: no focus, no hover, no press.
class CruxPressable extends StatefulWidget {
  /// Creates a pressable.
  const CruxPressable({
    required this.onPressed,
    required this.builder,
    this.semanticLabel,
    this.semanticValue,
    this.selected,
    this.expanded,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    super.key,
  });

  /// Called on a click, Space or Enter; null disables the control.
  final VoidCallback? onPressed;

  /// Draws the control.
  final CruxPressBuilder builder;

  /// The accessible name.
  final String? semanticLabel;

  /// The accessible value, such as a pop-up button's chosen item.
  final String? semanticValue;

  /// Whether the control is the selected one of a set; null leaves the
  /// state out.
  final bool? selected;

  /// Whether the control's menu or panel is open; null leaves the state
  /// out.
  final bool? expanded;

  /// An optional focus node.
  final FocusNode? focusNode;

  /// Whether the control takes focus when first built.
  final bool autofocus;

  /// Called when the control gains or loses focus.
  final ValueChanged<bool>? onFocusChange;

  @override
  State<CruxPressable> createState() => _CruxPressableState();
}

class _CruxPressableState extends State<CruxPressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void didUpdateWidget(CruxPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
  }

  void _activate() {
    if (!_enabled) return;
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final state = CruxPressState(
      pressed: _pressed && _enabled,
      hovered: _hovered && _enabled,
      focused: _focused && _enabled,
      enabled: _enabled,
    );
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      selected: widget.selected,
      expanded: widget.expanded,
      onTap: _enabled ? _activate : null,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: _enabled,
        onFocusChange: widget.onFocusChange,
        mouseCursor: _enabled && !mac
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        // The tap action is the container's: a second one here would split
        // the control into two nodes, one named and one focused.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: _enabled ? _activate : null,
          child: ExcludeSemantics(child: widget.builder(context, state)),
        ),
      ),
    );
  }
}

/// The one Crux Desktop keyboard-focus ring: a [width] stroke of [color]
/// [gap] outside the control's rounded rectangle of [radius], or [gap]
/// inside it when [inset] (a segment of a segmented control, whose ring must
/// not overlap its neighbours).
///
/// Painted in the foreground, so focusing never moves layout. [width]
/// defaults to [cruxFocusRingWidth] and [color] to the theme's primary.
class CruxFocusRing extends StatelessWidget {
  /// Creates a ring around [child].
  const CruxFocusRing({
    required this.focused,
    required this.child,
    this.radius = 4,
    this.color,
    this.width,
    this.gap = kCruxFocusRingGap,
    this.inset = false,
    super.key,
  });

  /// Whether the ring shows.
  final bool focused;

  /// The control.
  final Widget child;

  /// The control's corner radius.
  final double radius;

  /// The ring colour; null is the theme's primary.
  final Color? color;

  /// The stroke width; null is [cruxFocusRingWidth].
  final double? width;

  /// The distance between the control's edge and the ring.
  final double gap;

  /// Whether the ring sits inside the control's edge rather than outside.
  final bool inset;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: focused
        ? CruxFocusRingPainter(
            color: color ?? Theme.of(context).colorScheme.primary,
            radius: radius,
            width: width ?? cruxFocusRingWidth(context),
            gap: gap,
            inset: inset,
          )
        : null,
    child: child,
  );
}

/// Paints a [CruxFocusRing].
@immutable
class CruxFocusRingPainter extends CustomPainter {
  /// Creates the painter.
  const CruxFocusRingPainter({
    required this.color,
    required this.radius,
    required this.width,
    this.gap = kCruxFocusRingGap,
    this.inset = false,
  });

  /// The ring colour.
  final Color color;

  /// The control's corner radius.
  final double radius;

  /// The stroke width.
  final double width;

  /// The distance between the control's edge and the ring.
  final double gap;

  /// Whether the ring sits inside the control's edge.
  final bool inset;

  /// The rounded rectangle the stroke is centred on, for a control of
  /// [size].
  RRect ringFor(Size size) {
    final offset = gap + width / 2;
    final rect = Offset.zero & size;
    if (inset) {
      final r = radius - offset;
      return RRect.fromRectAndRadius(
        rect.deflate(offset),
        Radius.circular(r < 2 ? 2 : r),
      );
    }
    return RRect.fromRectAndRadius(
      rect.inflate(offset),
      Radius.circular(radius + offset),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      ringFor(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(CruxFocusRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.width != width ||
      oldDelegate.gap != gap ||
      oldDelegate.inset != inset;
}
