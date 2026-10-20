// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Track width of a [CruxSwitch].
const double kCruxSwitchTrackWidth = 32;

/// Track height of a [CruxSwitch].
const double kCruxSwitchTrackHeight = 18;

/// Thumb diameter of a [CruxSwitch].
const double kCruxSwitchThumbSize = 14;

/// The desktop switch: a 32×18 track with a 14 px thumb.
///
/// Material 3's `Switch` is a 52×32 touch control with no size property, and
/// scaling it with `Transform.scale` shrinks its hit area and focus outline
/// with it while its semantics keep the old size. This is drawn at size.
///
/// A switch is only for a setting that takes effect at once. An option inside
/// a form that applies on OK is a checkbox.
///
/// - **Keyboard.** A Tab stop; Space and Enter toggle it.
/// - **Screen reader.** One node with the toggled state and [semanticLabel],
///   which a `CruxFormRow` sets from its row label, so the label is announced
///   with the state and the row's visible text is not read twice.
/// - **Focus.** An always-visible ring in the primary colour, 1.5 px, or
///   2.5 px when the platform asks for high contrast.
/// - **Hover and disabled** states. Null [onChanged] disables it.
class CruxSwitch extends StatefulWidget {
  /// Creates a switch.
  const CruxSwitch({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value; null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// The accessible name, normally the row label.
  final String? semanticLabel;

  /// An optional focus node.
  final FocusNode? focusNode;

  /// Whether the switch takes focus when first built.
  final bool autofocus;

  @override
  State<CruxSwitch> createState() => _CruxSwitchState();
}

class _CruxSwitchState extends State<CruxSwitch> {
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final on = widget.value;

    var track = on ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final border = on ? colorScheme.primary : colorScheme.outline;
    var thumb = on ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    if (_hovered && _enabled) {
      track = Color.alphaBlend(
        colorScheme.onSurface.withValues(alpha: on ? 0.12 : 0.08),
        track,
      );
    }
    if (!_enabled) {
      track = track.withValues(alpha: 0.38);
      thumb = thumb.withValues(alpha: 0.38);
    }
    final ring = highContrast ? 2.5 : 1.5;

    final painted = Padding(
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        // The focus ring: drawn outside the track with a 2 px gap, always
        // visible on keyboard focus, transparent otherwise so focusing never
        // moves the track.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kCruxSwitchTrackHeight),
          border: Border.all(
            color: _focused ? colorScheme.primary : Colors.transparent,
            width: ring,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: kCruxSwitchTrackWidth,
            height: kCruxSwitchTrackHeight,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(
                kCruxSwitchTrackHeight / 2,
              ),
              border: Border.all(
                color: _enabled ? border : border.withValues(alpha: 0.38),
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: kCruxSwitchThumbSize,
                  height: kCruxSwitchThumbSize,
                  decoration: BoxDecoration(
                    color: thumb,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      toggled: on,
      enabled: _enabled,
      label: widget.semanticLabel,
      onTap: _enabled ? _toggle : null,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: _enabled,
        mouseCursor: _enabled
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
              _toggle();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        // The tap action is the container's: a second one here would split
        // the switch into two nodes, one named and one focused.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _enabled ? _toggle : null,
          child: ExcludeSemantics(child: painted),
        ),
      ),
    );
  }
}
