// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Commits the inline editor. Its own Intent type rather than a reused one so
/// the Enter binding cannot collide with anything the surrounding app maps.
class _CommitIntent extends Intent {
  const _CommitIntent();
}

/// The in-place text field a callout's text is edited in.
///
/// Inline rather than a modal dialog: annotating is something a user does
/// many times in a row while reading a canvas, and a dialog per note breaks
/// that rhythm. Enter commits, Shift+Enter inserts a line break, Escape
/// reverts to [initialText], and losing focus commits: walking away keeps what
/// was typed. [onCommit] is called exactly once.
class CruxCalloutInlineEditor extends StatefulWidget {
  /// Creates the editor. It takes focus after its first frame.
  const CruxCalloutInlineEditor({
    required this.initialText,
    required this.hint,
    required this.color,
    required this.onCommit,
    required this.maxLength,
    super.key,
  });

  /// The text the field opens with, and what Escape commits.
  final String initialText;

  /// The placeholder shown while the field is empty.
  final String hint;

  /// The text colour.
  final Color color;

  /// Receives the trimmed text on commit, or [initialText] on Escape.
  final void Function(String text) onCommit;

  /// The product's bound on a note's text, enforced while typing.
  final int maxLength;

  @override
  State<CruxCalloutInlineEditor> createState() =>
      _CruxCalloutInlineEditorState();
}

class _CruxCalloutInlineEditorState extends State<CruxCalloutInlineEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final FocusNode _focus = FocusNode();
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    if (_committed) return;
    _committed = true;
    widget.onCommit(_controller.text.trim());
  }

  void _cancel() {
    if (_committed) return;
    _committed = true;
    // Commits the text the note already had, so Escape reverts the edit
    // rather than deleting a note that previously said something.
    widget.onCommit(widget.initialText);
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    // A multi-line TextField never fires onSubmitted (Enter inserts a
    // newline), so binding the key explicitly is the only way to keep "type
    // and press Enter" working while still allowing a two-line note.
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      SingleActivator(LogicalKeyboardKey.enter): _CommitIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): _CommitIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            _cancel();
            return null;
          },
        ),
        _CommitIntent: CallbackAction<_CommitIntent>(
          onInvoke: (_) {
            _commit();
            return null;
          },
        ),
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: 4,
        minLines: 1,
        maxLength: widget.maxLength,
        style: TextStyle(fontSize: 11, height: 1.25, color: widget.color),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          counterText: '',
          hintText: widget.hint,
          hintStyle: TextStyle(
            fontSize: 11,
            color: widget.color.withValues(alpha: 0.45),
          ),
        ),
        onSubmitted: (_) => _commit(),
      ),
    ),
  );
}
