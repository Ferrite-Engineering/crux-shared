// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/src/widgets/double_tap_region.dart';
import 'package:crux_annotations/src/widgets/inline_editor.dart';
import 'package:crux_annotations/src/widgets/number_dot.dart';
import 'package:flutter/material.dart';

/// The key of a balloon's text, the double-tap target that opens its editor.
const ValueKey<String> kCruxCalloutBalloonTextKey = ValueKey<String>(
  'annotation-balloon-text',
);

/// An expanded callout: its number, its text (or the inline editor), and the
/// fold and delete controls.
///
/// Every string is the caller's; the package carries no localizations.
class CruxCalloutBalloon extends StatelessWidget {
  /// Creates the balloon.
  const CruxCalloutBalloon({
    required this.text,
    required this.number,
    required this.color,
    required this.surface,
    required this.onSurface,
    required this.drifted,
    required this.touchTarget,
    required this.isEditing,
    required this.onCollapse,
    required this.onDelete,
    required this.onCommit,
    required this.onBeginEdit,
    required this.collapseTooltip,
    required this.deleteTooltip,
    required this.editHint,
    required this.maxLength,
    this.selected = false,
    this.maxLines = 4,
    super.key,
  });

  /// The text shown, or the editor's starting text.
  final String text;

  /// The callout's number, matching its panel row.
  final int number;

  /// The border and number colour: the note's own, its author's, or the drift
  /// amber.
  final Color color;

  /// The balloon's ground, drawn nearly opaque so the canvas stays faintly
  /// legible underneath.
  final Color surface;

  /// The text colour.
  final Color onSurface;

  /// Whether the note is drifted; its text then reads in italics.
  final bool drifted;

  /// The product's pointer target size; the fold and delete controls are 0.6
  /// of it square.
  final double touchTarget;

  /// Whether the inline editor replaces the text.
  final bool isEditing;

  /// Folds this balloon back to its numbered dot. Null when this viewer may
  /// not fold the note: the control is then absent, never inert.
  final VoidCallback? onCollapse;

  /// Removes the note. Null when this viewer may not remove it: the control is
  /// then absent, never inert.
  final VoidCallback? onDelete;

  /// Receives the editor's text on commit.
  final void Function(String text) onCommit;

  /// Opens the editor, on a double-tap of the text alone.
  ///
  /// A single tap cannot do it: selection rides pointer-down, and if one click
  /// also opened the editor every following keystroke would go to a text
  /// field. And the recognizer must not wrap the whole balloon, or every tap
  /// on the fold and delete controls would wait out the double-tap timeout.
  /// Null when the note's words are somebody else's.
  final VoidCallback? onBeginEdit;

  /// The fold control's tooltip and spoken name.
  final String collapseTooltip;

  /// The delete control's tooltip and spoken name.
  final String deleteTooltip;

  /// The editor's placeholder.
  final String editHint;

  /// The product's bound on a note's text.
  final int maxLength;

  /// Whether this is the selected callout. See
  /// [CruxCalloutNumberDot.selected].
  final bool selected;

  /// How many lines of [text] are shown before an ellipsis.
  final int maxLines;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: surface.withValues(alpha: 0.92),
      border: Border.all(color: color, width: selected ? 2.5 : 1.5),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CruxCalloutNumberDot(
            number: number,
            color: color,
            onColor: surface,
            selected: selected,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: isEditing
                ? CruxCalloutInlineEditor(
                    initialText: text,
                    hint: editHint,
                    color: onSurface,
                    onCommit: onCommit,
                    maxLength: maxLength,
                  )
                : CruxCalloutDoubleTapRegion(
                    key: kCruxCalloutBalloonTextKey,
                    onDoubleTap: onBeginEdit,
                    child: Text(
                      text,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        color: onSurface,
                        fontStyle: drifted
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
          ),
          if (!isEditing && onCollapse != null)
            _BalloonControl(
              label: collapseTooltip,
              icon: Icons.unfold_less,
              extent: touchTarget * 0.6,
              color: onSurface,
              onTap: onCollapse!,
            ),
          if (onDelete != null)
            _BalloonControl(
              label: deleteTooltip,
              icon: Icons.close,
              extent: touchTarget * 0.6,
              color: onSurface,
              onTap: onDelete!,
            ),
        ],
      ),
    ),
  );
}

class _BalloonControl extends StatelessWidget {
  const _BalloonControl({
    required this.label,
    required this.icon,
    required this.extent,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final double extent;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: extent,
          height: extent,
          child: Icon(icon, size: 12, color: color.withValues(alpha: 0.7)),
        ),
      ),
    ),
  );
}
