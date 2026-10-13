// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/src/table_metrics.dart';
import 'package:flutter/material.dart';

/// A text cell in a table's body row, sized by [flex] like its header.
///
/// The full value shows on hover, so a cell dragged narrow is still readable.
/// Hover only: a tooltip's default long-press trigger would claim the
/// long-press the row uses for its context menu on touch hosts. The text is
/// excluded from semantics: the row is read as one sentence by its one focus
/// stop, and a cell announced on its own is a fragment with no column
/// context.
///
/// An optional [annotation] (a chip that marks the row) renders inside the
/// cell, right-aligned after the text at its natural width. The text
/// ellipsizes first, and in a cell too narrow for both the annotation scales
/// down rather than overflowing. Inside the cell, not in a reserved slot
/// after the last column: a fixed slot at the row's end stopped the last
/// column short of the pane edge in every row, annotated or not.
class CruxTableCell extends StatelessWidget {
  /// Creates a cell showing [text] at [flex].
  const CruxTableCell({
    required this.text,
    required this.flex,
    this.tooltip,
    this.annotation,
    this.style,
    super.key,
  });

  /// The text keeps at least this much of the cell beside an annotation.
  static const double minTextWidth = 24;

  /// The gap between the text and its annotation.
  static const double annotationGap = 6;

  /// The cell's text, ellipsized when the column is narrower.
  final String text;

  /// The column's flex, from `CruxColumnLayout.flexOf`.
  final int flex;

  /// The hover tooltip; [text] when `null`. A path column shows a relative
  /// path and carries the full one here.
  final String? tooltip;

  /// Drawn after [text], right-aligned. Stays in semantics, so a tooltip of
  /// its own is still announced.
  final Widget? annotation;

  /// The text style; the theme's `bodySmall` when `null`.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = ExcludeSemantics(
      child: Tooltip(
        message: tooltip ?? text,
        triggerMode: TooltipTriggerMode.manual,
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: style ?? Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
    final annotation = this.annotation;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kCruxTableCellPadding),
        child: annotation == null
            ? Align(alignment: Alignment.centerLeft, child: label)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final room =
                      constraints.maxWidth - annotationGap - minTextWidth;
                  return Row(
                    children: <Widget>[
                      Expanded(child: label),
                      if (room > 0) ...<Widget>[
                        const SizedBox(width: annotationGap),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: room),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: annotation,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }
}
