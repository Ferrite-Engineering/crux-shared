// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/src/shortcut_label.dart';
import 'package:crux_keybindings/src/widgets/key_binding_editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One editable row in a keyboard-shortcut list: an action label and its
/// current binding, plus edit / unbind / reset affordances. Entering capture
/// mode swaps the binding chip for an inline capture field (supplied by the
/// parent via [captureField]).
///
/// Given a `focusNode`, the row itself is the keyboard stop: it is announced
/// as one button named "action, binding" (plus any conflict), Enter or Space
/// starts capture, Delete or Backspace unbinds, and Shift+Delete resets. The
/// icon buttons stay for the pointer but leave the Tab order, so a list of
/// eighty actions is not two hundred Tab stops. Without a focus node the row
/// keeps its original pointer-and-Tab behaviour.
///
/// A presentation widget — all state and persistence live in the host; the row
/// only renders and forwards taps. Domain-neutral: the action is identified by
/// its already-localized [label], not by any product enum.
class KeyBindingRow extends StatelessWidget {
  /// Creates a binding row.
  const KeyBindingRow({
    required this.label,
    required this.activator,
    required this.metrics,
    required this.notBoundLabel,
    required this.conflictMessage,
    required this.isCustomized,
    required this.editTooltip,
    required this.unbindTooltip,
    required this.resetTooltip,
    required this.onEdit,
    required this.onUnbind,
    required this.onReset,
    this.conflictIsShadowed = false,
    this.captureField,
    this.focusNode,
    this.notBoundSpokenLabel,
    super.key,
  });

  /// Makes the row a single keyboard stop; see the class documentation.
  final FocusNode? focusNode;

  /// What a screen reader says for an unbound row. Null uses
  /// [notBoundLabel].
  final String? notBoundSpokenLabel;

  /// Localized action name.
  final String label;

  /// The action's current activator, or null when unbound.
  final ShortcutActivator? activator;

  /// Host-supplied sizing.
  final KeyBindingEditorMetrics metrics;

  /// Localized placeholder shown when [activator] is null.
  final String notBoundLabel;

  /// Localized conflict warning, or null when there's no conflict.
  final String? conflictMessage;

  /// Whether this row's binding is *shadowed* by another action (it will not
  /// fire). Shadowed rows render the warning in the theme's error color with a
  /// blocking icon; a row that merely shares its chord but still fires renders
  /// in the softer amber warning style. Ignored when [conflictMessage] is null.
  final bool conflictIsShadowed;

  /// Whether the current binding differs from the platform default (controls
  /// whether the reset affordance is shown).
  final bool isCustomized;

  /// Tooltip for the edit (start-capture) button.
  final String editTooltip;

  /// Tooltip for the unbind button.
  final String unbindTooltip;

  /// Tooltip for the reset-to-default button.
  final String resetTooltip;

  /// Invoked when the edit button is tapped (enter capture mode).
  final VoidCallback onEdit;

  /// Invoked when the unbind button is tapped.
  final VoidCallback onUnbind;

  /// Invoked when the reset button is tapped.
  final VoidCallback onReset;

  /// When non-null, the row is in capture mode and renders this widget (the
  /// parent's capture field) instead of the chip + buttons.
  final Widget? captureField;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasConflict = conflictMessage != null;
    // Shadowed (won't-fire) conflicts use the error color + a blocking icon;
    // a still-firing chord-sharer uses the softer amber warning.
    final conflictColor = conflictIsShadowed
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;
    final conflictIcon = conflictIsShadowed
        ? Icons.error_outline
        : Icons.warning_amber_rounded;

    final node = focusNode;
    if (node == null) {
      return _layout(theme, hasConflict, conflictColor, conflictIcon);
    }
    final spokenBinding = formatShortcutSpokenLabel(
      activator,
      emptyLabel: notBoundSpokenLabel ?? notBoundLabel,
    );
    return Semantics(
      container: true,
      button: true,
      label: <String>[
        label,
        spokenBinding,
        ?conflictMessage,
      ].join(', '),
      onTap: captureField == null ? onEdit : null,
      child: Focus(
        focusNode: node,
        onKeyEvent: _onKeyEvent,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, child) => DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: node.hasFocus
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            child: child,
          ),
          child: _layout(
            theme,
            hasConflict,
            conflictColor,
            conflictIcon,
            rowIsTheStop: true,
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || captureField != null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final modified =
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed;
    if (modified) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      onEdit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (keyboard.isShiftPressed) {
        if (!isCustomized) return KeyEventResult.ignored;
        onReset();
      } else {
        if (activator == null) return KeyEventResult.ignored;
        onUnbind();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The visual row. When [rowIsTheStop], the row's own semantics already
  /// say everything the text, chip and buttons say, so those are excluded
  /// (and the buttons leave the Tab order); the capture field is not, since
  /// it is where focus goes during capture.
  Widget _layout(
    ThemeData theme,
    bool hasConflict,
    Color conflictColor,
    IconData conflictIcon, {
    bool rowIsTheStop = false,
  }) {
    Widget quiet(Widget child) => rowIsTheStop
        ? ExcludeSemantics(child: ExcludeFocusTraversal(child: child))
        : child;
    return Padding(
      // Match the 16dp horizontal inset host cards apply to their ListTile
      // rows, so these custom rows don't hug the card edge.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: quiet(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: metrics.bodyFontSize,
                    ),
                  ),
                  if (hasConflict) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          conflictIcon,
                          size: metrics.labelFontSize + 2,
                          color: conflictColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            conflictMessage!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: metrics.labelFontSize,
                              color: conflictColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (captureField != null)
            captureField!
          else
            quiet(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BindingChip(
                    label: formatShortcutLabel(
                      activator,
                      emptyLabel: notBoundLabel,
                    ),
                    isPlaceholder: activator == null,
                    fontSize: metrics.monoFontSize,
                  ),
                  _RowIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: editTooltip,
                    onPressed: onEdit,
                    target: metrics.touchTarget,
                    iconSize: metrics.iconSize,
                  ),
                  if (activator != null)
                    _RowIconButton(
                      icon: Icons.backspace_outlined,
                      tooltip: unbindTooltip,
                      onPressed: onUnbind,
                      target: metrics.touchTarget,
                      iconSize: metrics.iconSize,
                    ),
                  if (isCustomized)
                    _RowIconButton(
                      icon: Icons.settings_backup_restore,
                      tooltip: resetTooltip,
                      onPressed: onReset,
                      target: metrics.touchTarget,
                      iconSize: metrics.iconSize,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BindingChip extends StatelessWidget {
  const _BindingChip({
    required this.label,
    required this.isPlaceholder,
    required this.fontSize,
  });

  final String label;
  final bool isPlaceholder;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          color: isPlaceholder
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// An icon button whose hit area meets the touch-target floor.
class _RowIconButton extends StatelessWidget {
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.target,
    required this.iconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double target;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: iconSize,
      tooltip: tooltip,
      // No VisualDensity.compact: it would shrink the hit area below the
      // [target] touch floor. The constraints govern the minimum size.
      constraints: BoxConstraints(minWidth: target, minHeight: target),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
