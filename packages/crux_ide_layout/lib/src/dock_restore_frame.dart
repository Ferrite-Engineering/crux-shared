// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// The fixed frame around an IDE layout and the restore bars of its collapsed
/// dock regions.
///
/// A hidden dock region leaves a slim bar of its tab icons along its window
/// edge, and a click on one reopens the region with that tab active. The
/// frame places up to three of those bars around [child] (the IDE layout)
/// and always produces this one tree, whatever is collapsed:
///
/// ```text
/// Row(
///   leftBar?,
///   Expanded(Column(Expanded(child), bottomBar?)),
///   rightBar?,
/// )
/// ```
///
/// One tree shape is the point. Every product once picked the wrapper by
/// which regions were collapsed (the bare child, a `Column`, a `Row`, a `Row`
/// around a `Column`), so each dock toggle changed the widget type directly
/// above the IDE layout and Flutter discarded and rebuilt everything beneath
/// it: every dock, the pane `ProviderScope`, the show/hide animation, and
/// every dock's scroll position. In one product a `GlobalKey`'d canvas then
/// migrated across a freshly built semantics boundary, which is what
/// `flushSemantics` asserts on while a screen reader is attached. With a
/// fixed shape and keyed slots, a bar appearing or vanishing is matched by
/// identity and touches nothing but itself; the subtree under [child] keeps
/// its elements and its state.
///
/// The bars are supplied built, so the frame carries no dock vocabulary and
/// no dependency on any dock widget: each product keeps the widget that owns
/// its entries (ids, icons, localized labels, reveal callbacks) and delegates
/// its `build` to this frame. The slots are keyed by the frame
/// ([leftBarKey], [rightBarKey], [bottomBarKey], [centerKey]); a bar passed in
/// should not repeat them.
class CruxDockRestoreFrame extends StatelessWidget {
  /// Creates the frame around [child], with whichever bars are showing.
  const CruxDockRestoreFrame({
    required this.child,
    this.leftBar,
    this.rightBar,
    this.bottomBar,
    super.key,
  });

  /// The key of the slot holding [leftBar].
  static const Key leftBarKey = ValueKey<String>('dockRestoreBar.left');

  /// The key of the slot holding [rightBar].
  static const Key rightBarKey = ValueKey<String>('dockRestoreBar.right');

  /// The key of the slot holding [bottomBar].
  static const Key bottomBarKey = ValueKey<String>('dockRestoreBar.bottom');

  /// The key of the centre slot: the `Expanded` holding [child] and
  /// [bottomBar].
  static const Key centerKey = ValueKey<String>('dockRestoreBars.center');

  /// The IDE layout being framed.
  final Widget child;

  /// The restore bar for a collapsed left region, or `null` while it is open.
  final Widget? leftBar;

  /// The restore bar for a collapsed right region, or `null` while it is
  /// open.
  final Widget? rightBar;

  /// The restore bar for a collapsed bottom region, or `null` while it is
  /// open.
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final leftBar = this.leftBar;
    final rightBar = this.rightBar;
    final bottomBar = this.bottomBar;
    return Row(
      children: <Widget>[
        if (leftBar != null) KeyedSubtree(key: leftBarKey, child: leftBar),
        Expanded(
          key: centerKey,
          child: Column(
            children: <Widget>[
              Expanded(child: child),
              if (bottomBar != null)
                KeyedSubtree(key: bottomBarKey, child: bottomBar),
            ],
          ),
        ),
        if (rightBar != null) KeyedSubtree(key: rightBarKey, child: rightBar),
      ],
    );
  }
}
