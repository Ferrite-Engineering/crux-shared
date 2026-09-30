// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Builds the scroll view inside a [CruxScrollRegion], wired to [controller].
typedef CruxScrollRegionBuilder =
    Widget Function(BuildContext context, ScrollController controller);

/// A scrolling block of text that a keyboard can reach and scroll: one Tab
/// stop, announced by name, that scrolls with the arrow keys, Page Up and Page
/// Down, Home and End.
///
/// A scroll view of plain text has nothing focusable in it, so Tab passes it
/// by and a keyboard user can neither read past the first screenful nor tell
/// that there is more. This makes the region itself the stop. It draws a
/// focus outline while focused, and moves the scroll view the builder wires
/// to its controller.
///
/// A screen reader hears [semanticLabel] as the stop's name. With
/// [excludeContentSemantics] the label *is* the content, and nothing below it
/// is announced separately: right for a short passage whose text can be the
/// label. Without it the label names the region and the content stays
/// readable node by node: right for a long document.
///
/// The keys are bound here rather than left to the app's defaults, which bind
/// the arrow keys to scrolling on desktop only and act on the nearest scroll
/// view, which for a region inside a scrolling dialog is the dialog's own.
class CruxScrollRegion extends StatefulWidget {
  /// Creates a keyboard-scrollable region around the scroll view [builder]
  /// returns.
  const CruxScrollRegion({
    required this.semanticLabel,
    required this.builder,
    this.excludeContentSemantics = false,
    this.autofocus = false,
    super.key,
  });

  /// The name a screen reader announces when the region takes focus.
  final String semanticLabel;

  /// Returns the scroll view. It must use the controller it is given, or the
  /// keys scroll nothing.
  final CruxScrollRegionBuilder builder;

  /// Whether [semanticLabel] replaces the content's own semantics.
  final bool excludeContentSemantics;

  /// Whether the region takes focus when it first appears.
  final bool autofocus;

  @override
  State<CruxScrollRegion> createState() => _CruxScrollRegionState();
}

class _CruxScrollRegionState extends State<CruxScrollRegion> {
  final ScrollController _controller = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'CruxScrollRegion');
  bool _focused = false;

  static const Map<ShortcutActivator, Intent> _keys =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _ScrollBy(_Step.line, 1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _ScrollBy(_Step.line, -1),
        SingleActivator(LogicalKeyboardKey.pageDown): _ScrollBy(_Step.page, 1),
        SingleActivator(LogicalKeyboardKey.pageUp): _ScrollBy(_Step.page, -1),
        SingleActivator(LogicalKeyboardKey.end): _ScrollBy(_Step.edge, 1),
        SingleActivator(LogicalKeyboardKey.home): _ScrollBy(_Step.edge, -1),
      };

  /// One line: the same increment the framework's `ScrollAction` uses.
  static const double _lineStep = 50;

  void _scroll(_ScrollBy intent) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final double target;
    switch (intent.step) {
      case _Step.line:
        target = position.pixels + intent.direction * _lineStep;
      case _Step.page:
        target =
            position.pixels +
            intent.direction * position.viewportDimension * .8;
      case _Step.edge:
        target = intent.direction < 0
            ? position.minScrollExtent
            : position.maxScrollExtent;
    }
    _controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.primary;
    return Actions(
      actions: <Type, Action<Intent>>{
        _ScrollBy: CallbackAction<_ScrollBy>(onInvoke: _scroll),
      },
      child: Shortcuts(
        shortcuts: _keys,
        child: Focus(
          focusNode: _focus,
          autofocus: widget.autofocus,
          includeSemantics: false,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: Semantics(
            container: true,
            explicitChildNodes: !widget.excludeContentSemantics,
            excludeSemantics: widget.excludeContentSemantics,
            label: widget.semanticLabel,
            focusable: true,
            focused: _focused,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _focused ? outline : Colors.transparent,
                  width: 2,
                ),
              ),
              child: widget.builder(context, _controller),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { line, page, edge }

class _ScrollBy extends Intent {
  const _ScrollBy(this.step, this.direction);

  final _Step step;

  /// `1` toward the end of the content, `-1` toward the start.
  final int direction;
}
