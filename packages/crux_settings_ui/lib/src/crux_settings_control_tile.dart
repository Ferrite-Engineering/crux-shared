// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/src/crux_form_row.dart';
import 'package:flutter/material.dart';

/// A settings row around a control that is not a plain switch: a
/// `SegmentedButton`, a dropdown.
///
/// A [CruxFormRow]: on desktop the [title] and [description] take the row
/// and the [control] sits at its end; on phone and tablet the label stacks
/// above a full-width control. The title is the control's accessible name.
class CruxSettingsControlTile extends StatelessWidget {
  /// Creates a control row.
  const CruxSettingsControlTile({
    required this.title,
    required this.control,
    this.description,
    super.key,
  });

  /// Row label.
  final String title;

  /// Optional secondary description shown under the [title].
  final String? description;

  /// The control.
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: CruxFormRow(label: title, help: description, child: control),
    );
  }
}
