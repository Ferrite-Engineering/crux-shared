// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_ide_layout/src/crux_control_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One choice of a [CruxPopUpButton].
@immutable
class CruxPopUpItem<T> {
  /// Creates an item.
  const CruxPopUpItem({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  /// The value the item selects.
  final T value;

  /// The localized label, drawn in the button and the menu, and announced.
  final String label;

  /// An optional glyph before the label in the menu.
  final IconData? icon;

  /// Whether the item can be chosen; a disabled one is greyed and skipped.
  final bool enabled;
}

/// How long typed characters build one type-ahead prefix.
const Duration _kTypeAheadWindow = Duration(seconds: 1);

/// The gap between the button and its menu.
const double _kMenuGap = 4;

/// The closest a menu comes to the window's edge.
const double _kMenuMargin = 8;

/// The Crux Desktop pop-up button: a single choice of a list, shown as the
/// chosen value with a down chevron, opening a menu of the choices. It
/// replaces Material's `DropdownButton` and `DropdownButtonFormField` on
/// desktop.
///
/// - **Look.** 28 px tall (`CruxDesktopTokens.controlHeight`), or 24 px
///   with [dense]; a 4 px radius; a flat face with a 1 px border; the value
///   in regular weight; one plain chevron. It is as wide as its widest item
///   unless [width] or [expand] says otherwise. The menu opens below it (above
///   when there is no room) at the 6 px menu radius; the chosen item carries a
///   check mark there.
/// - **Keyboard.** A Tab stop. Space, Enter and Alt+Down (or Alt+Up) open
///   the menu with focus on the chosen item. In the menu the arrow keys,
///   Home and End move, typing a label's first letters jumps to it,
///   Space and Enter choose, and Escape closes with nothing changed.
/// - **Screen reader.** One button named [semanticLabel], with the chosen
///   item's label as its value and the expanded or collapsed state. The menu
///   is a named scope of one button per item, the chosen one selected.
/// - **Hover, press, disabled, error and high contrast** states. A null
///   [onChanged] disables it.
class CruxPopUpButton<T> extends StatefulWidget {
  /// Creates a pop-up button.
  const CruxPopUpButton({
    required this.items,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.placeholder,
    this.width,
    this.expand = false,
    this.dense = false,
    this.valueStyle,
    this.focusNode,
    this.autofocus = false,
    this.hasError = false,
    super.key,
  });

  /// The choices, in menu order.
  final List<CruxPopUpItem<T>> items;

  /// The chosen value. A value no item carries shows [placeholder].
  final T? value;

  /// Called with the chosen item's value; null disables the button. Not
  /// called when the menu closes on the item already chosen, or on Escape.
  final ValueChanged<T>? onChanged;

  /// The accessible name, normally the row label.
  final String? semanticLabel;

  /// The text shown when no item is chosen.
  final String? placeholder;

  /// A fixed width; null sizes the button to its widest item.
  final double? width;

  /// Whether the button fills its parent's width. The parent must bound it.
  final bool expand;

  /// Whether the button takes the dense height of dock strips.
  final bool dense;

  /// The value's text style over the default, such as the monospace face
  /// for a technical value.
  final TextStyle? valueStyle;

  /// An optional focus node.
  final FocusNode? focusNode;

  /// Whether the button takes focus when first built.
  final bool autofocus;

  /// Whether to draw the error border, as a form field with a failed
  /// validation does.
  final bool hasError;

  @override
  State<CruxPopUpButton<T>> createState() => _CruxPopUpButtonState<T>();
}

class _CruxPopUpButtonState<T> extends State<CruxPopUpButton<T>> {
  bool _open = false;

  int get _selectedIndex =>
      widget.items.indexWhere((item) => item.value == widget.value);

  bool get _enabled => widget.onChanged != null;

  Future<void> _openMenu() async {
    if (_open || !_enabled || widget.items.isEmpty) return;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final style = CruxControlStyle.of(context, dense: widget.dense);
    setState(() => _open = true);
    final picked = await navigator.push<_Picked<T>>(
      _PopUpMenuRoute<T>(
        anchor: anchor,
        items: widget.items,
        selectedIndex: _selectedIndex,
        style: style,
        valueStyle: widget.valueStyle,
        semanticLabel: widget.semanticLabel,
        textDirection: Directionality.of(context),
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
      ),
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked == null || picked.index == _selectedIndex) return;
    widget.onChanged?.call(picked.value);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) &&
        HardwareKeyboard.instance.isAltPressed) {
      unawaited(_openMenu());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final style = CruxControlStyle.of(context, dense: widget.dense);
    final selected = _selectedIndex;
    final valueLabel = selected >= 0
        ? widget.items[selected].label
        : widget.placeholder ?? '';
    final fixed = widget.expand || widget.width != null;

    Widget button = CruxPressable(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onPressed: _enabled && widget.items.isNotEmpty
          ? () => unawaited(_openMenu())
          : null,
      semanticLabel: widget.semanticLabel,
      semanticValue: valueLabel,
      expanded: _open,
      builder: (context, state) {
        var face = state.pressed || _open
            ? style.pressed(style.face)
            : state.hovered
            ? style.hover(style.face)
            : style.face;
        var border = widget.hasError
            ? style.error
            : state.hovered || state.pressed || _open
            ? style.borderStrong
            : style.border;
        var text = style.label;
        var chevron = style.labelSecondary;
        if (!state.enabled) {
          face = style.disabled(face);
          border = style.disabled(border);
          text = style.labelDisabled;
          chevron = style.labelDisabled;
        }
        final valueText = style.value
            .merge(widget.valueStyle)
            .copyWith(color: text);
        final placeholderText = valueText.copyWith(
          color: state.enabled ? style.labelSecondary : style.labelDisabled,
        );
        Text line(String label, {bool placeholder = false}) => Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: placeholder ? placeholderText : valueText,
        );

        // Sized to the widest item, as a native pop-up is, so the button
        // never changes width when the choice changes.
        final Widget value = fixed
            ? line(valueLabel, placeholder: selected < 0)
            : IndexedStack(
                index: selected >= 0 ? selected : widget.items.length,
                alignment: AlignmentDirectional.centerStart,
                children: [
                  for (final item in widget.items) line(item.label),
                  line(widget.placeholder ?? '', placeholder: true),
                ],
              );
        return CruxFocusRing(
          focused: state.focused,
          color: style.focus,
          radius: style.radius,
          child: Container(
            height: style.height,
            padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
            decoration: BoxDecoration(
              color: face,
              borderRadius: BorderRadius.circular(style.radius),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Flexible(
                  fit: fixed ? FlexFit.tight : FlexFit.loose,
                  child: value,
                ),
                const SizedBox(width: 6),
                Icon(Icons.expand_more, size: 16, color: chevron),
              ],
            ),
          ),
        );
      },
    );
    if (widget.expand) {
      button = SizedBox(width: double.infinity, child: button);
    } else if (widget.width case final double width) {
      button = SizedBox(width: width, child: button);
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: button,
    );
  }
}

/// The [CruxPopUpButton] of a [Form]: validation, saving and reset, with the
/// error message below the button and the error border on it.
///
/// Use it where a `DropdownButtonFormField` took a validator or sat in a
/// form that is saved or reset; elsewhere a [CruxPopUpButton] is enough.
class CruxPopUpFormField<T> extends FormField<T> {
  /// Creates a form field.
  CruxPopUpFormField({
    required List<CruxPopUpItem<T>> items,
    super.initialValue,
    ValueChanged<T>? onChanged,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    String? semanticLabel,
    String? placeholder,
    double? width,
    bool expand = false,
    bool dense = false,
    super.enabled,
    super.key,
  }) : super(
         builder: (field) {
           final theme = Theme.of(field.context);
           final error = field.errorText;
           return Column(
             mainAxisSize: MainAxisSize.min,
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               CruxPopUpButton<T>(
                 items: items,
                 value: field.value,
                 onChanged: field.widget.enabled
                     ? (value) {
                         field.didChange(value);
                         onChanged?.call(value);
                       }
                     : null,
                 semanticLabel: semanticLabel,
                 placeholder: placeholder,
                 width: width,
                 expand: expand,
                 dense: dense,
                 hasError: error != null,
               ),
               if (error != null)
                 Padding(
                   padding: const EdgeInsets.only(top: 4),
                   child: Text(
                     error,
                     style: theme.textTheme.bodySmall?.copyWith(
                       color: theme.colorScheme.error,
                     ),
                   ),
                 ),
             ],
           );
         },
       );
}

/// What the menu returns: the chosen item, which may carry a null value.
@immutable
class _Picked<T> {
  const _Picked(this.index, this.value);

  final int index;
  final T value;
}

class _PopUpMenuRoute<T> extends PopupRoute<_Picked<T>> {
  _PopUpMenuRoute({
    required this.anchor,
    required this.items,
    required this.selectedIndex,
    required this.style,
    required this.valueStyle,
    required this.semanticLabel,
    required this.textDirection,
    required this.barrierLabel,
    required this.themes,
  });

  final Rect anchor;
  final List<CruxPopUpItem<T>> items;
  final int selectedIndex;
  final CruxControlStyle style;
  final TextStyle? valueStyle;
  final String? semanticLabel;
  final TextDirection textDirection;
  final CapturedThemes themes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  // No motion: the menu is there at once and gone at once.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _MenuLayout(anchor: anchor, textDirection: textDirection),
      child: themes.wrap(_PopUpMenu<T>(route: this)),
    );
  }
}

/// Places the menu below its button, or above it when there is more room
/// there, never past the window's edge.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.textDirection});

  final Rect anchor;
  final TextDirection textDirection;

  double _below(Size size) =>
      size.height - anchor.bottom - _kMenuGap - _kMenuMargin;

  double _above() => anchor.top - _kMenuGap - _kMenuMargin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final maxWidth = math.max(0, size.width - 2 * _kMenuMargin).toDouble();
    final maxHeight = math.max(0, math.max(_below(size), _above())).toDouble();
    return BoxConstraints(
      minWidth: math.min(anchor.width, maxWidth),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = _below(size);
    final fitsBelow = childSize.height <= below || below >= _above();
    final y = fitsBelow
        ? anchor.bottom + _kMenuGap
        : anchor.top - _kMenuGap - childSize.height;
    final x = textDirection == TextDirection.ltr
        ? anchor.left
        : anchor.right - childSize.width;
    final maxX = math.max(
      _kMenuMargin,
      size.width - _kMenuMargin - childSize.width,
    );
    return Offset(x.clamp(_kMenuMargin, maxX), y);
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.textDirection != textDirection;
}

class _PopUpMenu<T> extends StatefulWidget {
  const _PopUpMenu({required this.route});

  final _PopUpMenuRoute<T> route;

  @override
  State<_PopUpMenu<T>> createState() => _PopUpMenuState<T>();
}

class _PopUpMenuState<T> extends State<_PopUpMenu<T>> {
  late final List<FocusNode> _nodes;
  late final int _initial;
  String _typed = '';
  Timer? _typeAheadReset;

  List<CruxPopUpItem<T>> get _items => widget.route.items;

  @override
  void initState() {
    super.initState();
    _nodes = [
      for (var i = 0; i < _items.length; i++)
        FocusNode(debugLabel: 'CruxPopUpItem $i'),
    ];
    final selected = widget.route.selectedIndex;
    _initial = selected >= 0 && _items[selected].enabled
        ? selected
        : _next(-1, 1) ?? 0;
    // A long menu opens scrolled to the chosen item.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _nodes.isEmpty) return;
      final context = _nodes[_initial].context;
      if (context != null) Scrollable.ensureVisible(context);
    });
  }

  @override
  void dispose() {
    _typeAheadReset?.cancel();
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int? _next(int from, int step, {bool wrap = false}) {
    final n = _items.length;
    for (var k = 1; k <= n; k++) {
      final i = from + step * k;
      if (!wrap && (i < 0 || i >= n)) return null;
      final j = i % n;
      if (_items[j].enabled) return j;
    }
    return null;
  }

  int get _focused {
    final i = _nodes.indexWhere((n) => n.hasFocus);
    return i < 0 ? _initial : i;
  }

  void _focus(int? i) {
    if (i == null) return;
    _nodes[i].requestFocus();
    final context = _nodes[i].context;
    if (context != null) {
      // Each is a no-op when the item is already in view on that side.
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  void _typeAhead(String character) {
    _typeAheadReset?.cancel();
    _typeAheadReset = Timer(_kTypeAheadWindow, () => _typed = '');
    final repeat = _typed.length == 1 && _typed == character;
    _typed = repeat ? _typed : '$_typed$character';
    final prefix = _typed.toLowerCase();
    // A fresh letter, or the same letter again, starts after the current
    // item, so repeating it walks the items that start with it; a longer
    // prefix may still match the current item.
    final from = _typed.length == 1 ? _focused : _focused - 1;
    final n = _items.length;
    for (var k = 1; k <= n; k++) {
      final i = (from + k) % n;
      if (_items[i].enabled &&
          _items[i].label.toLowerCase().trimLeft().startsWith(prefix)) {
        _focus(i);
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _focus(_next(_focused, 1, wrap: true));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _focus(_next(_focused, -1, wrap: true));
    } else if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.pageUp) {
      _focus(_next(-1, 1));
    } else if (key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.pageDown) {
      _focus(_next(_items.length, -1));
    } else if (key == LogicalKeyboardKey.tab) {
      // A menu is not a Tab cycle: Tab stays put, Escape closes.
    } else {
      final character = event.character;
      final keyboard = HardwareKeyboard.instance;
      if (character == null ||
          character.isEmpty ||
          keyboard.isControlPressed ||
          keyboard.isMetaPressed ||
          keyboard.isAltPressed ||
          character.codeUnitAt(0) < 0x20) {
        return KeyEventResult.ignored;
      }
      _typeAhead(character);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final style = route.style;
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final valueStyle = style.value.merge(route.valueStyle);
    return Semantics(
      scopesRoute: true,
      namesRoute: route.semanticLabel != null,
      explicitChildNodes: true,
      label: route.semanticLabel,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _onKey,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: BoxDecoration(
              color: style.menuSurface,
              borderRadius: BorderRadius.circular(style.menuRadius),
              border: Border.all(color: style.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(style.menuRadius - 1),
              child: IntrinsicWidth(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        _row(context, i, style, valueStyle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    int i,
    CruxControlStyle style,
    TextStyle valueStyle,
  ) {
    final item = _items[i];
    final chosen = i == widget.route.selectedIndex;
    return CruxPressable(
      key: ValueKey<String>('cruxPopUpItem-$i'),
      focusNode: _nodes[i],
      autofocus: i == _initial,
      onPressed: item.enabled
          ? () => Navigator.of(context).pop(_Picked<T>(i, item.value))
          : null,
      semanticLabel: item.label,
      selected: chosen,
      builder: (context, state) {
        final highlight = state.hovered || state.focused;
        final face = state.pressed
            ? style.overlay.withValues(alpha: 0.14)
            : highlight
            ? style.overlay.withValues(alpha: 0.08)
            : Colors.transparent;
        final text = state.enabled ? style.label : style.labelDisabled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: CruxFocusRing(
            focused: state.focused,
            color: style.focus,
            radius: 3,
            inset: true,
            gap: 0.5,
            child: Container(
              height: style.height,
              padding: const EdgeInsetsDirectional.only(start: 6, end: 12),
              decoration: BoxDecoration(
                color: face,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: chosen
                        ? Icon(Icons.check, size: 14, color: text)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  if (item.icon case final IconData icon) ...[
                    Icon(icon, size: 16, color: text),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: valueStyle.copyWith(color: text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
