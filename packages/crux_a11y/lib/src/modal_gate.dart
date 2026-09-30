// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Shows [modal] over [child] as a modal surface that a keyboard and a screen
/// reader treat as one, without pushing a route.
///
/// A gate that must be answered before the app can be used — a licence
/// agreement, a consent disclosure — often sits above the app's `Navigator`,
/// where no route can be pushed. Stacking the surface over the app with a
/// `ModalBarrier` stops the pointer and hides the app from a screen reader,
/// but not from the keyboard: focus stays on the app behind, Tab walks
/// controls the user cannot see (each one silent, because the barrier blocks
/// their semantics), and Enter can activate one of them. This widget supplies
/// the rest of what a route would:
///
/// - While [modal] is non-null, [child] is excluded from focus and from
///   semantics. Nothing behind the surface can be focused — by Tab, by a
///   pointer, or by app code calling `requestFocus` — so no key reaches it.
/// - When [modal] becomes null and focus has fallen to nowhere, focus moves to
///   the first focusable control in [child]: the control a scope remembers
///   as last focused, or else the first in its traversal order. That is how a
///   second gate nested in [child] receives focus when the first is answered.
///
/// [modal] owns its own presentation: its barrier, and a [CruxModalSurface]
/// around the dialog so focus is trapped inside it and it is announced by its
/// title. [child] keeps its element and state across both transitions.
class CruxModalGate extends StatefulWidget {
  /// Creates a gate showing [modal], when non-null, over [child].
  const CruxModalGate({required this.child, this.modal, super.key});

  /// The app content the gate covers.
  final Widget child;

  /// The modal surface, or `null` when the gate is open.
  final Widget? modal;

  @override
  State<CruxModalGate> createState() => _CruxModalGateState();
}

class _CruxModalGateState extends State<CruxModalGate> {
  /// Inert: never focused itself and never a Tab stop. It exists so the gate
  /// can find the focus nodes inside [CruxModalGate.child].
  final FocusNode _content = FocusNode(
    debugLabel: 'CruxModalGate content',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void didUpdateWidget(CruxModalGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modal != null && widget.modal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusContent());
    }
  }

  /// Moves focus into the content once the surface has gone, unless the user
  /// or the app has already put it somewhere.
  void _focusContent() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary is! FocusScopeNode) return;

    final candidates = _content.traversalDescendants
        .where((node) => node is! FocusScopeNode && node.context != null)
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final first = candidates.first;

    final policy =
        FocusTraversalGroup.maybeOf(first.context!) ??
        ReadingOrderTraversalPolicy();
    // The policy answers within `first`'s scope: the control that scope last
    // had focused, or else its first in traversal order. It can also answer
    // with a scope, or with a control outside the content when that scope
    // lies above the gate; in either case `first` is the answer instead.
    (switch (policy.findFirstFocus(first)) {
      final FocusNode preferred
          when preferred is! FocusScopeNode &&
              preferred.canRequestFocus &&
              preferred.ancestors.contains(_content) =>
        preferred,
      _ => first,
    }).requestFocus();
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = widget.modal != null;
    // One structure in every state, so the content is never remounted when
    // the gate opens or closes.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          excluding: showing,
          child: ExcludeFocus(
            excluding: showing,
            child: Focus(
              focusNode: _content,
              includeSemantics: false,
              child: widget.child,
            ),
          ),
        ),
        ?widget.modal,
      ],
    );
  }
}

/// The dialog inside a modal surface: announced as one named container, with
/// keyboard focus kept inside it and Escape unable to dismiss it.
///
/// - [label], normally the dialog's title, names a container that
///   `scopesRoute` and `namesRoute`, so a screen reader announces the dialog
///   by name as focus enters it.
/// - A focus scope keeps Tab and Shift+Tab cycling through the dialog's own
///   controls; they never leave it for something outside the surface.
/// - Escape is consumed and does nothing. A surface that must be answered is
///   not dismissed by a key that is not an answer.
///
/// Give the control that should hold focus when the surface opens
/// `autofocus: true`; normally the first one, so a screen reader reads the
/// dialog from the top.
class CruxModalSurface extends StatelessWidget {
  /// Creates the surface around [child], announced as [label].
  const CruxModalSurface({required this.label, required this.child, super.key});

  /// The dialog's accessible name, normally its title.
  final String label;

  /// The dialog.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: label,
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: DoNothingAction(),
        },
        child: FocusScope(
          debugLabel: 'CruxModalSurface $label',
          includeSemantics: false,
          child: child,
        ),
      ),
    );
  }
}
