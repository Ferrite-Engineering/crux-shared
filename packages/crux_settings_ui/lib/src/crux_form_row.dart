// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show CruxDesktopTokens, CruxSegmentedControl;
import 'package:flutter/material.dart';

/// The label column width a [CruxFormSection] gives its rows by default.
const double kCruxFormLabelWidth = 140;

/// The widest a control grows at the end of a spread (Settings) row.
const double kCruxFormSpreadControlMaxWidth = 320;

/// A group of [CruxFormRow]s with one label column: an optional heading,
/// then the rows, evenly spaced.
///
/// Rows inside a section line their labels up in a column [labelWidth] wide,
/// the desktop form idiom: label left, control right, no floating labels. A
/// Settings pane passes a null [labelWidth] and gets spread rows instead.
class CruxFormSection extends StatelessWidget {
  /// Creates a section.
  const CruxFormSection({
    required this.children,
    this.title,
    this.labelWidth = kCruxFormLabelWidth,
    this.spacing = 8,
    super.key,
  });

  /// The rows, normally [CruxFormRow]s.
  final List<Widget> children;

  /// An optional localized heading.
  final String? title;

  /// The label column's width. Null lines nothing up: each row spreads its
  /// label and control apart, the Settings idiom.
  final double? labelWidth;

  /// The vertical gap between rows.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = title;
    return _CruxFormScope(
      labelWidth: labelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (heading != null) ...<Widget>[
            Semantics(
              header: true,
              child: Text(
                heading,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(height: spacing),
          ],
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _CruxFormScope extends InheritedWidget {
  const _CruxFormScope({required this.labelWidth, required super.child});

  final double? labelWidth;

  static double? labelWidthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CruxFormScope>()?.labelWidth;

  @override
  bool updateShouldNotify(_CruxFormScope oldWidget) =>
      labelWidth != oldWidget.labelWidth;
}

enum _RowKind { control, toggle, checkbox }

/// One labelled control: the label on the left, the control on the right,
/// optional help text under the control.
///
/// - **Layout.** Inside a [CruxFormSection] (or with [labelWidth]) the label
///   sits in a fixed column and the control fills the rest. Otherwise the
///   label and help text take the row and the control sits at its end, the
///   Settings idiom. Under a theme without `CruxDesktopTokens` (phone and
///   tablet) the label stacks above the control, as Material forms do.
/// - **Name.** The label is the control's accessible name: the row is one
///   semantics node carrying the label, the control's role and state, and
///   the help text as its hint. A control that holds several focusable
///   parts (a field with a browse button) passes `mergeSemantics: false` and
///   names its parts itself.
/// - **Click target.** For [CruxFormRow.toggle] and [CruxFormRow.checkbox]
///   the label is clickable and toggles the control.
///
/// A switch is only for a setting that takes effect at once; inside a form
/// that applies on OK, use [CruxFormRow.checkbox].
class CruxFormRow extends StatelessWidget {
  /// A row around any [child] control: a text field, a dropdown, a segmented
  /// button, a slider.
  const CruxFormRow({
    required this.label,
    required Widget this.child,
    this.help,
    this.labelWidth,
    this.mergeSemantics = true,
    super.key,
  }) : _kind = _RowKind.control,
       value = null,
       onChanged = null;

  /// A row holding a [CruxSwitch], for a setting that applies at once.
  /// Space, Enter, the switch and the label all toggle it.
  const CruxFormRow.toggle({
    required this.label,
    required bool this.value,
    required this.onChanged,
    this.help,
    this.labelWidth,
    super.key,
  }) : _kind = _RowKind.toggle,
       child = null,
       mergeSemantics = true;

  /// A row holding a checkbox, for an option in a form that applies on OK.
  /// The label sits after the box and toggles it.
  const CruxFormRow.checkbox({
    required this.label,
    required bool this.value,
    required this.onChanged,
    this.help,
    this.labelWidth,
    super.key,
  }) : _kind = _RowKind.checkbox,
       child = null,
       mergeSemantics = true;

  /// The localized label, also the control's accessible name.
  final String label;

  /// The control, for the default constructor.
  final Widget? child;

  /// Optional localized help text, shown under the control and read as the
  /// row's hint.
  final String? help;

  /// The label column width; null takes the enclosing [CruxFormSection]'s,
  /// and with neither the row spreads label and control apart.
  final double? labelWidth;

  /// Whether the label and [child] merge into one semantics node.
  final bool mergeSemantics;

  /// The toggle or checkbox state.
  final bool? value;

  /// Called with the new toggle or checkbox state; null disables the row.
  final ValueChanged<bool>? onChanged;

  final _RowKind _kind;

  bool get _enabled => _kind == _RowKind.control || onChanged != null;

  void _toggle() {
    final change = onChanged;
    if (change != null) change(!(value ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktop = CruxDesktopTokens.of(context);
    final width = labelWidth ?? _CruxFormScope.labelWidthOf(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: _enabled
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurface.withValues(alpha: 0.38),
    );
    final helpStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // A segmented control is not merged into the row (see the end of build)
    // and names its own group, so the visible label would be a second,
    // identical name around it.
    final segmented = child is CruxSegmentedControl;
    final labelText = segmented
        ? ExcludeSemantics(child: Text(label, style: labelStyle))
        : Text(label, style: labelStyle);
    // The whole label area, not only the glyphs, toggles a switch or a
    // checkbox.
    Widget clickable(Widget area) {
      if (_kind == _RowKind.control || !_enabled) return area;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        // The control carries the tap action for a screen reader; a second
        // one on the label would compete with it in the merged row.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _toggle,
          child: area,
        ),
      );
    }

    final helpText = help == null
        ? null
        : ExcludeSemantics(child: Text(help!, style: helpStyle));

    final control = switch (_kind) {
      _RowKind.control => child!,
      _RowKind.toggle =>
        desktop == null
            ? Switch(
                value: value ?? false,
                onChanged: onChanged == null ? null : (v) => onChanged!(v),
              )
            : CruxSwitch(value: value ?? false, onChanged: onChanged),
      _RowKind.checkbox => Checkbox(
        value: value ?? false,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      ),
    };

    final Widget row;
    if (_kind == _RowKind.checkbox) {
      // The box leads and the label follows it, in the control column when
      // there is one.
      final box = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          control,
          const SizedBox(width: 6),
          Expanded(
            child: clickable(
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[labelText, ?helpText],
                ),
              ),
            ),
          ),
        ],
      );
      row = width == null || desktop == null
          ? box
          : Padding(
              padding: EdgeInsets.only(left: width),
              child: box,
            );
    } else if (desktop == null) {
      // Phone and tablet: label above the control, or beside a switch.
      row = _kind == _RowKind.toggle
          ? Row(
              children: <Widget>[
                Expanded(
                  child: clickable(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[labelText, ?helpText],
                    ),
                  ),
                ),
                control,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                labelText,
                ?helpText,
                const SizedBox(height: 6),
                control,
              ],
            );
    } else if (width != null) {
      // A form: the label in its column, the control filling the rest.
      row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: width,
            child: clickable(
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 12),
                child: labelText,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: desktop.controlHeight),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: control,
                  ),
                ),
                if (helpText != null) ...<Widget>[
                  const SizedBox(height: 2),
                  helpText,
                ],
              ],
            ),
          ),
        ],
      );
    } else {
      // Settings: label and help take the row, the control sits at its end.
      row = Row(
        children: <Widget>[
          Expanded(
            child: clickable(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  labelText,
                  if (helpText != null) ...<Widget>[
                    const SizedBox(height: 2),
                    helpText,
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Bounded, so a control that fills its width (a field with a
          // button beside it) has a width to fill; anything narrower keeps
          // its own size.
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kCruxFormSpreadControlMaxWidth,
            ),
            child: control,
          ),
        ],
      );
    }

    // A segmented control is a group of buttons, one per segment, each with
    // its own selected state: merged into the row it would be one node with
    // three taps. It names its group itself (its semanticLabel).
    if (!mergeSemantics || segmented) return row;
    return MergeSemantics(
      child: Semantics(hint: help, child: row),
    );
  }
}
