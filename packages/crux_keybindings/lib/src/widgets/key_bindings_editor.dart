// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_keybindings/src/key_binding.dart';
import 'package:crux_keybindings/src/key_binding_resolver.dart';
import 'package:crux_keybindings/src/shortcut_conflicts.dart';
import 'package:crux_keybindings/src/widgets/key_binding_editor_metrics.dart';
import 'package:crux_keybindings/src/widgets/key_binding_row.dart';
import 'package:crux_keybindings/src/widgets/key_bindings_editor_strings.dart';
import 'package:crux_keybindings/src/widgets/shortcut_capture_field.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps one category's rows in the host application's grouped-settings
/// surface.
///
/// Supplied by the host so this package stays independent of any settings-UI
/// shell — products using `crux_settings_ui` pass
/// `(context, rows) => CruxSettingsCard(children: rows)`.
typedef KeyBindingsCategoryCardBuilder =
    Widget Function(BuildContext context, List<Widget> rows);

/// The full editable keyboard-shortcut list — actions grouped by category, each
/// with a binding chip, key capture, live conflict warning, unbind, and reset,
/// plus Import / Export / Reset-all controls. Generic over a product's
/// [CruxAction] enum.
///
/// Drops into a settings detail pane (it returns a [Column]; pair it with the
/// `crux_settings_ui` master-detail shell). The widget owns only transient
/// capture state and the reset-all confirmation dialog; everything else —
/// bindings, defaults, conflict computation, persistence, file I/O, and the
/// grouped-card surface itself ([categoryCardBuilder]) — is the host's,
/// supplied via parameters and callbacks. This keeps the package free of
/// Riverpod, file pickers, localization, and any settings-UI shell.
class KeyBindingsEditor<A extends CruxAction> extends StatefulWidget {
  /// Creates the editor.
  const KeyBindingsEditor({
    required this.actions,
    required this.categoryOf,
    required this.categoryLabelOf,
    required this.labelOf,
    required this.bindings,
    required this.defaults,
    required this.conflicts,
    required this.metrics,
    required this.strings,
    required this.onCapture,
    required this.onUnbind,
    required this.onReset,
    required this.onResetAll,
    required this.onImport,
    required this.onExport,
    required this.categoryCardBuilder,
    this.conflictDetails,
    this.conflictMessages,
    this.accessibilityStrings,
    this.showPhoneNote = false,
    super.key,
  }) : assert(
         conflictDetails == null || conflictMessages != null,
         'conflictMessages must be supplied when conflictDetails is set',
       );

  /// All actions, in display order. Grouped into category sections by
  /// [categoryOf], preserving first-encounter category order.
  final List<A> actions;

  /// The category an action belongs to.
  final ActionCategory Function(A action) categoryOf;

  /// Localized header label for a category.
  final String Function(ActionCategory category) categoryLabelOf;

  /// Localized name for an action.
  final String Function(A action) labelOf;

  /// The current resolved activator for each action (absent = unbound).
  final Map<A, ShortcutActivator> bindings;

  /// The platform-default activators, used to decide which rows are customized.
  final Map<A, ShortcutActivator> defaults;

  /// For each conflicting action, the other actions sharing its chord.
  ///
  /// Used for the legacy *symmetric* warning
  /// ([KeyBindingsEditorStrings.conflict]) when [conflictDetails] is not
  /// supplied. When [conflictDetails] is supplied it takes precedence and this
  /// map is ignored.
  final Map<A, List<A>> conflicts;

  /// Optional richer conflict view (from `resolveShortcutConflicts`). When
  /// supplied — together with [conflictMessages] — each conflicting row renders
  /// an **asymmetric** message distinguishing the action that fires from the
  /// one(s) it shadows, and a summary banner shows the total conflict count.
  /// When null, the editor falls back to the symmetric [conflicts] behavior so
  /// existing hosts keep working unchanged.
  final Map<A, ShortcutConflictEntry<A>>? conflictDetails;

  /// Localized message builders for the asymmetric conflict UI. Required to be
  /// non-null whenever [conflictDetails] is supplied.
  final KeyBindingsConflictMessages? conflictMessages;

  /// Localized keyboard hint and spoken placeholder. The list is keyboard
  /// operable either way — one Tab stop, arrows between rows, Enter, Delete
  /// and Shift+Delete on a row — but only this explains it.
  final KeyBindingsAccessibilityStrings? accessibilityStrings;

  /// Host-supplied sizing.
  final KeyBindingEditorMetrics metrics;

  /// Host-supplied localized strings.
  final KeyBindingsEditorStrings strings;

  /// Called when the user captures a new chord for an action.
  final void Function(A action, KeyBinding binding) onCapture;

  /// Called when the user unbinds an action.
  final void Function(A action) onUnbind;

  /// Called when the user resets an action to its default.
  final void Function(A action) onReset;

  /// Called (after the confirmation dialog) to reset every action to default.
  final VoidCallback onResetAll;

  /// Called when the user presses Import (the host runs the file flow).
  final VoidCallback onImport;

  /// Called when the user presses Export (the host runs the file flow).
  final VoidCallback onExport;

  /// Wraps each category's rows in the host's grouped-settings surface.
  final KeyBindingsCategoryCardBuilder categoryCardBuilder;

  /// Whether to render [KeyBindingsEditorStrings.phoneNote].
  final bool showPhoneNote;

  @override
  State<KeyBindingsEditor<A>> createState() => _KeyBindingsEditorState<A>();
}

class _KeyBindingsEditorState<A extends CruxAction>
    extends State<KeyBindingsEditor<A>> {
  /// The single action currently in key-capture mode, if any.
  ///
  /// Held in a [ValueNotifier] rather than in `setState` state: entering or
  /// leaving capture mode changes the appearance of at most two rows, but a
  /// `setState` here would re-group every action by category, re-derive every
  /// conflict string and rebuild every row. Each row listens for itself.
  final ValueNotifier<A?> _capturing = ValueNotifier<A?>(null);

  /// One focus node per row. Only the row that last had focus is in the Tab
  /// order; the arrow keys move between the others.
  final Map<A, FocusNode> _rowNodes = <A, FocusNode>{};

  /// The rows in on-screen order (category order, then action order).
  List<A> _order = <A>[];

  /// The row that holds the list's single Tab stop.
  A? _tabStop;

  @override
  void dispose() {
    _capturing.dispose();
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(A action) => _rowNodes.putIfAbsent(action, () {
    final node = FocusNode(debugLabel: 'Shortcut row');
    node.addListener(() {
      // Deferred: focus listeners run while the focus manager is still
      // iterating its dirty nodes, and changing `skipTraversal` marks nodes
      // dirty, which throws a concurrent modification there.
      if (node.hasPrimaryFocus) {
        scheduleMicrotask(() {
          if (mounted && node.hasPrimaryFocus) _moveTabStop(action);
        });
      }
    });
    return node;
  });

  void _moveTabStop(A action) {
    if (_tabStop == action) return;
    _rowNodes[_tabStop]?.skipTraversal = true;
    _tabStop = action;
    _rowNodes[action]?.skipTraversal = false;
  }

  void _syncRowNodes(List<A> order) {
    _order = order;
    final live = order.toSet();
    _rowNodes.removeWhere((action, node) {
      if (live.contains(action)) return false;
      node.dispose();
      return true;
    });
    if (_tabStop == null || !live.contains(_tabStop)) {
      _tabStop = order.isEmpty ? null : order.first;
    }
    for (final action in order) {
      _nodeFor(action).skipTraversal = action != _tabStop;
    }
  }

  void _focusRow(int Function(int from) to) {
    if (_order.isEmpty || _capturing.value != null) return;
    final stop = _tabStop;
    final from = stop == null ? 0 : _order.indexOf(stop);
    final index = to(from).clamp(0, _order.length - 1);
    final node = _rowNodes[_order[index]]!..requestFocus();
    final rowContext = node.context;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: index > from
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  /// Ends capture on [action] and, when focus was still in the capture
  /// field (a chord was pressed, or Escape), puts it back on the row. When
  /// capture ended because the user clicked elsewhere, focus stays there.
  void _endCapture(A action) {
    final primary = FocusManager.instance.primaryFocus;
    final restore =
        primary == null ||
        primary.context
                ?.findAncestorWidgetOfExactType<ShortcutCaptureField>() !=
            null;
    _capturing.value = null;
    if (!restore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rowNodes[action]?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = widget.strings;
    final grouped = _groupByCategory();
    final conflictChordCount = _conflictChordCount;
    _syncRowNodes(<A>[for (final actions in grouped.values) ...actions]);
    final hint = widget.accessibilityStrings?.keyboardHint;

    final rows = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _focusRow((i) => i + 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _focusRow((i) => i - 1),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            _focusRow((_) => 0),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _focusRow((_) => _order.length - 1),
      },
      child: Semantics(
        // Spoken once, when focus first enters the list.
        container: hint != null,
        explicitChildNodes: true,
        label: hint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final category in grouped.keys) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Text(
                  widget.categoryLabelOf(category),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              widget.categoryCardBuilder(context, [
                for (final action in grouped[category]!) _row(action),
              ]),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.showPhoneNote) ...[
                const SizedBox(height: 8),
                Text(
                  strings.phoneNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (hint != null) ...[
                const SizedBox(height: 8),
                // Visible for keyboard users who are not using a screen
                // reader; the list's container label speaks it for those who
                // are.
                ExcludeSemantics(
                  child: Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload_outlined),
                    label: Text(strings.importLabel),
                    onPressed: widget.onImport,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_download_outlined),
                    label: Text(strings.exportLabel),
                    onPressed: widget.onExport,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.settings_backup_restore),
                    label: Text(strings.resetAllLabel),
                    onPressed: _confirmResetAll,
                  ),
                ],
              ),
              if (conflictChordCount > 0) ...[
                const SizedBox(height: 12),
                _ConflictSummaryBanner(
                  message: widget.conflictMessages!.summary(
                    conflictChordCount,
                  ),
                  fontSize: widget.metrics.bodyFontSize,
                ),
              ],
            ],
          ),
        ),
        rows,
      ],
    );
  }

  /// Distinct conflicting chords, for the summary banner. Zero in legacy mode
  /// (no [KeyBindingsEditor.conflictDetails]).
  int get _conflictChordCount {
    final details = widget.conflictDetails;
    if (details == null) return 0;
    return details.values.map((e) => e.winner).toSet().length;
  }

  Widget _row(A action) {
    final detail = widget.conflictDetails?[action];
    String? conflictMessage;
    var conflictIsShadowed = false;
    if (detail != null) {
      // Asymmetric mode: the row either wins its chord (still fires) or is
      // shadowed by the winner (won't fire) — so the user can tell which row is
      // the interloper to fix.
      final messages = widget.conflictMessages!;
      if (detail.winner == action) {
        conflictMessage = messages.wins(
          detail.others.map(widget.labelOf).join(', '),
        );
      } else {
        conflictMessage = messages.shadowedBy(widget.labelOf(detail.winner));
        conflictIsShadowed = true;
      }
    } else {
      // Legacy symmetric mode.
      final others = widget.conflicts[action];
      if (others != null && others.isNotEmpty) {
        conflictMessage = widget.strings.conflict(
          others.map(widget.labelOf).join(', '),
        );
      }
    }

    // Everything except the capture field is independent of `_capturing`, so
    // it is resolved once here, during the editor's own build, and closed
    // over — a capture-mode change must not re-resolve labels or re-compare
    // bindings against defaults for every row in the list.
    final label = widget.labelOf(action);
    final activator = widget.bindings[action];
    final isCustomized = !KeyBindingResolver.activatorsEqual(
      activator,
      widget.defaults[action],
    );

    return ValueListenableBuilder<A?>(
      valueListenable: _capturing,
      builder: (context, capturing, _) => KeyBindingRow(
        label: label,
        activator: activator,
        metrics: widget.metrics,
        notBoundLabel: widget.strings.notBound,
        conflictMessage: conflictMessage,
        conflictIsShadowed: conflictIsShadowed,
        isCustomized: isCustomized,
        editTooltip: widget.strings.editTooltip,
        unbindTooltip: widget.strings.unbindTooltip,
        resetTooltip: widget.strings.resetTooltip,
        onEdit: () => _capturing.value = action,
        onUnbind: () => widget.onUnbind(action),
        onReset: () => widget.onReset(action),
        focusNode: _nodeFor(action),
        notBoundSpokenLabel: widget.accessibilityStrings?.notBoundSpoken,
        captureField: capturing == action
            ? ShortcutCaptureField(
                prompt: widget.strings.capturePrompt,
                metrics: widget.metrics,
                onCaptured: (binding) {
                  _endCapture(action);
                  widget.onCapture(action, binding);
                },
                onCancel: () => _endCapture(action),
              )
            : null,
      ),
    );
  }

  Map<ActionCategory, List<A>> _groupByCategory() {
    final grouped = <ActionCategory, List<A>>{};
    for (final action in widget.actions) {
      grouped.putIfAbsent(widget.categoryOf(action), () => []).add(action);
    }
    return grouped;
  }

  Future<void> _confirmResetAll() async {
    final strings = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.resetAllTitle),
        content: Text(strings.resetAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.resetAllCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.resetAllLabel),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.onResetAll();
  }
}

/// Always-visible summary shown above the list when one or more chords are in
/// conflict, so the user is alerted even when the affected rows are scrolled
/// out of view.
class _ConflictSummaryBanner extends StatelessWidget {
  const _ConflictSummaryBanner({required this.message, required this.fontSize});

  final String message;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: fontSize + 4,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: fontSize,
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
