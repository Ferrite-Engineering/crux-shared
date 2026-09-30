// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Maximum size of a [CruxSearchDialog] (the suite-standard search modal).
const Size kCruxSearchDialogSize = Size(560, 480);

/// Uniform result-row height inside a [CruxSearchDialog]. A fixed extent
/// lets arrow-key navigation scroll the highlighted row into view with
/// exact arithmetic instead of a per-row key lookup; a dense two-line
/// [ListTile] fits inside it.
const double kCruxSearchDialogRowExtent = 64;

/// Per-keystroke debounce for [CruxSearchDialog]. Host searches typically
/// walk a whole model synchronously, so running one on every keystroke
/// janks the UI on large inputs; bursts of typing coalesce into a single
/// search this long after the last keystroke.
const Duration kCruxSearchDebounceInterval = Duration(milliseconds: 200);

/// Builds one result row. [highlighted] is true for the row the keyboard
/// highlight sits on (the one Enter activates); [onActivate] applies the
/// result (the dialog pops itself afterwards). Hosts normally return a
/// [CruxSearchResultTile] so all four apps render identical rows.
typedef CruxSearchRowBuilder<T> =
    Widget Function(
      BuildContext context,
      T result, {
      required bool highlighted,
      required VoidCallback onActivate,
    });

/// The suite-standard search modal (Cmd/Ctrl+F): a query field with
/// debounced synchronous search, an optional host header (e.g. search-mode
/// chips), and a fixed-extent result list navigated with ↑/↓ and activated
/// with Enter while focus stays in the field.
///
/// The shell owns the query field, debounce, highlight tracking, keyboard
/// bindings, scroll-into-view math, and the empty state; the host supplies
/// [search] (query → results), [rowBuilder], and [onActivateResult]
/// (selection side effects — the shell pops the dialog afterwards).
///
/// [headerBuilder] receives a `refresh` callback: hosts whose external
/// search state changed (a mode chip toggled) call it to cancel any pending
/// debounce and re-run [search] with the current query immediately.
///
/// All strings are caller-supplied and already localized.
class CruxSearchDialog<T> extends StatefulWidget {
  /// Creates the suite-standard search dialog.
  const CruxSearchDialog({
    required this.title,
    required this.hintText,
    required this.emptyLabel,
    required this.search,
    required this.rowBuilder,
    required this.onActivateResult,
    this.headerBuilder,
    this.fieldKey,
    super.key,
  });

  /// Localized dialog title.
  final String title;

  /// Localized hint inside the query field.
  final String hintText;

  /// Localized "no matches" label, centered in the list area when a
  /// non-empty query has no results. (An empty query shows nothing.)
  final String emptyLabel;

  /// Runs the host's synchronous search for the current query and returns
  /// results in display order.
  final List<T> Function(String query) search;

  /// Builds one result row (see [CruxSearchRowBuilder]).
  final CruxSearchRowBuilder<T> rowBuilder;

  /// Applies the chosen result (selection/reveal side effects). The shell
  /// pops the dialog after this returns.
  final ValueChanged<T> onActivateResult;

  /// Optional row rendered between the title and the query field (e.g.
  /// search-mode chips). Call `refresh` after changing external search
  /// state so the visible results can't go stale.
  final Widget Function(BuildContext context, VoidCallback refresh)?
  headerBuilder;

  /// Optional key for the query [TextField] so hosts keep stable test keys.
  final Key? fieldKey;

  @override
  State<CruxSearchDialog<T>> createState() => _CruxSearchDialogState<T>();
}

class _CruxSearchDialogState<T> extends State<CruxSearchDialog<T>> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounce;
  List<T> _results = <T>[];
  String _lastQuery = '';

  /// Index into [_results] of the keyboard-highlighted row — the one Enter
  /// activates. Reset to the first row every time the result set changes.
  int _highlighted = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Handles text-field input. An empty query clears immediately (no work
  /// to debounce); a non-empty query schedules the search after
  /// [kCruxSearchDebounceInterval].
  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _runSearch(query);
      return;
    }
    _debounce = Timer(kCruxSearchDebounceInterval, () {
      if (!mounted) return;
      _runSearch(query);
    });
  }

  void _runSearch(String query) {
    final hits = widget.search(query);
    setState(() {
      _results = hits;
      _lastQuery = query;
      _highlighted = 0;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// The `refresh` callback handed to [CruxSearchDialog.headerBuilder]: a
  /// header toggle is a single deliberate action, so re-run immediately and
  /// drop any pending keystroke-debounced search so a stale query can't
  /// fire.
  void _refresh() {
    _debounce?.cancel();
    _runSearch(_controller.text);
  }

  /// Moves the keyboard highlight by [delta] rows, clamped to the result
  /// list, and scrolls the new row into view.
  void _moveHighlight(int delta) {
    if (_results.isEmpty) return;
    final next = (_highlighted + delta).clamp(0, _results.length - 1);
    if (next == _highlighted) return;
    setState(() => _highlighted = next);
    _revealHighlighted();
  }

  void _revealHighlighted() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final top = _highlighted * kCruxSearchDialogRowExtent;
    final bottom = top + kCruxSearchDialogRowExtent;
    final double target;
    if (top < position.pixels) {
      target = top;
    } else if (bottom > position.pixels + position.viewportDimension) {
      target = bottom - position.viewportDimension;
    } else {
      return;
    }
    _scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Enter handler. A pending debounce means the results on screen are
  /// stale relative to what is typed, so Enter runs that search now rather
  /// than jumping to a row the user cannot see yet; otherwise it activates
  /// the highlighted row.
  void _activateHighlighted() {
    if (_debounce?.isActive ?? false) {
      _debounce?.cancel();
      _runSearch(_controller.text);
      return;
    }
    if (_results.isEmpty) return;
    _activate(_results[_highlighted.clamp(0, _results.length - 1)]);
  }

  void _activate(T result) {
    widget.onActivateResult(result);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kCruxSearchDialogSize.width,
          maxHeight: kCruxSearchDialogSize.height,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          // Arrow keys move the highlight and Enter activates it while
          // focus stays in the query field. The bindings sit below the
          // app-level `DefaultTextEditingShortcuts`, which resolves from
          // the focused node outwards, so these win over the text field's
          // caret-movement and submit handling.
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _moveHighlight(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _moveHighlight(-1),
              const SingleActivator(LogicalKeyboardKey.enter):
                  _activateHighlighted,
              const SingleActivator(LogicalKeyboardKey.numpadEnter):
                  _activateHighlighted,
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(widget.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (widget.headerBuilder != null) ...<Widget>[
                  widget.headerBuilder!(context, _refresh),
                  const SizedBox(height: 8),
                ],
                TextField(
                  key: widget.fieldKey,
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: widget.hintText,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _results.isEmpty
                      ? _NoResultsView(
                          query: _lastQuery,
                          emptyLabel: widget.emptyLabel,
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _results.length,
                          itemExtent: kCruxSearchDialogRowExtent,
                          itemBuilder: (rowContext, i) => widget.rowBuilder(
                            rowContext,
                            _results[i],
                            highlighted: i == _highlighted,
                            onActivate: () => _activate(_results[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoResultsView extends StatelessWidget {
  const _NoResultsView({required this.query, required this.emptyLabel});

  final String query;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (query.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Text(
        emptyLabel,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The canonical [CruxSearchDialog] result row: a dense [ListTile] with the
/// keyboard highlight rendered as a `secondaryContainer` tint so the Enter
/// target is unambiguous without a pointer.
///
/// [trailingChipLabel], when set, renders the compact kind chip
/// (Instance / Cell / Net / Test / …) all suite search dialogs use.
class CruxSearchResultTile extends StatelessWidget {
  /// Creates the canonical search result row.
  const CruxSearchResultTile({
    required this.title,
    required this.highlighted,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.trailingChipLabel,
    super.key,
  });

  /// Primary label (result name), ellipsized.
  final String title;

  /// Optional secondary line (scope / suite / path), ellipsized.
  final String? subtitle;

  /// Optional leading icon widget.
  final Widget? leading;

  /// Optional localized label for the compact trailing kind chip.
  final String? trailingChipLabel;

  /// Whether the keyboard highlight sits on this row.
  final bool highlighted;

  /// Activates the result.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      selected: highlighted,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      selectedColor: theme.colorScheme.onSecondaryContainer,
      leading: leading,
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: trailingChipLabel == null
          ? null
          : Chip(
              label: Text(trailingChipLabel!),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            ),
      onTap: onTap,
    );
  }
}
