// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:crux_ide_layout/src/modal_guard.dart';
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
}) async {
  Widget build(BuildContext dialogContext) =>
      _CruxDialogRouteScope(child: Builder(builder: builder));
  Future<T?> open() {
    final target = navigator;
    if (target == null) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierLabel: barrierLabel,
        useRootNavigator: useRootNavigator,
        routeSettings: routeSettings,
        builder: build,
      );
    }
    return target.push<T>(
      DialogRoute<T>(
        context: context,
        builder: build,
        barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
        barrierDismissible: barrierDismissible,
        barrierLabel: barrierLabel,
        settings: routeSettings,
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
        .max(
          0,
          math.min(widget.width, screen.width - gutter),
        )
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
KeyEventResult _onDialogKey(
  KeyEvent event,
  VoidCallback? onSubmit,
) {
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
