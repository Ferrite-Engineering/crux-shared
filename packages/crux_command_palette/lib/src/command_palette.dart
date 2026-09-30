// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Number of times the palette has scored a candidate action since the last
/// [debugResetCommandPaletteScoreCount] call.
///
/// The palette scores each surviving candidate exactly once per distinct
/// query and caches the ordered result, so this counter stays flat while the
/// user moves the selection with ↑/↓. Tests assert both properties; nothing
/// in production reads it.
@visibleForTesting
int debugCommandPaletteScoreCount = 0;

/// Resets [debugCommandPaletteScoreCount] to zero.
@visibleForTesting
void debugResetCommandPaletteScoreCount() {
  debugCommandPaletteScoreCount = 0;
}

/// `debugLabel` of the [Focus] node that owns the palette's ↑/↓/Enter/Escape
/// handling. Tests locate the node by this label; nothing in production reads
/// it.
@visibleForTesting
const commandPaletteKeyHandlerDebugLabel = 'CommandPalette keys';

/// Builder that wraps the palette's inner scrolling list with a
/// product-specific scroll-event listener (e.g. trackpad-pointer-pan
/// forwarders, mouse-wheel acceleration handlers).
typedef ScrollWrapperBuilder =
    Widget Function(
      BuildContext context,
      ScrollController controller,
      Widget child,
    );

/// Renders a [ShortcutActivator] as a short human-readable string
/// (e.g. `"⌘ P"`, `"Ctrl+Shift+P"`). Callers supply this so the widget
/// stays decoupled from product-specific shortcut display conventions.
typedef ShortcutActivatorLabel = String Function(ShortcutActivator? activator);

/// VS Code-style command palette overlay.
///
/// Lists [actions] with their localized labels and (optional) keyboard
/// shortcuts. Typing filters with fuzzy matching; ↑/↓ navigate the list;
/// Enter executes the selected action; Escape dismisses.
///
/// The widget is type-parameterized over each product's specific
/// [CruxAction] subtype so dispatch stays type-safe — every product supplies
/// its own action enum.
///
/// Everything product-specific is caller-supplied:
///
/// - The visible action list (caller pre-filters for app state, license
///   tier, device class).
/// - Action label resolution via [labelFor] — usually `(a) => a.label(l10n)`.
/// - Search-field hint and no-results text — caller-localized.
/// - Optional keyboard [bindings] for the per-row shortcut hint.
/// - Optional [activatorLabel] formatter and [scrollWrapperBuilder].
class CommandPalette<T extends CruxAction> extends StatefulWidget {
  /// Creates a command palette widget. Use [CommandPalette.show] when you
  /// want the dialog framing for free.
  const CommandPalette({
    required this.actions,
    required this.labelFor,
    required this.onAction,
    required this.hintText,
    required this.noResultsLabel,
    this.bindings = const {},
    this.activatorLabel,
    this.scrollWrapperBuilder,
    this.trailingBuilder,
    super.key,
  });

  /// Actions to display, in caller-decided order. Empty list shows the
  /// [noResultsLabel] placeholder.
  final List<T> actions;

  /// Maps an action to its localized label.
  final String Function(T) labelFor;

  /// Called after the dialog dismisses with the selected action.
  final void Function(T) onAction;

  /// Placeholder text in the search field.
  final String hintText;

  /// Shown when the typed query filters every action out of the list.
  final String noResultsLabel;

  /// Optional keyboard-shortcut bindings rendered to the right of each row.
  /// Pass an empty map to suppress the shortcut column.
  final Map<T, ShortcutActivator?> bindings;

  /// Optional formatter for the per-row shortcut hint. Defaults to
  /// [defaultShortcutActivatorLabel] (Material-style with `+` separators).
  final ShortcutActivatorLabel? activatorLabel;

  /// Optional wrapper around the inner scrolling list. Use to attach
  /// product-specific scroll-event listeners.
  final ScrollWrapperBuilder? scrollWrapperBuilder;

  /// Optional builder for a small trailing widget rendered before the
  /// keyboard-shortcut hint on each row — used by products to show a
  /// per-action badge (e.g. a license-tier chip). Return `null` for actions
  /// that need no trailing widget.
  final Widget? Function(T action)? trailingBuilder;

  /// Shows the palette as a centered modal dialog. The returned future
  /// completes when the dialog dismisses (after the [onAction] callback has
  /// fired, if an action was picked).
  static Future<void> show<T extends CruxAction>(
    BuildContext context, {
    required List<T> actions,
    required String Function(T) labelFor,
    required void Function(T) onAction,
    required String hintText,
    required String noResultsLabel,
    Map<T, ShortcutActivator?> bindings = const {},
    ShortcutActivatorLabel? activatorLabel,
    ScrollWrapperBuilder? scrollWrapperBuilder,
    Widget? Function(T action)? trailingBuilder,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPalette<T>(
        actions: actions,
        labelFor: labelFor,
        onAction: onAction,
        hintText: hintText,
        noResultsLabel: noResultsLabel,
        bindings: bindings,
        activatorLabel: activatorLabel,
        scrollWrapperBuilder: scrollWrapperBuilder,
        trailingBuilder: trailingBuilder,
      ),
    );
  }

  @override
  State<CommandPalette<T>> createState() => _CommandPaletteState<T>();
}

class _CommandPaletteState<T extends CruxAction>
    extends State<CommandPalette<T>> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// Focus node for the outer key-handling [Focus]. Held as a field rather
  /// than constructed in `build` so it survives rebuilds and is disposed once.
  final _keyboardFocusNode = FocusNode(debugLabel: 'CommandPalette keyboard');

  var _query = '';
  var _selectedIndex = 0;

  /// Set once the palette has popped its route, so a second signal for the
  /// same gesture is a no-op.
  ///
  /// Enter reaches the palette by two independent routes, both deliberately
  /// wired (see [_SearchField.onSubmitted]): as a [KeyDownEvent] on platforms
  /// that deliver it to the framework, and as a text-input *done* action on
  /// platforms whose engine translates Enter for the focused field before the
  /// framework ever sees a key event. Whichever arrives first wins. Without
  /// this latch a platform that delivers both would pop twice — taking the
  /// route underneath the palette with it — and dispatch the action twice.
  var _closed = false;

  static const _itemHeight = 44.0;
  static const _maxVisibleItems = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── filtering ──────────────────────────────────────────────────────────

  /// Query that produced [_cachedResults], or `null` when the cache is cold.
  String? _cachedQuery;

  /// The `widget.actions` list [_cachedResults] was derived from. Compared by
  /// identity so a caller handing back the same list keeps the cache warm.
  List<T>? _cachedSource;

  List<T>? _cachedResults;

  /// Scores [label] against the already-lowercased [lowerQuery].
  ///
  /// Returns `null` when [label] is not a match at all — every character of
  /// the query must appear in the label in order. Otherwise the return value
  /// orders results, higher first: an exact match beats a prefix match beats
  /// a substring match beats the longest run of consecutive matched
  /// characters.
  ///
  /// Scans with `codeUnitAt` rather than `operator []`, which would allocate
  /// a one-character String per index.
  static int? _scoreLabel(String lowerQuery, String label) {
    debugCommandPaletteScoreCount++;
    final t = label.toLowerCase();
    final qLen = lowerQuery.length;

    var consecutive = 0;
    var maxRun = 0;
    var qi = 0;
    for (var i = 0; i < t.length && qi < qLen; i++) {
      if (t.codeUnitAt(i) == lowerQuery.codeUnitAt(qi)) {
        qi++;
        consecutive++;
        if (consecutive > maxRun) maxRun = consecutive;
      } else {
        consecutive = 0;
      }
    }
    if (qi != qLen) return null;

    if (t.length == qLen && t == lowerQuery) return 100;
    if (t.startsWith(lowerQuery)) return 80;
    if (t.contains(lowerQuery)) return 60;
    return maxRun;
  }

  /// Filters and orders [CommandPalette.actions] against the current query.
  ///
  /// Scores each candidate exactly once (decorate–sort–undecorate) and caches
  /// the result, so rebuilds that leave the query untouched — moving the
  /// selection with ↑/↓, a theme change, a parent rebuild — reuse it.
  List<T> _filteredActions() {
    final source = widget.actions;
    if (_cachedQuery == _query && identical(_cachedSource, source)) {
      return _cachedResults!;
    }

    final List<T> result;
    if (_query.isEmpty) {
      result = source;
    } else {
      final lowerQuery = _query.toLowerCase();
      final scored = <({int score, T action})>[];
      for (final action in source) {
        final score = _scoreLabel(lowerQuery, widget.labelFor(action));
        if (score != null) scored.add((score: score, action: action));
      }
      scored.sort((a, b) => b.score.compareTo(a.score));
      result = [for (final entry in scored) entry.action];
    }

    _cachedQuery = _query;
    _cachedSource = source;
    _cachedResults = result;
    return result;
  }

  @override
  void didUpdateWidget(CommandPalette<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.actions, widget.actions) ||
        oldWidget.labelFor != widget.labelFor) {
      _cachedQuery = null;
      _cachedSource = null;
      _cachedResults = null;
    }
  }

  // ── keyboard navigation ─────────────────────────────────────────────────

  void _moveSelection(int delta, int total) {
    if (total == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, total - 1);
    });
    _scrollToSelected();
  }

  void _scrollToSelected() {
    final offset = _selectedIndex * _itemHeight;
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final current = _scrollController.offset;
    if (offset < current) {
      _scrollController.jumpTo(offset);
    } else if (offset + _itemHeight > current + viewport) {
      _scrollController.jumpTo(offset + _itemHeight - viewport);
    }
  }

  void _execute(List<T> actions) {
    if (_closed || actions.isEmpty) return;
    final action = actions[_selectedIndex.clamp(0, actions.length - 1)];
    _closed = true;
    Navigator.of(context).pop();
    widget.onAction(action);
  }

  /// Closes the palette without dispatching anything.
  void _dismiss() {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  /// Handles the four keys the palette owns, reporting them as consumed.
  ///
  /// Consuming matters as much as handling: an unconsumed ↑/↓ keeps
  /// travelling up the focus chain to the platform text-editing shortcuts and
  /// moves the query field's caret at the same time as the highlight, and an
  /// unconsumed Escape reaches the enclosing [ModalRoute] and pops a *second*
  /// route out from under the palette.
  KeyEventResult _handleKeyEvent(KeyEvent event, List<T> actions) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, actions.length);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, actions.length);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _execute(actions);
    } else if (key == LogicalKeyboardKey.escape) {
      _dismiss();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actions = _filteredActions();
    final formatter = widget.activatorLabel ?? defaultShortcutActivatorLabel;

    return Focus(
      focusNode: _keyboardFocusNode,
      debugLabel: commandPaletteKeyHandlerDebugLabel,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event, actions),
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 8,
                color: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SearchField(
                      controller: _controller,
                      focusNode: _focusNode,
                      hint: widget.hintText,
                      onChanged: (v) => setState(() {
                        _query = v;
                        _selectedIndex = 0;
                      }),
                      onSubmitted: (_) => _execute(actions),
                    ),
                    const Divider(height: 1),
                    _ResultsList<T>(
                      actions: actions,
                      selectedIndex: _selectedIndex,
                      scrollController: _scrollController,
                      bindings: widget.bindings,
                      itemHeight: _itemHeight,
                      maxVisibleItems: _maxVisibleItems,
                      noResultsLabel: widget.noResultsLabel,
                      labelFor: widget.labelFor,
                      activatorLabel: formatter,
                      scrollWrapperBuilder: widget.scrollWrapperBuilder,
                      trailingBuilder: widget.trailingBuilder,
                      onTap: (index) {
                        setState(() => _selectedIndex = index);
                        _execute(actions);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── sub-widgets ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;

  /// Runs the highlighted action when the *engine* finalizes editing.
  ///
  /// This is the path a real Enter keypress takes on every platform whose
  /// embedder owns the focused field's text-input connection: the engine
  /// translates the keystroke into a `TextInputAction.done` on the text-input
  /// channel and the framework never sees a `KeyDownEvent`. Handling Enter
  /// only in an ancestor key listener is therefore not enough — that is
  /// precisely how keyboard execution came to be dead in shipped desktop
  /// builds while widget tests, which deliver synthetic key events, stayed
  /// green.
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, size: 20),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

class _ResultsList<T extends CruxAction> extends StatelessWidget {
  const _ResultsList({
    required this.actions,
    required this.selectedIndex,
    required this.scrollController,
    required this.bindings,
    required this.itemHeight,
    required this.maxVisibleItems,
    required this.noResultsLabel,
    required this.labelFor,
    required this.activatorLabel,
    required this.scrollWrapperBuilder,
    required this.trailingBuilder,
    required this.onTap,
  });

  final List<T> actions;
  final int selectedIndex;
  final ScrollController scrollController;
  final Map<T, ShortcutActivator?> bindings;
  final double itemHeight;
  final int maxVisibleItems;
  final String noResultsLabel;
  final String Function(T) labelFor;
  final ShortcutActivatorLabel activatorLabel;
  final ScrollWrapperBuilder? scrollWrapperBuilder;
  final Widget? Function(T action)? trailingBuilder;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          noResultsLabel,
          // `onSurfaceVariant`, not `outline`. Material's `outline` is a
          // BORDER token — it is specified against decorative separators, not
          // against text, and using it here measured 4.26:1 in light theme
          // against WCAG AA's 4.5:1 for this 14 pt string.
          //
          // Marginal, and exactly the kind of thing nobody catches by eye —
          // which is why it stood until the accessibility guard landed. This
          // is also the state a user reaches by MISTYPING, so it is read more
          // often than its prominence suggests.
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final visibleHeight = actions.length.clamp(1, maxVisibleItems) * itemHeight;

    final listView = ListView.builder(
      controller: scrollController,
      itemCount: actions.length,
      itemExtent: itemHeight,
      itemBuilder: (context, index) {
        final action = actions[index];
        final isSelected = index == selectedIndex;
        final shortcutText = activatorLabel(bindings[action]);
        return _CommandItem(
          label: labelFor(action),
          shortcut: shortcutText,
          trailing: trailingBuilder?.call(action),
          isSelected: isSelected,
          onTap: () => onTap(index),
        );
      },
    );

    return SizedBox(
      height: visibleHeight,
      child: scrollWrapperBuilder != null
          ? scrollWrapperBuilder!(context, scrollController, listView)
          : listView,
    );
  }
}

class _CommandItem extends StatelessWidget {
  const _CommandItem({
    required this.label,
    required this.shortcut,
    required this.trailing,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String shortcut;
  final Widget? trailing;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (shortcut.isNotEmpty) ...[
              const SizedBox(width: 16),
              Text(
                shortcut,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Default Material-style activator label formatter. Returns an empty
/// string for `null` activators (no shortcut bound). Renders modifier keys
/// in a fixed `Ctrl Alt Shift Cmd Key` order.
///
/// Callers wanting platform-specific glyphs (e.g. `⌘` on macOS, `⊞` on
/// Windows) can supply their own [ShortcutActivatorLabel] formatter.
String defaultShortcutActivatorLabel(ShortcutActivator? activator) {
  if (activator is! SingleActivator) return '';
  final parts = <String>[];
  if (activator.control) parts.add('Ctrl');
  if (activator.alt) parts.add('Alt');
  if (activator.shift) parts.add('Shift');
  if (activator.meta) parts.add('Cmd');
  parts.add(_keyLabel(activator.trigger));
  return parts.join('+');
}

String _keyLabel(LogicalKeyboardKey key) {
  final label = key.keyLabel;
  if (label.isNotEmpty) return label;
  return key.debugName ?? '?';
}
