// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show CruxPanelEmptyState, announceCrux;
import 'package:crux_settings_ui/crux_settings_ui.dart' show CruxFormSection;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The label column width of every row in a [CruxInspector]: narrower than a
/// dialog form's, because a dock is narrower than a dialog.
const double kCruxInspectorLabelWidth = 112;

/// Builds one section of a [CruxInspector] for [selection], or returns null
/// when the section does not apply to it (a decoder section for a signal, a
/// Pro section in a build without the overlay).
///
/// A host assembles the list from its own code first and its Pro seam after:
/// `[...coreSections, ...ref.watch(proInspectorSectionsProvider)]`, where the
/// seam provider defaults to an empty list in open core and the Pro overlay
/// overrides it.
typedef CruxInspectorSectionBuilder<T extends Object> =
    Widget? Function(BuildContext context, T selection);

/// Opens a [CruxInspector] with keyboard focus: the double-click on a canvas
/// object, the object's "Properties" context-menu entry and its shortcut all
/// call [open].
///
/// One controller per inspector, owned by the same scope as the selection it
/// shows. In a product with one provider container per editor tab that is the
/// per-tab container: a controller shared by two tabs would let a request made
/// in one tab move focus in the other.
///
/// The controller also keeps the inspector's held draft (see
/// [CruxInspector.markDirty]) across the inspector being rebuilt: a dock
/// builds only its active tab, so switching to another tab and back mounts a
/// new inspector, which picks the hold up from here.
class CruxInspectorController extends ChangeNotifier {
  /// Creates a controller. [onReveal] makes the inspector visible: it
  /// activates the inspector's dock tab and un-collapses its region.
  CruxInspectorController({this.onReveal});

  /// Makes the inspector visible. Called first by [open].
  final VoidCallback? onReveal;

  bool _focusPending = false;

  // The held selection while a section is dirty, and the identity whose
  // held notice was last announced.
  Object? _held;
  bool _dirty = false;
  Object? _announcedFor;

  /// Whether a section holds unapplied edits.
  bool get dirty => _dirty;

  /// Whether an [open] is waiting for the inspector to take focus.
  bool get focusPending => _focusPending;

  /// Reveals the inspector and asks it to put focus on its first control
  /// (its heading when it has none) on the next frame it is showing.
  ///
  /// The request waits while the inspector is not mounted: a dock builds only
  /// its active tab, so the inspector takes focus when [onReveal] has made
  /// its tab active.
  void open() {
    onReveal?.call();
    _focusPending = true;
    notifyListeners();
  }

  /// Withdraws a pending [open].
  void cancel() => _focusPending = false;

  bool _takeFocusRequest() {
    final pending = _focusPending;
    _focusPending = false;
    return pending;
  }
}

/// A dock tab's body that shows and edits the properties of the current
/// canvas selection.
///
/// It is not a route. It sits inside the dock, so it is built inside the
/// provider scope the dock is in (in the suite, the editor tab's own
/// container) and reads and writes that tab's state with no container to pass
/// around. A section must not open a route to edit a value either: pickers
/// are inline controls, and a dropdown's items are plain widgets built from
/// values the section has already read.
///
/// - **Selection.** [selection] is the host's current selection, read from
///   its own state each build, ideally a small identity (an id or a sealed
///   selection value) that the sections resolve. Null shows the empty state,
///   a [CruxPanelEmptyState] with [emptyMessage], which also describes the
///   enclosing dock to a screen reader.
/// - **Sections.** One [CruxInspectorSectionBuilder] per section, core first,
///   Pro seam after; a builder returning null is skipped. Sections are
///   [CruxInspectorSection]s holding `CruxFormRow`s and
///   [CruxInspectorValueRow]s, or a [CruxInspectorListSection] for a long run
///   of rows, which the inspector builds lazily.
/// - **Action bar.** The `footer` of a [CruxInspectorSection] (a
///   [CruxInspectorApplyBar], or the section's own button row) is not drawn
///   with its rows: the inspector pins it to its bottom edge, under a divider
///   and outside the scrolling list, so a tall section never hides its
///   buttons. Sections keep declaring their footer; they may sit inside any
///   widget of the host's. When several sections on a selection have Apply
///   bars the one bar applies (or reverts) every enabled one, with the first
///   bar's labels; other footers stack in section order. A fade over the
///   list's bottom edge shows while rows continue below it.
/// - **Identity.** The body is keyed by [identity] (the selection itself when
///   null), so a section's controllers and drafts are rebuilt when another
///   object is selected and never carry one object's text into another's.
/// - **Drafts.** A section whose edits apply on Apply (cross-field validation,
///   an expensive re-run) calls [markDirty] while it holds unapplied edits.
///   While it is dirty the inspector keeps showing that object even when the
///   selection moves, says so with [heldMessage] (shown and announced), and
///   follows the selection again once the section applies or reverts. The
///   hold lives in the [controller], so it outlasts the dock showing another
///   tab; the section keeps its draft in the host's per-tab state (not in
///   widget state, which the dock discards with the tab) and reports
///   [markDirty] again when it mounts.
/// - **Focus.** [CruxInspectorController.open] puts focus on the first
///   control, or on the heading for a read-only object. Escape anywhere in
///   the inspector calls [onEscape], which returns focus to the canvas; an
///   input method's composition keeps its own Escape. Unapplied edits stay
///   held, so Escape loses nothing.
class CruxInspector<T extends Object> extends StatefulWidget {
  /// Creates an inspector.
  const CruxInspector({
    required this.selection,
    required this.sections,
    required this.emptyMessage,
    this.emptyIcon,
    this.title,
    this.headerActions,
    this.identity,
    this.controller,
    this.onEscape,
    this.heldMessage,
    super.key,
  });

  /// The object to inspect, or null for the empty state.
  final T? selection;

  /// The section builders, core first and Pro seam after.
  final List<CruxInspectorSectionBuilder<T>> sections;

  /// The localized empty-state message ("Select an element to inspect.").
  final String emptyMessage;

  /// An optional icon above [emptyMessage].
  final IconData? emptyIcon;

  /// The localized heading naming the inspected object ("Cell u_alu",
  /// "SPI decoder 2"). Null shows no heading.
  final String Function(T selection)? title;

  /// Actions beside the heading, such as a Pro "Go to source" button with its
  /// tier badge.
  final List<Widget> Function(BuildContext context, T selection)? headerActions;

  /// The identity the body is keyed by. Null keys by the selection itself.
  final Object? Function(T selection)? identity;

  /// Opens the inspector with focus. See [CruxInspectorController].
  final CruxInspectorController? controller;

  /// Returns focus to the canvas. Called on Escape; null leaves Escape to
  /// the host.
  final VoidCallback? onEscape;

  /// The localized notice shown while unapplied edits hold `held` on screen
  /// after the selection moved ("Apply or revert the changes to SPI decoder
  /// 2 to follow the selection."). Null shows no notice.
  final String Function(T held)? heldMessage;

  /// Tells the enclosing [CruxInspector] whether the calling section holds
  /// unapplied edits. Call it from an edit or apply callback, not from build.
  /// Does nothing outside an inspector.
  static void markDirty(BuildContext context, {required bool dirty}) {
    final scope = context.getInheritedWidgetOfExactType<_CruxInspectorScope>();
    scope?.setDirty(dirty: dirty);
  }

  @override
  State<CruxInspector<T>> createState() => _CruxInspectorState<T>();
}

class _CruxInspectorScope extends InheritedWidget {
  const _CruxInspectorScope({required this.setDirty, required super.child});

  final void Function({required bool dirty}) setDirty;

  @override
  bool updateShouldNotify(_CruxInspectorScope oldWidget) => false;
}

class _CruxInspectorState<T extends Object> extends State<CruxInspector<T>> {
  final FocusNode _root = FocusNode(
    debugLabel: 'CruxInspector',
    skipTraversal: true,
  );
  final FocusNode _body = FocusNode(
    debugLabel: 'CruxInspector body',
    skipTraversal: true,
  );
  final FocusNode _actions = FocusNode(
    debugLabel: 'CruxInspector actions',
    skipTraversal: true,
  );

  // Reached by open() when there is no control to focus. Not a Tab stop: the
  // heading names the object, Tab walks its controls.
  final FocusNode _heading = FocusNode(
    debugLabel: 'CruxInspector heading',
    skipTraversal: true,
  );

  // Text selection for copying values; never a Tab stop.
  final FocusNode _selectable = FocusNode(
    debugLabel: 'CruxInspector selection',
    skipTraversal: true,
  );

  // The footers of the sections on show, which the pinned bar renders.
  final _FooterHost _footers = _FooterHost();

  // Whether the list continues below the visible part; drives the fade.
  final ValueNotifier<bool> _moreBelow = ValueNotifier<bool>(false);

  // Holds the draft state when the host passes no controller.
  CruxInspectorController? _own;

  CruxInspectorController get _state =>
      widget.controller ?? (_own ??= CruxInspectorController());

  T? get _held {
    final held = _state._held;
    return held is T ? held : null;
  }

  set _held(T? value) => _state._held = value;

  bool get _dirty => _state._dirty;

  set _dirty(bool value) => _state._dirty = value;

  Object? get _announcedFor => _state._announcedFor;

  set _announcedFor(Object? value) => _state._announcedFor = value;

  @override
  void initState() {
    super.initState();
    _follow();
    widget.controller?.addListener(_onOpen);
    if (widget.controller?.focusPending ?? false) _scheduleFocus();
  }

  @override
  void didUpdateWidget(CruxInspector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onOpen);
      widget.controller?.addListener(_onOpen);
      if (widget.controller?.focusPending ?? false) _scheduleFocus();
    }
    _follow();
  }

  /// Tracks the selection: always while clean, and while dirty only to take
  /// the newest value of the held object itself (renamed, re-resolved).
  void _follow() {
    final current = widget.selection;
    final held = _held;
    if (!_dirty) {
      _held = current;
    } else if (current != null && held != null && _same(current, held)) {
      _held = current;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onOpen);
    _own?.dispose();
    _footers.dispose();
    _moreBelow.dispose();
    _root.dispose();
    _body.dispose();
    _actions.dispose();
    _heading.dispose();
    _selectable.dispose();
    super.dispose();
  }

  Object? _identityOf(T value) => widget.identity?.call(value) ?? value;

  bool _same(T a, T b) => _identityOf(a) == _identityOf(b);

  void _onOpen() {
    if (widget.controller?.focusPending ?? false) _scheduleFocus();
  }

  void _scheduleFocus() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.controller?._takeFocusRequest() ?? false) _focusFirst();
      })
      ..ensureVisualUpdate();
  }

  void _focusFirst() {
    (_firstIn(_body) ?? _firstIn(_actions) ?? _headingOrRoot()).requestFocus();
  }

  FocusNode _headingOrRoot() => _heading.context != null ? _heading : _root;

  /// The first traversable control under [scope] in reading order.
  static FocusNode? _firstIn(FocusNode scope) {
    final nodes = scope.traversalDescendants
        .where((n) => n.context != null)
        .toList(growable: false);
    if (nodes.isEmpty) return null;
    nodes.sort((a, b) {
      final ra = a.rect;
      final rb = b.rect;
      final dy = ra.top.compareTo(rb.top);
      return dy != 0 ? dy : ra.left.compareTo(rb.left);
    });
    return nodes.first;
  }

  void _setDirty({required bool dirty}) {
    if (_dirty == dirty) return;
    void apply() {
      if (!mounted || _dirty == dirty) return;
      setState(() {
        _dirty = dirty;
        if (!dirty) {
          _held = widget.selection;
          _announcedFor = null;
        }
      });
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final onEscape = widget.onEscape;
    if (onEscape == null || _composing()) return KeyEventResult.ignored;
    onEscape();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.selection;
    final shown = _dirty ? (_held ?? current) : current;
    final heldAway =
        _dirty && shown != null && (current == null || !_same(shown, current));

    Widget content;
    if (shown == null) {
      content = _empty();
    } else {
      final built = <Widget>[
        for (final builder in widget.sections) ?builder(context, shown),
      ];
      if (built.isEmpty) {
        // The held object no longer resolves (it was deleted): nothing is
        // left to apply, so follow the selection again.
        if (heldAway) _setDirty(dirty: false);
        content = _empty();
      } else {
        content = KeyedSubtree(
          key: ValueKey<Object?>(_identityOf(shown)),
          child: _buildBody(context, shown, built, heldAway: heldAway),
        );
      }
    }

    if (heldAway) {
      final notice = widget.heldMessage?.call(shown);
      final id = _identityOf(shown);
      if (notice != null && _announcedFor != id) {
        _announcedFor = id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) announceCrux(context, notice);
        });
      }
    }

    return Focus(
      focusNode: _root,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: _CruxInspectorScope(
        setDirty: _setDirty,
        child: Material(type: MaterialType.transparency, child: content),
      ),
    );
  }

  void _onMoreBelow(bool more) {
    if (_moreBelow.value == more) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      _moreBelow.value = more;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moreBelow.value = more;
    });
  }

  bool _onScrollNotification(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final depth) when depth != 0 => null,
      ScrollMetricsNotification(:final depth) when depth != 0 => null,
      ScrollNotification(:final metrics) => metrics,
      ScrollMetricsNotification(:final metrics) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _onMoreBelow(metrics.extentAfter > 0.5);
    }
    return false;
  }

  Widget _empty() => Semantics(
    container: true,
    child: Focus(
      focusNode: _heading,
      child: CruxPanelEmptyState(
        message: widget.emptyMessage,
        icon: widget.emptyIcon,
      ),
    ),
  );

  Widget _buildBody(
    BuildContext context,
    T shown,
    List<Widget> sections, {
    required bool heldAway,
  }) {
    final theme = Theme.of(context);
    final heading = widget.title?.call(shown);
    final actions =
        widget.headerActions?.call(context, shown) ?? const <Widget>[];
    final notice = heldAway ? widget.heldMessage?.call(shown) : null;
    final segments = _segments(sections);
    final count = segments.fold<int>(0, (sum, s) => sum + s.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (heading != null || actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: heading == null
                      ? const SizedBox.shrink()
                      // Its own node: merged upward, the heading would
                      // rename the dock region around it.
                      : Semantics(
                          container: true,
                          header: true,
                          child: Focus(
                            focusNode: _heading,
                            child: Text(
                              heading,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                ),
                if (actions.isNotEmpty)
                  Focus(
                    focusNode: _actions,
                    includeSemantics: false,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        if (notice != null)
          Container(
            key: const ValueKey<String>('cruxInspectorHeldNotice'),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              notice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Focus(
                  focusNode: _body,
                  includeSemantics: false,
                  child: SelectionArea(
                    focusNode: _selectable,
                    child: NotificationListener<Notification>(
                      onNotification: _onScrollNotification,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: count,
                        itemBuilder: (context, index) {
                          var i = index;
                          for (final segment in segments) {
                            if (i < segment.count) {
                              return segment.build(context, i);
                            }
                            i -= segment.count;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ScrollFade(visible: _moreBelow),
              ),
            ],
          ),
        ),
        _PinnedActionBar(host: _footers),
      ],
    );
  }

  List<_Segment> _segments(List<Widget> sections) {
    final out = <_Segment>[];
    for (var s = 0; s < sections.length; s++) {
      if (s > 0) {
        out.add(_Segment(1, (_, _) => const Divider(height: 24)));
      }
      final section = sections[s];
      if (section is CruxInspectorListSection) {
        out
          ..add(
            _Segment(
              1,
              (context, _) => _SectionHeading(
                title: section.title,
                trailing: section.trailing,
              ),
            ),
          )
          ..add(_Segment(section.itemCount, section.itemBuilder));
      } else {
        // Kept alive, so a section scrolled away keeps its footer in the
        // pinned bar and the callbacks behind it current.
        out.add(
          _Segment(
            1,
            (_, _) => _KeepAlive(
              child: _FooterSlot(host: _footers, index: s, child: section),
            ),
          ),
        );
      }
    }
    return out;
  }
}

class _Segment {
  const _Segment(this.count, this.build);

  final int count;
  final Widget Function(BuildContext context, int index) build;
}

/// Hands a section the pinned bar's host and its own place in the section
/// order. Never notifies: a section re-registers its footer on every build.
class _FooterSlot extends InheritedWidget {
  const _FooterSlot({
    required this.host,
    required this.index,
    required super.child,
  });

  final _FooterHost host;
  final int index;

  @override
  bool updateShouldNotify(_FooterSlot oldWidget) =>
      index != oldWidget.index || !identical(host, oldWidget.host);
}

/// Keeps a section mounted while it is scrolled out of the viewport, so the
/// footer it registered stays live in the pinned bar.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _PinnedFooter {
  const _PinnedFooter(this.index, this.seq, this.footer);

  final int index;
  final int seq;
  final Widget footer;
}

/// The footers the sections on show have registered, in section order.
///
/// A section registers while it builds, so the bar learns of a change one
/// frame later: the bar rebuilds after the frame, never during it, and a
/// rebuild of the bar does not rebuild the sections.
class _FooterHost extends ChangeNotifier {
  final Map<Object, _PinnedFooter> _pinned = <Object, _PinnedFooter>{};
  int _seq = 0;
  bool _scheduled = false;
  bool _disposed = false;

  void put(Object owner, int index, Widget footer) {
    _pinned[owner] = _PinnedFooter(
      index,
      _pinned[owner]?.seq ?? _seq++,
      footer,
    );
    _notifyAfterFrame();
  }

  void remove(Object owner) {
    if (_pinned.remove(owner) != null) _notifyAfterFrame();
  }

  List<Widget> get footers {
    final entries = _pinned.values.toList(growable: false)
      ..sort((a, b) {
        final byIndex = a.index.compareTo(b.index);
        return byIndex != 0 ? byIndex : a.seq.compareTo(b.seq);
      });
    return <Widget>[for (final e in entries) e.footer];
  }

  void _notifyAfterFrame() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      })
      ..ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The inspector's bottom bar: the sections' footers, under a divider, outside
/// the scrolling list. Empty (no divider either) while no section has a footer.
class _PinnedActionBar extends StatelessWidget {
  const _PinnedActionBar({required this.host});

  final _FooterHost host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: host,
    builder: (context, _) {
      final footers = host.footers;
      if (footers.isEmpty) return const SizedBox.shrink();
      return Column(
        key: const ValueKey<String>('cruxInspectorActionBar'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _merged(footers),
          ),
        ],
      );
    },
  );

  /// One footer as it is; several Apply bars as one that applies and reverts
  /// them all; any other mix stacked in section order.
  static Widget _merged(List<Widget> footers) {
    if (footers.length == 1) return footers.single;
    if (footers.every((f) => f is CruxInspectorApplyBar)) {
      final bars = footers.cast<CruxInspectorApplyBar>();
      VoidCallback? all(VoidCallback? Function(CruxInspectorApplyBar) pick) {
        final calls = <VoidCallback>[];
        for (final bar in bars) {
          final call = pick(bar);
          if (call != null && !calls.contains(call)) calls.add(call);
        }
        if (calls.isEmpty) return null;
        return () {
          for (final call in calls) {
            call();
          }
        };
      }

      return CruxInspectorApplyBar(
        applyLabel: bars.first.applyLabel,
        revertLabel: bars.first.revertLabel,
        onApply: all((b) => b.onApply),
        onRevert: all((b) => b.onRevert),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < footers.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8),
          footers[i],
        ],
      ],
    );
  }
}

/// A gradient to the surface colour along the scroll view's bottom edge, shown
/// while the list continues below it.
class _ScrollFade extends StatelessWidget {
  const _ScrollFade({required this.visible});

  final ValueNotifier<bool> visible;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, more, _) => more
          ? IgnorePointer(
              child: Container(
                key: const ValueKey<String>('cruxInspectorScrollFade'),
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[surface.withValues(alpha: 0), surface],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Whether the focused text field is composing with an input method, which
/// owns Enter and Escape until it commits.
bool _composing() {
  final focused = FocusManager.instance.primaryFocus?.context;
  final editable = focused?.findAncestorWidgetOfExactType<EditableText>();
  if (editable == null) return false;
  final composing = editable.controller.value.composing;
  return composing.isValid && !composing.isCollapsed;
}

/// Whether a plain Enter, with focus where it is now, belongs to the section's
/// apply action rather than to the focused control: a single-line field
/// submits, a multi-line field takes a newline, and a button, checkbox or
/// dropdown keeps Enter as its own activation.
bool _enterApplies() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final editable = focused.findAncestorWidgetOfExactType<EditableText>();
  if (editable != null) {
    if (_composing()) return false;
    return editable.maxLines == 1;
  }
  final activate = Actions.maybeFind<ActivateIntent>(focused);
  return activate == null || !activate.isEnabled(const ActivateIntent());
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              // Its own node, so the heading does not name the rows'
              // container.
              container: true,
              header: true,
              child: Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One titled group of rows in a [CruxInspector].
///
/// [children] are `CruxFormRow`s (editable) and [CruxInspectorValueRow]s
/// (read-only), laid out in one label column [kCruxInspectorLabelWidth]
/// wide. [trailing] sits at the end of the heading: a Pro section's tier
/// badge goes there, and a gated section stays visible with it.
///
/// A section that applies on Apply puts a [CruxInspectorApplyBar] in
/// [footer] and passes the same action as [onSubmit], so a plain Enter in a
/// single-line field applies too.
class CruxInspectorSection extends StatefulWidget {
  /// Creates a section.
  const CruxInspectorSection({
    required this.title,
    required this.children,
    this.trailing,
    this.footer,
    this.onSubmit,
    super.key,
  });

  /// The localized section heading.
  final String title;

  /// The rows.
  final List<Widget> children;

  /// A widget at the end of the heading, typically a tier badge.
  final Widget? trailing;

  /// The section's commit buttons, typically a [CruxInspectorApplyBar].
  ///
  /// Inside a [CruxInspector] the footer is not drawn with the rows: the
  /// inspector pins it to its bottom edge, outside the scrolling list, so a
  /// tall section never hides its buttons. A section can be wrapped in any
  /// widget of the host's; the footer still reaches the bar. Outside an
  /// inspector the footer is drawn under the rows.
  final Widget? footer;

  /// Called on a plain Enter that the focused control does not take for
  /// itself. Null leaves Enter alone.
  final VoidCallback? onSubmit;

  @override
  State<CruxInspectorSection> createState() => _CruxInspectorSectionState();
}

class _CruxInspectorSectionState extends State<CruxInspectorSection> {
  _FooterHost? _host;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final submit = widget.onSubmit;
    if (submit == null || event is! KeyDownEvent) {
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
    if (!_enterApplies()) return KeyEventResult.ignored;
    submit();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _host?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = context.dependOnInheritedWidgetOfExactType<_FooterSlot>();
    final footer = widget.footer;
    final pinned = slot != null;
    if (!identical(_host, slot?.host)) _host?.remove(this);
    _host = slot?.host;
    if (slot != null && footer != null) {
      slot.host.put(this, slot.index, footer);
    } else {
      slot?.host.remove(this);
    }
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SectionHeading(title: widget.title, trailing: widget.trailing),
        CruxFormSection(
          labelWidth: kCruxInspectorLabelWidth,
          spacing: 6,
          children: widget.children,
        ),
        if (footer != null && !pinned) ...<Widget>[
          const SizedBox(height: 8),
          footer,
        ],
      ],
    );
    // Always present, so a section that gains or loses [onSubmit] as its
    // draft turns dirty keeps its subtree (and the focused field) in place.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: body,
    );
  }
}

/// A titled run of rows a [CruxInspector] builds lazily, for a list as long
/// as a clock net's sinks.
///
/// Outside an inspector it builds every row at once.
class CruxInspectorListSection extends StatelessWidget {
  /// Creates a list section.
  const CruxInspectorListSection({
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.trailing,
    super.key,
  });

  /// The localized section heading.
  final String title;

  /// The number of rows.
  final int itemCount;

  /// Builds row `index`, normally a [CruxInspectorValueRow].
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// A widget at the end of the heading, typically a tier badge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _SectionHeading(title: title, trailing: trailing),
      for (var i = 0; i < itemCount; i++) itemBuilder(context, i),
    ],
  );
}

/// A read-only label and value: one screen-reader node ("Type, $dff"), not a
/// Tab stop, and selectable for copying inside a [CruxInspector].
///
/// Technical values (names, widths, values) pass the product's technical
/// text style as [valueStyle].
class CruxInspectorValueRow extends StatelessWidget {
  /// Creates a value row.
  const CruxInspectorValueRow({
    required this.label,
    required this.value,
    this.valueStyle,
    super.key,
  });

  /// The localized label. Empty continues the row above (the second and
  /// later sinks of a net).
  final String label;

  /// The value.
  final String value;

  /// The value's text style; defaults to `bodySmall`.
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        label: label.isEmpty ? null : label,
        value: value,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: kCruxInspectorLabelWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: valueStyle ?? theme.textTheme.bodySmall,
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

/// Revert and Apply for a section whose edits apply together.
///
/// Pass null callbacks while there is nothing to revert or the draft is not
/// valid: the buttons render disabled.
///
/// As a [CruxInspectorSection.footer] it is pinned to the inspector's bottom
/// edge; several of them on one selection merge into one bar.
class CruxInspectorApplyBar extends StatelessWidget {
  /// Creates the bar.
  const CruxInspectorApplyBar({
    required this.applyLabel,
    required this.revertLabel,
    required this.onApply,
    required this.onRevert,
    super.key,
  });

  /// The localized apply label ("Apply", "Save").
  final String applyLabel;

  /// The localized revert label ("Revert").
  final String revertLabel;

  /// Applies the draft; null disables Apply.
  final VoidCallback? onApply;

  /// Discards the draft; null disables Revert.
  final VoidCallback? onRevert;

  @override
  // A Wrap, not a Row: in a narrow dock the two buttons plus a long label
  // ("Add Decoder", a translation) are wider than the Inspector, and a Row
  // overflows; the Wrap drops Apply onto its own line instead.
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        TextButton(onPressed: onRevert, child: Text(revertLabel)),
        FilledButton(onPressed: onApply, child: Text(applyLabel)),
      ],
    ),
  );
}
