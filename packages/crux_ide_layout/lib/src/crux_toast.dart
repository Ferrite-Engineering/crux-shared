// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/src/crux_desktop_tokens.dart';
import 'package:crux_ide_layout/src/debug_stderr_stub.dart'
    if (dart.library.io) 'package:crux_ide_layout/src/debug_stderr_io.dart';
import 'package:crux_ide_layout/src/feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
///
/// A toast may carry one [CruxToastAction] (Undo, Show). It is drawn as a
/// text button, reachable with Tab like the error toast's close button, and
/// invoking it closes the toast. An info toast that carries an action stays
/// for the longer duration its caller gives and never leaves while the
/// pointer is over it or focus is in it.
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
    CruxToastAction? action,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    _ensureHost(overlay);
    final tokens = CruxDesktopTokens.of(context) ?? const CruxDesktopTokens();
    (_stacks[overlay] ??= _ToastStack(overlay)).show(
      _ToastData(
        message: message,
        error: error,
        tokens: tokens,
        key: key,
        action: action,
      ),
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

  /// Shows [message] as an informational toast without a [BuildContext], for
  /// feedback raised after the widget that caused it is gone: a context menu
  /// that has closed, a background re-run that fails after its panel
  /// unmounted.
  ///
  /// It behaves exactly like `showCruxInfoSnack` called from the host's own
  /// context: one toast at a time with the newest replacing the one showing,
  /// the same duration, [action] and focus behaviour, and a polite
  /// announcement.
  ///
  /// The host is a root overlay that a `CruxIdeLayout` is mounted under, or
  /// that has shown a toast through `showCruxInfoSnack` / `showCruxErrorSnack`.
  /// When more than one exists (several windows), the one whose focus
  /// changed most recently wins; a host registered but never focused ranks by
  /// when it registered.
  ///
  /// Returns true when the toast was shown. Returns false, and never throws,
  /// when no host is registered, the host's theme is not a Crux Desktop theme
  /// (the phone and tablet path, which has no toast stack), or the host has no
  /// overlay. A debug build also writes a line to standard error.
  static bool showInfo(String message, {CruxToastAction? action, Key? key}) =>
      _showWithoutContext(
        (_) => message,
        plain: message,
        error: false,
        action: action == null ? null : (_) => action,
        key: key,
      );

  /// Shows [message] as an error toast without a [BuildContext]. As
  /// [showInfo], with the error behaviour of `showCruxErrorSnack`: it stays
  /// until the user closes it or a newer toast replaces it, and it is
  /// announced assertively.
  static bool showError(String message, {CruxToastAction? action, Key? key}) =>
      _showWithoutContext(
        (_) => message,
        plain: message,
        error: true,
        action: action == null ? null : (_) => action,
        key: key,
      );

  /// As [showError], with the message and the action built from the host's
  /// context, so their words follow the host window's locale: for feedback
  /// raised where no context is at hand that still has to be localized (a
  /// link no browser opened, from a launcher seam).
  static bool showErrorFor(
    String Function(BuildContext context) message, {
    CruxToastAction Function(BuildContext context)? action,
    Key? key,
  }) => _showWithoutContext(message, error: true, action: action, key: key);

  static bool _showWithoutContext(
    String Function(BuildContext context) messageFor, {
    required bool error,
    required CruxToastAction Function(BuildContext context)? action,
    required Key? key,
    String plain = '',
  }) {
    var message = plain;
    try {
      final overlay = _mostRecentlyFocusedHost();
      if (overlay == null) {
        _noHost(message, 'no toast host is registered');
        return false;
      }
      // The overlay's own context sits above its entries, so it carries the
      // theme, the locale and the view the toast and its announcement need.
      final context = overlay.context;
      message = messageFor(context);
      final tokens = CruxDesktopTokens.of(context);
      if (tokens == null) {
        _noHost(message, 'the host theme is not a Crux Desktop theme');
        return false;
      }
      final toastAction = action?.call(context);
      (_stacks[overlay] ??= _ToastStack(overlay)).show(
        _ToastData(
          message: message,
          error: error,
          tokens: tokens,
          key: key,
          action: toastAction,
        ),
        duration: error
            ? null
            : (toastAction == null
                  ? kCruxInfoSnackDuration
                  : kCruxActionSnackDuration),
      );
      final spoken = toastAction == null
          ? message
          : '$message ${toastAction.label}';
      announceCrux(context, spoken, assertive: error);
      return true;
    } on Object catch (e) {
      _noHost(message, 'failed: $e');
      return false;
    }
  }

  static void _noHost(String message, String why) {
    if (!kDebugMode) return;
    writeDebugStderr('CruxToasts: toast not shown ($why): $message');
  }
}

class _Host {
  _Host(this.overlay, this.stamp);

  final OverlayState overlay;
  int stamp;

  /// Widgets holding this host open; a host with none stays until its
  /// overlay is gone.
  int holds = 0;
}

final List<_Host> _hosts = <_Host>[];
int _clock = 0;
bool _listening = false;

/// Registers the root overlay above [context] as a toast host and returns the
/// call that removes it.
///
/// Called by the widget that owns the window's chrome, and by every context
/// toast, so a window that has shown one is a host from then on. Registering
/// an overlay that is already a host changes nothing. Not exported from the
/// package.
VoidCallback registerCruxToastHost(BuildContext context) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return () {};
  final host = _ensureHost(overlay);
  host.holds++;
  var released = false;
  return () {
    if (released) return;
    released = true;
    host.holds--;
    if (host.holds <= 0) _hosts.remove(host);
    _stopListeningIfIdle();
  };
}

_Host _ensureHost(OverlayState overlay) {
  for (final host in _hosts) {
    if (identical(host.overlay, overlay)) return host;
  }
  final host = _Host(overlay, ++_clock);
  _hosts.add(host);
  if (!_listening) {
    _listening = true;
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
  }
  return host;
}

void _stopListeningIfIdle() {
  if (_hosts.isEmpty && _listening) {
    _listening = false;
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
  }
}

void _onPrimaryFocusChanged() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null || !focused.mounted) return;
  final overlay = Overlay.maybeOf(focused, rootOverlay: true);
  if (overlay == null) return;
  for (final host in _hosts) {
    if (identical(host.overlay, overlay)) host.stamp = ++_clock;
  }
}

OverlayState? _mostRecentlyFocusedHost() {
  _hosts.removeWhere((h) => !h.overlay.mounted);
  _stopListeningIfIdle();
  _Host? best;
  for (final host in _hosts) {
    if (best == null || host.stamp > best.stamp) best = host;
  }
  return best?.overlay;
}

/// The one action a toast can offer: a short, already-localized [label]
/// ("Undo") and what it does. Invoking it closes the toast.
@immutable
class CruxToastAction {
  /// Creates an action.
  const CruxToastAction({required this.label, required this.onPressed});

  /// The button's label, also its accessible name.
  final String label;

  /// Runs when the action is chosen, after which the toast closes.
  final VoidCallback onPressed;
}

@immutable
class _ToastData {
  const _ToastData({
    required this.message,
    required this.error,
    required this.tokens,
    this.key,
    this.action,
  });

  final String message;
  final bool error;
  final CruxDesktopTokens tokens;
  final Key? key;
  final CruxToastAction? action;
}

class _ToastStack {
  _ToastStack(this.overlay);

  final OverlayState overlay;
  OverlayEntry? _entry;
  Timer? _timer;
  Duration? _duration;

  /// Whether the pointer or focus is in the toast, which holds it up.
  final ValueNotifier<bool> _held = ValueNotifier<bool>(false);

  void show(_ToastData data, {required Duration? duration}) {
    hide();
    _duration = duration;
    final entry = OverlayEntry(
      builder: (context) =>
          _ToastPositioned(data: data, onClose: hide, held: _held),
    );
    _entry = entry;
    overlay.insert(entry);
    _held
      ..value = false
      ..addListener(_onHeldChanged);
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    final duration = _duration;
    if (duration == null || _held.value) return;
    _timer = Timer(duration, hide);
  }

  void _onHeldChanged() {
    if (_held.value) {
      _timer?.cancel();
      _timer = null;
    } else {
      // Released: the full duration again, so a toast is never snatched the
      // moment the pointer leaves it.
      _arm();
    }
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    _held.removeListener(_onHeldChanged);
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    if (overlay.mounted) entry.remove();
    entry.dispose();
  }
}

/// Places the toast and keeps its close button in the Tab order the user is
/// walking.
///
/// The toast's overlay entry sits outside every route, so its focus node is
/// a child of the navigator's own scope. A modal route traps Tab inside its
/// scope, which left an error toast's close button unreachable from the
/// keyboard while a dialog was open. The toast therefore re-parents its
/// focus node under the scope that holds the primary focus, following it as
/// dialogs open and close, so Tab reaches the close button from the page and
/// from inside a modal alike.
class _ToastPositioned extends StatefulWidget {
  const _ToastPositioned({
    required this.data,
    required this.onClose,
    required this.held,
  });

  final _ToastData data;
  final VoidCallback onClose;
  final ValueNotifier<bool> held;

  @override
  State<_ToastPositioned> createState() => _ToastPositionedState();
}

class _ToastPositionedState extends State<_ToastPositioned> {
  final FocusNode _anchor = FocusNode(
    debugLabel: 'cruxToastAnchor',
    canRequestFocus: false,
    skipTraversal: true,
  );
  FocusScopeNode? _parent;
  bool _hovered = false;
  bool _focused = false;

  void _updateHeld() {
    final held = _hovered || _focused;
    if (widget.held.value == held) return;
    widget.held.value = held;
  }

  @override
  void initState() {
    super.initState();
    _parent = _activeScope();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _anchor.dispose();
    super.dispose();
  }

  /// The scope the user is tabbing in, or null to keep the natural parent.
  /// Focus on the toast itself keeps the current parent.
  FocusScopeNode? _activeScope() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return _parent;
    if (primary == _anchor || primary.ancestors.contains(_anchor)) {
      return _parent;
    }
    final scope = primary.nearestScope;
    if (scope == null || !_isLive(scope)) return _parent;
    return scope;
  }

  static bool _isLive(FocusNode node) => node.context?.mounted ?? false;

  void _onFocusChanged() {
    if (!mounted) return;
    final next = _activeScope();
    if (identical(next, _parent)) return;
    void apply() {
      if (!mounted) return;
      setState(() => _parent = next);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final tokens = data.tokens;
    final parent = _parent;
    final action = data.action;
    return Positioned(
      right: 16,
      bottom: tokens.toastBottomInset,
      child: MouseRegion(
        onEnter: (_) {
          _hovered = true;
          _updateHeld();
        },
        onExit: (_) {
          _hovered = false;
          _updateHeld();
        },
        child: Focus(
          focusNode: _anchor,
          parentNode: parent != null && _isLive(parent) ? parent : null,
          includeSemantics: false,
          onFocusChange: (focused) {
            _focused = focused;
            _updateHeld();
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tokens.toastMaxWidth),
            child: CruxToastCard(
              key: data.key,
              message: data.message,
              error: data.error,
              onClose: data.error ? widget.onClose : null,
              action: action,
              onAction: action == null
                  ? null
                  : () {
                      widget.onClose();
                      action.onPressed();
                    },
            ),
          ),
        ),
      ),
    );
  }
}

/// The toast surface: an icon, the message, an optional action and, for an
/// error, a close button. Exposed so a render check can draw it without the
/// overlay.
class CruxToastCard extends StatelessWidget {
  /// Creates a toast card.
  const CruxToastCard({
    required this.message,
    required this.error,
    this.onClose,
    this.action,
    this.onAction,
    super.key,
  });

  /// The already-localized message.
  final String message;

  /// Whether this reports a failure.
  final bool error;

  /// Closes the toast; when null there is no close button.
  final VoidCallback? onClose;

  /// The toast's action, drawn as a text button; null for none.
  final CruxToastAction? action;

  /// Runs when [action] is chosen; defaults to the action's own callback.
  final VoidCallback? onAction;

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
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          close == null && action == null ? 12 : 4,
          8,
        ),
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
            if (action case final CruxToastAction action) ...<Widget>[
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('cruxToastAction'),
                onPressed: onAction ?? action.onPressed,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action.label),
              ),
            ],
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
