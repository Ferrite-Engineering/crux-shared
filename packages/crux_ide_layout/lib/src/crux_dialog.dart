// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:crux_ide_layout/src/modal_guard.dart';
import 'package:crux_ide_layout/src/pushed_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The gutter a dialog keeps from every edge of the window.
const double kCruxDialogGutter = 24;

/// The width a [CruxDialog] takes when it is not given one.
const double kCruxDialogDefaultWidth = 440;

/// Opens a desktop dialog: the one way every Crux dialog is shown.
///
/// Mirrors `showDialog`'s named parameters, so moving a call site is a
/// rename, and adds what every suite dialog needs:
///
/// - **Escape closes it**, whatever [barrierDismissible] says. The route's own
///   dismiss action is disabled whenever the barrier is, so a non-dismissible
///   form would otherwise ignore Escape; the charter's rule is that closing is
///   a deliberate act (Escape, Cancel, the close button), never a stray click
///   on the scrim, and Escape is deliberate.
/// - **[barrierDismissible]** keeps its name so the suite's dismissible-form
///   guard reads it at the call site: pass `false` for anything that holds
///   input. A lightweight confirm may leave it `true`.
/// - **[modalGuardKey]**, when given, runs the open inside
///   `ModalGuard.run` under that key, so a repeated shortcut, key repeat or a
///   double-clicked menu item cannot stack a second copy. The guard's
///   reachability scanner counts a call that passes it as guarded. A
///   suppressed re-entrant call resolves `null` at once.
/// - The scrim, corner radius and border come from the theme
///   (`cruxDesktopTheme`'s dialog theme), so a product not yet on the desktop
///   theme keeps its current look.
///
/// - **[navigator]**, when given, is the navigator the dialog is pushed on,
///   in place of the one [context] and [useRootNavigator] would find. A
///   product passes a tab's own nested navigator (crux_workspace's
///   `CruxTabNavigators`) so the dialog mounts under that tab's provider
///   scope instead of wrapping its builder in a second scope over the tab's
///   container. The dialog then covers that navigator's area, not the window.
///   Tab and Shift+Tab stay inside the dialog; a click or a window-level
///   shortcut still reaches the rest of the window. Escape closes it and
///   focus returns to the control that had it in the tab. A window-level key
///   handler skips keys while `cruxFocusIsInPushedRoute()` is true.
///
/// - **[blocking]**, true by default, is the modal dialog with the theme's
///   scrim. Pass false for a transient surface that does not interrupt (a
///   statistics popover): no scrim (a transparent barrier), closed by a click
///   outside it as well as by Escape, whatever [barrierDismissible] says.
///   Focus-in, [modalGuardKey] and the semantics behaviour are unchanged.
///
/// - **Tab stays inside.** Every dialog, on either navigator, traverses in a
///   closed loop, while the app's page routes hand Tab on to the window at
///   their edges so the strips drawn above the `Navigator` are reachable.
///
/// - **Focus on close.** When the route leaves the tree, keyboard focus goes
///   back to the node that held it when the dialog was opened, or to the
///   navigator's enclosing scope when that node is gone, so a window-level
///   shortcut keeps firing without a click into the window. It is left where
///   it is when it is already under the dialog's navigator (an action that
///   focused a control) or inside another pushed route
///   (`cruxFocusIsInPushedRoute`: an action that opened a dialog).
///
/// [builder] normally returns a [CruxDialog]. The EULA, which is mounted
/// above the `Navigator` where no route can be pushed, uses [CruxDialog]
/// directly instead.
Future<T?> showCruxDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? modalGuardKey,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  NavigatorState? navigator,
  bool blocking = true,
}) async {
  // A non-blocking surface has no scrim and closes on a click outside it, so
  // it is always dismissible by the barrier.
  final dismissible = !blocking || barrierDismissible;
  // Read before the route is pushed: once it is, the route's own scope has
  // taken focus and the node the user was on is no longer the primary focus.
  final focusBefore = FocusManager.instance.primaryFocus;
  Widget build(BuildContext dialogContext) => _CruxDialogFocusReturn(
    focusBefore: focusBefore,
    child: _CruxDialogRouteScope(child: Builder(builder: builder)),
  );
  Future<T?> open() {
    final target = navigator;
    if (target == null) {
      return showDialog<T>(
        context: context,
        barrierColor: blocking ? null : Colors.transparent,
        barrierDismissible: dismissible,
        barrierLabel: barrierLabel,
        useRootNavigator: useRootNavigator,
        routeSettings: routeSettings,
        // The app's routes hand Tab on to the window at their edges, so the
        // strips above the Navigator are reachable; a dialog keeps it. This
        // is showDialog's default too, stated so it cannot drift.
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        builder: build,
      );
    }
    return target.push<T>(
      DialogRoute<T>(
        context: context,
        builder: build,
        barrierColor: blocking
            ? DialogTheme.of(context).barrierColor ?? Colors.black54
            : Colors.transparent,
        barrierDismissible: dismissible,
        barrierLabel: barrierLabel,
        settings: routeSettings,
        // A nested navigator hands Tab on to the window by default; a dialog
        // keeps it, as one on the root navigator does. The pointer and
        // window-level shortcuts still reach the rest of the window.
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        // Themes between the caller and the navigator travel with the
        // dialog, as showDialog does; a caller outside the navigator (a menu
        // bar opening a dialog on a tab's navigator) has none to carry.
        themes: _isAncestor(target.context, context)
            ? InheritedTheme.capture(from: context, to: target.context)
            : null,
      ),
    );
  }

  final key = modalGuardKey;
  if (key == null) return await open();
  T? result;
  await ModalGuard.run(key, () async {
    result = await open();
  });
  return result;
}

bool _isAncestor(BuildContext ancestor, BuildContext of) {
  var found = false;
  of.visitAncestorElements((element) {
    if (identical(element, ancestor)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Hands keyboard focus back when the dialog's route leaves the tree.
///
/// A window-level shortcut hears a key only while some node under the
/// navigator holds primary focus. When the route is removed and focus has
/// ended up on a scope above the navigator, or nowhere (the platform can leave
/// it there while a modal is up), the next chord reaches no one until the user
/// clicks into the window.
///
/// This widget wraps the dialog. When it is disposed, which is when the route
/// is removed after its exit transition, it checks where focus is on the next
/// frame:
///
/// - Focus under the dialog's own navigator is left alone: a control the
///   action that closed the dialog focused, or a dialog it opened on that
///   navigator, keeps the focus it took.
/// - Focus inside a route pushed on any navigator is left alone
///   ([cruxFocusIsInPushedRoute]): an action that opened a dialog on another
///   navigator, such as a tab's own.
/// - Otherwise focus goes back to the node that held it before the dialog
///   opened, if that node is still in the tree under the navigator, or else to
///   the navigator's enclosing scope.
class _CruxDialogFocusReturn extends StatefulWidget {
  const _CruxDialogFocusReturn({
    required this.focusBefore,
    required this.child,
  });

  /// The primary focus when the dialog was opened.
  final FocusNode? focusBefore;

  final Widget child;

  @override
  State<_CruxDialogFocusReturn> createState() => _CruxDialogFocusReturnState();
}

class _CruxDialogFocusReturnState extends State<_CruxDialogFocusReturn> {
  late final NavigatorState _navigator;
  late final FocusNode? _focusBefore;

  @override
  void initState() {
    super.initState();
    _navigator = Navigator.of(context);
    _focusBefore = widget.focusBefore;
  }

  @override
  void dispose() {
    final navigator = _navigator;
    final before = _focusBefore;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      final navigatorFocus = navigator.focusNode;
      final primary = FocusManager.instance.primaryFocus;
      final inNavigator =
          primary != null &&
          (primary == navigatorFocus ||
              primary.ancestors.contains(navigatorFocus));
      if (inNavigator || cruxFocusIsInPushedRoute(primary)) return;
      if (before != null &&
          before.context?.mounted == true &&
          before.canRequestFocus &&
          before.ancestors.contains(navigatorFocus)) {
        before.requestFocus();
      } else {
        navigatorFocus.enclosingScope?.requestFocus();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Lets Escape pop the dialog's route even when its barrier is not
/// dismissible. A disabled action found first ends the Escape lookup, so
/// this enabled one sits between the route and the focused control.
class _CruxDialogRouteScope extends StatelessWidget {
  const _CruxDialogRouteScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) => Navigator.of(context).maybePop(),
        ),
      },
      child: child,
    );
  }
}

/// What a [CruxDialogAction] does, which sets how it looks.
enum CruxDialogActionRole {
  /// A neutral choice: Cancel, Close, Back. Outlined.
  secondary,

  /// The dialog's default choice: OK, Save, Add. Filled.
  primary,

  /// A choice that destroys something: Delete, Discard. Filled in the error
  /// colour. The dialog's safe choice should take [CruxDialogAction.autofocus].
  destructive,

  /// A low-emphasis choice beside the others: Learn more, Copy. Text only.
  tertiary,
}

/// A button in a [CruxDialog]'s action row.
class CruxDialogAction extends StatelessWidget {
  /// Creates an action. A null [onPressed] renders it disabled.
  const CruxDialogAction({
    required this.label,
    required this.onPressed,
    this.role = CruxDialogActionRole.secondary,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  /// The localized label.
  final String label;

  /// Called on activation; null disables the button.
  final VoidCallback? onPressed;

  /// How the button reads.
  final CruxDialogActionRole role;

  /// Whether this button takes focus when the dialog opens. Give it to the
  /// safe action of a destructive dialog.
  final bool autofocus;

  /// An optional focus node.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);
    switch (role) {
      case CruxDialogActionRole.secondary:
        return OutlinedButton(
          onPressed: onPressed,
          autofocus: autofocus,
          focusNode: focusNode,
          child: text,
        );
      case CruxDialogActionRole.primary:
        return FilledButton(
          onPressed: onPressed,
          autofocus: autofocus,
          focusNode: focusNode,
          child: text,
        );
      case CruxDialogActionRole.destructive:
        final colorScheme = Theme.of(context).colorScheme;
        return FilledButton(
          onPressed: onPressed,
          autofocus: autofocus,
          focusNode: focusNode,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: text,
        );
      case CruxDialogActionRole.tertiary:
        return TextButton(
          onPressed: onPressed,
          autofocus: autofocus,
          focusNode: focusNode,
          child: text,
        );
    }
  }
}

/// The Crux Desktop dialog frame: an optional title, a body, and an action
/// row, sized and named the same way in every product.
///
/// - **Size.** [width] (default [kCruxDialogDefaultWidth]) is clamped to the
///   window less a [kCruxDialogGutter] on each side, and the height to the
///   window less the same gutter; a [scrollable] body scrolls rather than
///   overflowing.
/// - **Name.** The dialog is one semantics container named by [title] (or
///   [semanticLabel]): the desktop bridges have no dialog role, so the name
///   is the only way a screen reader can say where focus went.
/// - **Focus.** Unless [takeFocus] is false, focus moves into the dialog
///   when it opens: to a control that asked for `autofocus`, else to the
///   first control in traversal order.
/// - **Enter** runs [onSubmit] when focus is not on a button, a checkbox, a
///   dropdown or another control that Enter already activates, and not in a
///   multi-line text field, where Enter is a newline. Without [onSubmit],
///   Enter does only what the focused control does.
/// - **Escape** is the route's: [showCruxDialog] makes it close the dialog.
///
/// Colours, the corner radius and the border come from the ambient
/// `DialogThemeData`, which `cruxDesktopTheme` sets.
class CruxDialog extends StatefulWidget {
  /// Creates a dialog.
  const CruxDialog({
    required this.content,
    this.title,
    this.titleTrailing,
    this.actions = const <Widget>[],
    this.onSubmit,
    this.width = kCruxDialogDefaultWidth,
    this.scrollable = true,
    this.contentPadding,
    this.semanticLabel,
    this.takeFocus = true,
    this.semanticContainer = true,
    super.key,
  });

  /// The body.
  final Widget content;

  /// The localized title, also the dialog's accessible name.
  final String? title;

  /// A widget at the end of the title row: a badge or a close button.
  final Widget? titleTrailing;

  /// The action row, laid out at the end in order. Use [CruxDialogAction]s;
  /// put the safe choice first.
  final List<Widget> actions;

  /// The default action Enter triggers; see the class docs.
  final VoidCallback? onSubmit;

  /// The preferred width, before the window clamp.
  final double width;

  /// Whether the body scrolls when the window is too short for it. Pass
  /// false when the body manages its own scrolling (a list).
  final bool scrollable;

  /// Padding around the body. Defaults to 16 at the sides and bottom, and at
  /// the top when there is no title.
  final EdgeInsetsGeometry? contentPadding;

  /// The accessible name when it should differ from [title], or when there
  /// is no title.
  final String? semanticLabel;

  /// Whether focus moves into the dialog when it opens.
  final bool takeFocus;

  /// Whether the frame is the named semantics container. False only where
  /// the host already names the surface (a `CruxModalSurface` above the
  /// `Navigator`), so the dialog is not announced twice.
  final bool semanticContainer;

  @override
  State<CruxDialog> createState() => _CruxDialogState();
}

class _CruxDialogState extends State<CruxDialog> {
  final FocusNode _frame = FocusNode(
    debugLabel: 'CruxDialog',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    if (widget.takeFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirst());
    }
  }

  void _focusFirst() {
    if (!mounted || _frame.hasFocus) return;
    // With nothing in the dialog focused, the traversal policy hands focus
    // to the first traversable control in the dialog's scope.
    _frame.nextFocus();
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogTheme = DialogTheme.of(context);
    final screen = MediaQuery.sizeOf(context);
    const gutter = kCruxDialogGutter * 2;
    final width = math
        .max(0, math.min(widget.width, screen.width - gutter))
        .toDouble();
    final maxHeight = math.max(0, screen.height - gutter).toDouble();
    final title = widget.title;
    final name = widget.semanticLabel ?? title;

    final titleStyle =
        dialogTheme.titleTextStyle ??
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final contentStyle =
        dialogTheme.contentTextStyle ?? theme.textTheme.bodyMedium;

    final padding =
        widget.contentPadding ??
        EdgeInsets.fromLTRB(16, title == null ? 16 : 0, 16, 16);
    Widget body = Padding(padding: padding, child: widget.content);
    if (widget.scrollable) body = SingleChildScrollView(child: body);
    if (contentStyle != null) {
      body = DefaultTextStyle.merge(style: contentStyle, child: body);
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  // The container below carries the title as its name.
                  child: ExcludeSemantics(
                    excluding: name == title,
                    child: Text(title, style: titleStyle),
                  ),
                ),
                if (widget.titleTrailing case final Widget trailing) trailing,
              ],
            ),
          ),
        Flexible(child: body),
        if (widget.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              overflowAlignment: OverflowBarAlignment.end,
              children: widget.actions,
            ),
          ),
      ],
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(kCruxDialogGutter),
      semanticsRole: widget.semanticContainer
          ? SemanticsRole.dialog
          : SemanticsRole.none,
      child: Semantics(
        container: widget.semanticContainer,
        explicitChildNodes: widget.semanticContainer,
        label: widget.semanticContainer ? name : null,
        child: Focus(
          focusNode: _frame,
          includeSemantics: false,
          onKeyEvent: (_, event) => _onDialogKey(event, widget.onSubmit),
          child: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: column,
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether a plain Enter, with focus where it is now, belongs to the dialog's
/// default action rather than to the focused control.
bool _enterSubmits() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return true;
  final editable = focused.findAncestorWidgetOfExactType<EditableText>();
  if (editable != null) {
    // An input method composing text (Chinese, Japanese, Korean) commits
    // the composition with Enter; a multi-line field takes it as a newline.
    // A single-line field submits.
    final composing = editable.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return false;
    return editable.maxLines == 1;
  }
  // A button, checkbox or dropdown takes Enter as its own activation, through
  // the app's Enter shortcut, which this handler must not pre-empt.
  final activate = Actions.maybeFind<ActivateIntent>(focused);
  return activate == null || !activate.isEnabled(const ActivateIntent());
}

/// Maps a plain Enter to [onSubmit] while focus is inside the dialog. A key
/// handler on the dialog's own (semantics-free) focus node rather than a
/// `Shortcuts` widget, whose focus node would add a semantics node around
/// the body.
KeyEventResult _onDialogKey(KeyEvent event, VoidCallback? onSubmit) {
  if (onSubmit == null || event is! KeyDownEvent) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  if (key != LogicalKeyboardKey.enter &&
      key != LogicalKeyboardKey.numpadEnter) {
    return KeyEventResult.ignored;
  }
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isShiftPressed ||
      keyboard.isControlPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed) {
    return KeyEventResult.ignored;
  }
  if (!_enterSubmits()) return KeyEventResult.ignored;
  onSubmit();
  return KeyEventResult.handled;
}
