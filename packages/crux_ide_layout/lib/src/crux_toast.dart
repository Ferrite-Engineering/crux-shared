// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/src/crux_desktop_tokens.dart';
import 'package:flutter/material.dart';

/// The desktop toast stack behind `showCruxInfoSnack` / `showCruxErrorSnack`.
///
/// One toast is visible at a time, bottom-right above the status bar. A new
/// toast replaces the one showing. An info toast leaves after the
/// `infoDuration` given to [show]; an error toast stays until the user
/// closes it, because a failure that
/// vanishes while the user looks elsewhere was never reported.
///
/// The stack lives in the root [Overlay], keyed by that overlay, so a toast
/// raised from inside a dialog outlives the dialog and a second window's
/// overlay has its own stack.
abstract final class CruxToasts {
  static final Expando<_ToastStack> _stacks = Expando<_ToastStack>();

  /// Shows [message] as a toast over [context]'s root overlay. Returns false
  /// when there is no overlay to show it in.
  static bool show(
    BuildContext context,
    String message, {
    required bool error,
    required Duration infoDuration,
    Key? key,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    final tokens = CruxDesktopTokens.of(context) ?? const CruxDesktopTokens();
    (_stacks[overlay] ??= _ToastStack(overlay)).show(
      _ToastData(message: message, error: error, tokens: tokens, key: key),
      duration: error ? null : infoDuration,
    );
    return true;
  }

  /// Removes the toast showing over [context]'s root overlay, if any.
  static void hide(BuildContext context) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _stacks[overlay]?.hide();
  }
}

@immutable
class _ToastData {
  const _ToastData({
    required this.message,
    required this.error,
    required this.tokens,
    this.key,
  });

  final String message;
  final bool error;
  final CruxDesktopTokens tokens;
  final Key? key;
}

class _ToastStack {
  _ToastStack(this.overlay);

  final OverlayState overlay;
  OverlayEntry? _entry;
  Timer? _timer;

  void show(_ToastData data, {required Duration? duration}) {
    hide();
    final entry = OverlayEntry(
      builder: (context) => _ToastPositioned(data: data, onClose: hide),
    );
    _entry = entry;
    overlay.insert(entry);
    if (duration != null) _timer = Timer(duration, hide);
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    if (overlay.mounted) entry.remove();
    entry.dispose();
  }
}

class _ToastPositioned extends StatelessWidget {
  const _ToastPositioned({required this.data, required this.onClose});

  final _ToastData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = data.tokens;
    return Positioned(
      right: 16,
      bottom: tokens.toastBottomInset,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tokens.toastMaxWidth),
        child: CruxToastCard(
          key: data.key,
          message: data.message,
          error: data.error,
          onClose: data.error ? onClose : null,
        ),
      ),
    );
  }
}

/// The toast surface: an icon, the message and, for an error, a close
/// button. Exposed so a render check can draw it without the overlay.
class CruxToastCard extends StatelessWidget {
  /// Creates a toast card.
  const CruxToastCard({
    required this.message,
    required this.error,
    this.onClose,
    super.key,
  });

  /// The already-localized message.
  final String message;

  /// Whether this reports a failure.
  final bool error;

  /// Closes the toast; when null there is no close button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = CruxDesktopTokens.of(context) ?? const CruxDesktopTokens();
    final close = onClose;
    // One container named by the message, so a keyboard user who tabs to an
    // error toast's close button hears what it closes.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: message,
      child: _card(context, colorScheme, tokens, close),
    );
  }

  Widget _card(
    BuildContext context,
    ColorScheme colorScheme,
    CruxDesktopTokens tokens,
    VoidCallback? close,
  ) {
    return Material(
      key: const ValueKey('cruxToast'),
      color: colorScheme.surfaceContainerHighest,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.menuRadius),
        side: BorderSide(
          color: error ? colorScheme.error : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, close == null ? 12 : 4, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(
                error ? Icons.error_outline : Icons.info_outline,
                size: 16,
                color: error ? colorScheme.error : colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: ExcludeSemantics(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: tokens.bodyFontSize,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            if (close != null) ...<Widget>[
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('cruxToastClose'),
                icon: const Icon(Icons.close, size: 14),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: close,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
