// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds a named region's semantics with the description its content
/// currently asks for, or null when none does.
typedef CruxRegionHintBuilder =
    Widget Function(BuildContext context, String? hint, Widget child);

/// A named region whose description can be supplied by something inside it.
///
/// A region's accessible name identifies it and must not change with its
/// state; a description explains the state and is read after the name and
/// role. An empty dock is the case this exists for: its name stays its title
/// ("Details dock"), and while its empty state is mounted the empty message
/// ("Select a test to inspect.") becomes its description, so a screen reader
/// entering the region says why it is empty without the user switching to
/// browse mode. The message's own text node stays where it is for browse mode.
///
/// The region builds its own `Semantics` in [builder] (it knows its label,
/// container and child-node settings) and applies the hint with
/// [cruxRegionHintSemantics]. A [CruxRegionHint] anywhere below registers its
/// text with the nearest host; when several are mounted the most recently
/// mounted one is described.
///
/// The hint reaches the region one frame after the [CruxRegionHint] mounts
/// or changes, because a descendant cannot rebuild its ancestor during the
/// build that created it.
class CruxRegionHintHost extends StatefulWidget {
  /// Creates a host.
  const CruxRegionHintHost({
    required this.builder,
    required this.child,
    super.key,
  });

  /// Wraps [child] in the region's semantics, given the current hint.
  final CruxRegionHintBuilder builder;

  /// The region's content.
  final Widget child;

  @override
  State<CruxRegionHintHost> createState() => _CruxRegionHintHostState();
}

class _CruxRegionHintHostState extends State<CruxRegionHintHost> {
  final List<_CruxRegionHintState> _sources = <_CruxRegionHintState>[];
  String? _hint;
  bool _syncScheduled = false;

  void _register(_CruxRegionHintState source) {
    _sources
      ..remove(source)
      ..add(source);
    _scheduleSync();
  }

  void _unregister(_CruxRegionHintState source) {
    if (_sources.remove(source)) _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _syncScheduled = false;
        if (!mounted) return;
        final next = _sources.isEmpty ? null : _sources.last.widget.hint;
        final normalized = next == null || next.trim().isEmpty ? null : next;
        if (normalized != _hint) setState(() => _hint = normalized);
      })
      ..ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => _CruxRegionHintScope(
    state: this,
    child: widget.builder(context, _hint, widget.child),
  );
}

class _CruxRegionHintScope extends InheritedWidget {
  const _CruxRegionHintScope({required this.state, required super.child});

  final _CruxRegionHintHostState state;

  @override
  bool updateShouldNotify(_CruxRegionHintScope oldWidget) =>
      state != oldWidget.state;
}

/// Describes the nearest enclosing [CruxRegionHintHost] with [hint] for as
/// long as this widget is mounted. Renders [child] unchanged.
class CruxRegionHint extends StatefulWidget {
  /// Creates a hint source.
  const CruxRegionHint({required this.hint, required this.child, super.key});

  /// The description, already localized.
  final String hint;

  /// The content.
  final Widget child;

  @override
  State<CruxRegionHint> createState() => _CruxRegionHintState();
}

class _CruxRegionHintState extends State<CruxRegionHint> {
  _CruxRegionHintHostState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context
        .getInheritedWidgetOfExactType<_CruxRegionHintScope>()
        ?.state;
    if (host != _host) {
      _host?._unregister(this);
      _host = host?.._register(this);
    }
  }

  @override
  void didUpdateWidget(CruxRegionHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hint != widget.hint) _host?._scheduleSync();
  }

  @override
  void dispose() {
    _host?._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The region `Semantics` a [CruxRegionHintHost] builder returns.
///
/// [hint] is set both as the semantics hint, which the mobile and web
/// screen readers read after the name and role, and as the tooltip, because
/// the desktop accessibility bridge (`shell/platform/common` in the Flutter
/// engine) drops the hint and exposes the tooltip as the accessible
/// description instead. The name stays [label] in every state.
Widget cruxRegionHintSemantics({
  required String? label,
  required String? hint,
  required Widget child,
  bool container = true,
  bool explicitChildNodes = false,
}) => Semantics(
  container: container,
  explicitChildNodes: explicitChildNodes,
  label: label,
  hint: hint,
  tooltip: hint,
  child: child,
);
