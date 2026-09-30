// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// One serialized semantics node, as the engine would see it.
class RecordedSemanticsNode {
  /// Creates a record of one `updateNode` call.
  const RecordedSemanticsNode({
    required this.id,
    required this.label,
    required this.identifier,
    required this.traversalParent,
    required this.children,
  });

  /// The node id.
  final int id;

  /// The node label.
  final String label;

  /// The node identifier.
  final String identifier;

  /// The traversal parent id the framework resolved, or -1.
  final int traversalParent;

  /// The `childrenInTraversalOrder` list — the only structure the bridge uses.
  final List<int> children;

  @override
  String toString() =>
      'node $id label="$label" identifier="$identifier" '
      'traversalParent=$traversalParent children=$children';
}

/// A node the bridge would reject, with the update it appeared in.
class SemanticsOrphan {
  /// Creates an orphan report.
  const SemanticsOrphan(this.node, this.updateIndex, this.reason);

  /// The offending node.
  final RecordedSemanticsNode node;

  /// 1-based index of the update since the last [SemanticsOrphanGuard.reset].
  final int updateIndex;

  /// Why the engine would reject it.
  final String reason;

  @override
  String toString() => 'update #$updateIndex: $node -> $reason';
}

/// Shadow of the engine's accessibility tree, rebuilt from every update.
///
/// The parent map is maintained the way `flutter::AccessibilityBridge` and
/// `ui::AXTree` maintain theirs: a node's parent is whichever updated node
/// last listed it as a child. A serialized node that ends an update without a
/// parent reachable from the root is an orphan.
///
/// Enable semantics (`tester.ensureSemantics()`) before driving the surface
/// under test. The automated test binding can split the very first update
/// when semantics are switched on in the middle of a running transition; the
/// production engine does not, so a first update without root 0 in that
/// situation is a harness artifact rather than a defect.
class SemanticsOrphanGuard {
  SemanticsOrphanGuard._();

  /// The process-wide guard the recording builder reports into.
  static final SemanticsOrphanGuard instance = SemanticsOrphanGuard._();

  final Map<int, int?> _parentOf = <int, int?>{};
  final Map<int, List<int>> _childrenOf = <int, List<int>>{};
  final Map<int, RecordedSemanticsNode> _last = <int, RecordedSemanticsNode>{};
  final List<RecordedSemanticsNode> _pending = <RecordedSemanticsNode>[];

  /// Every orphan seen since the last [reset].
  final List<SemanticsOrphan> orphans = <SemanticsOrphan>[];

  /// Number of updates seen since the last [reset].
  int updates = 0;

  bool _hasRoot = false;

  /// Forgets everything. Call at the start of each test.
  void reset() {
    _parentOf.clear();
    _childrenOf.clear();
    _last.clear();
    _pending.clear();
    orphans.clear();
    updates = 0;
    _hasRoot = false;
  }

  void _record(RecordedSemanticsNode n) => _pending.add(n);

  void _commit() {
    if (_pending.isEmpty) return;
    updates++;
    final pending = <int, RecordedSemanticsNode>{
      for (final RecordedSemanticsNode n in _pending) n.id: n,
    };
    final claimed = <int>{};
    for (final p in pending.values) {
      for (final c in _childrenOf[p.id] ?? const <int>[]) {
        if (!p.children.contains(c) && _parentOf[c] == p.id) {
          _parentOf[c] = null;
        }
      }
      _childrenOf[p.id] = List<int>.of(p.children);
      for (final c in p.children) {
        _parentOf[c] = p.id;
        claimed.add(c);
      }
    }
    if (!_hasRoot) {
      if (pending.containsKey(0)) {
        _hasRoot = true;
        _parentOf[0] = null;
      } else {
        orphans.add(
          SemanticsOrphan(
            pending.values.first,
            updates,
            'first update does not contain root 0; the engine would crown an '
            'arbitrary node as the native root',
          ),
        );
      }
    }
    for (final n in pending.values) {
      _last[n.id] = n;
      if (n.id == 0) continue;
      final parent = _parentOf[n.id];
      if (parent == null || !_reachable(parent)) {
        orphans.add(
          SemanticsOrphan(
            n,
            updates,
            claimed.contains(n.id)
                ? 'claimed only by a node that is itself not in the tree'
                : 'not claimed by any childrenInTraversalOrder',
          ),
        );
      }
    }
    final dead = <int>[
      for (final int id in _parentOf.keys)
        if (id != 0 && !_reachable(id)) id,
    ];
    for (final id in dead) {
      _parentOf.remove(id);
      _childrenOf.remove(id);
    }
    _pending.clear();
  }

  bool _reachable(int id) {
    int? cur = id;
    var hops = 0;
    while (cur != null && cur != 0) {
      if (!_parentOf.containsKey(cur)) return false;
      cur = _parentOf[cur];
      if (++hops > 100000) return false;
    }
    return cur == 0 && _hasRoot;
  }

  /// Fails the current test if any orphan was recorded since [reset].
  void check({String context = ''}) {
    if (orphans.isEmpty) return;
    final b = StringBuffer()
      ..writeln(
        'Semantics orphans detected $context '
        '(${orphans.length} over $updates updates):',
      );
    for (final o in orphans) {
      b.writeln('  $o');
    }
    fail(b.toString());
  }

  /// Describes the last serialized form of node [id].
  String describe(int id) =>
      _last[id]?.toString() ?? 'node $id (never serialized)';
}

class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this._inner);
  final ui.SemanticsUpdateBuilder _inner;

  @override
  ui.SemanticsUpdate build() {
    SemanticsOrphanGuard.instance._commit();
    return _inner.build();
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _inner.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  // `updateNode` has several dozen named parameters that change between
  // framework releases; forwarding by invocation keeps this pinned to the
  // handful of fields the invariant needs.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode && invocation.isMethod) {
      final a = invocation.namedArguments;
      SemanticsOrphanGuard.instance._record(
        RecordedSemanticsNode(
          id: a[#id] as int,
          label: a[#label] as String,
          identifier: a[#identifier] as String,
          traversalParent: a[#traversalParent] as int,
          children: List<int>.of(a[#childrenInTraversalOrder] as Int32List),
        ),
      );
      return Function.apply(_inner.updateNode, const <Object?>[], a);
    }
    return super.noSuchMethod(invocation);
  }
}

/// Routes every semantics update through [SemanticsOrphanGuard].
///
/// Mix into a test binding when a test file already needs its own binding
/// class; otherwise use [SemanticsOrphanTestBinding].
mixin SemanticsOrphanRecording on SemanticsBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingBuilder(super.createSemanticsUpdateBuilder());
}

/// The default widget-test binding with orphan recording installed.
class SemanticsOrphanTestBinding extends AutomatedTestWidgetsFlutterBinding
    with SemanticsOrphanRecording {
  SemanticsOrphanTestBinding._();

  /// Installs the binding; idempotent. Call first thing in `main()`.
  factory SemanticsOrphanTestBinding.ensureInitialized() =>
      _instance ??= SemanticsOrphanTestBinding._();

  static SemanticsOrphanTestBinding? _instance;
}
