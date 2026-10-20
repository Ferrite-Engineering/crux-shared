// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Synthetic widget shapes exercising the route-mount analysis in
// `../route_mounted_scope_leak_test.dart`.
//
// The corpus is the mutation verification of that guard, kept standing rather
// than performed once by hand: `leakySearchDialog` reproduces a NetCrux beta
// bug verbatim (a `ConsumerStatefulWidget` pushed with `showDialog`, reading
// per-tab providers from its `State`, with nothing re-binding the container),
// and `fixedSearchDialog` reproduces the shipped fix. The guard must flag the
// first and clear the second. Every other shape is a variation the analysis has
// to get right, plus controls that must stay clean so a guard that passes by
// over-reporting fails here.
//
// This file is deliberately outside `lib/`, so the production scan never sees
// it; it is resolved on its own by the shape test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stands in for a per-tab provider — `hierarchyTreeProvider` in the NetCrux
/// reproduction.
final perTabProvider = Provider<int>((ref) => 0);

/// A provider that is *not* per-tab. Reading only this must not flag.
final rootProvider = Provider<int>((ref) => 1);

// --- Shape 1: the NetCrux search-dialog bug, verbatim. -----------------------
// A ConsumerStatefulWidget pushed on the root navigator by `showDialog`. The
// read lives in its State, not in the widget class, and not in the builder.

class LeakySearchDialog extends ConsumerStatefulWidget {
  const LeakySearchDialog({super.key});

  @override
  ConsumerState<LeakySearchDialog> createState() => _LeakySearchDialogState();
}

class _LeakySearchDialogState extends ConsumerState<LeakySearchDialog> {
  @override
  Widget build(BuildContext context) => Text('${ref.watch(perTabProvider)}');
}

Future<void> leakySearchDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const LeakySearchDialog(),
  );
}

// --- Shape 2: its shipped fix. ----------------------------------------------
// Same widget, same route API; the builder re-binds the active tab's container.

Future<void> fixedSearchDialog(
  BuildContext context,
  ProviderContainer container,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: const LeakySearchDialog(),
    ),
  );
}

// --- Shape 3: the read is in the widget class body, not a State. -------------

class LeakyStatelessPanel extends ConsumerWidget {
  const LeakyStatelessPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(perTabProvider)}');
}

Future<void> leakyBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const LeakyStatelessPanel(),
  );
}

// --- Shape 4: the read is behind a helper method on the State. ---------------
// The call-graph walk has to follow the helper; a body-only scan misses it.

class LeakyIndirectDialog extends ConsumerStatefulWidget {
  const LeakyIndirectDialog({super.key});

  @override
  ConsumerState<LeakyIndirectDialog> createState() =>
      _LeakyIndirectDialogState();
}

class _LeakyIndirectDialogState extends ConsumerState<LeakyIndirectDialog> {
  int _load() => ref.read(perTabProvider);

  @override
  Widget build(BuildContext context) => Text('${_load()}');
}

Future<void> leakyIndirectDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    pageBuilder: (_, _, _) => const LeakyIndirectDialog(),
  );
}

// --- Shape 5: `Navigator.push` with a `MaterialPageRoute`. -------------------
// The builder is nested one constructor deep inside the route argument.

Future<void> leakyPushedPage(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => const LeakyStatelessPanel()),
  );
}

// --- Shape 6: the widget installs its own scope. -----------------------------
// A dialog that wraps its own subtree is fixed even though the builder does
// not wrap it.

class SelfScopedDialog extends ConsumerWidget {
  const SelfScopedDialog({required this.container, super.key});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      UncontrolledProviderScope(
        container: container,
        child: const LeakyStatelessPanel(),
      );
}

Future<void> selfScopedDialog(
  BuildContext context,
  ProviderContainer container,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => SelfScopedDialog(container: container),
  );
}

// --- Control 1: a dialog that reads only root-scoped state. ------------------

class RootOnlyDialog extends ConsumerWidget {
  const RootOnlyDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(rootProvider)}');
}

Future<void> rootOnlyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RootOnlyDialog(),
  );
}

// --- Control 2: a per-tab read in a widget that is never route-mounted. ------
// In-tree widgets are the sibling guard's territory, not this one's.

class InTreePanel extends ConsumerWidget {
  const InTreePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(perTabProvider)}');
}

// --- Control 3: a dialog taking its data by constructor parameter. -----------
// It reads nothing, so the root container never comes into it.

class InertDialog extends StatelessWidget {
  const InertDialog({required this.value, super.key});

  final int value;

  @override
  Widget build(BuildContext context) => Text('$value');
}

Future<void> inertDialog(BuildContext context, int value) {
  return showDialog<void>(
    context: context,
    builder: (_) => InertDialog(value: value),
  );
}

// --- Control 4: the read lives in a collaborator, not in the widget. ---------
// Deliberately NOT flagged. Following the call graph out of a widget attributes
// a collaborator's reads to the widget, and in a real product tree that
// misfires badly: a dialog whose only sin is calling a workspace API to open a
// new tab was reported as reading fourteen per-tab providers. See the
// limitation note in `../route_mounted_scope_leak_test.dart`.

class _Collaborator {
  int load(WidgetRef ref) => ref.read(perTabProvider);
}

class CollaboratorReadingDialog extends ConsumerWidget {
  const CollaboratorReadingDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${_Collaborator().load(ref)}');
}

Future<void> collaboratorReadingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const CollaboratorReadingDialog(),
  );
}

// --- Shape 7: the builder installs the scope through a named helper. ---------
// LintCrux writes `wrapInActiveTabScope(context, const FooDialog())` rather
// than an inline `UncontrolledProviderScope`. Without one hop of resolution,
// every call site of such a helper reads as a violation.

/// Stands in for LintCrux's `wrapInActiveTabScope`.
Widget wrapInActiveTabScope(BuildContext context, Widget child) =>
    UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: child,
    );

class HelperScopedPanel extends ConsumerWidget {
  const HelperScopedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(perTabProvider)}');
}

Future<void> helperScopedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => wrapInActiveTabScope(context, const HelperScopedPanel()),
  );
}

// --- Shape 8: the Crux Desktop opener, bug and fix. --------------------------
// `showCruxDialog` also mounts on the root navigator. The scanner matches the
// opener by name, so this same-named local stand-in proves it sees the call
// without this package depending on the layout package that declares it.

/// Stands in for the layout package's `showCruxDialog`.
Future<T?> showCruxDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? modalGuardKey,
  NavigatorState? navigator,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
);

class LeakyCruxDialog extends ConsumerWidget {
  const LeakyCruxDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(perTabProvider)}');
}

Future<bool?> leakyCruxDialog(BuildContext context) {
  return showCruxDialog<bool>(
    context: context,
    modalGuardKey: 'leaky',
    builder: (_) => const LeakyCruxDialog(),
  );
}

Future<bool?> fixedCruxDialog(
  BuildContext context,
  ProviderContainer container,
) {
  return showCruxDialog<bool>(
    context: context,
    modalGuardKey: 'fixed',
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: const LeakyCruxDialog(),
    ),
  );
}

// --- Shape 9: the dialog goes on the tab's own navigator. ------------------
// A route pushed on the tab's nested navigator is built under the tab's scope,
// so it needs no second scope. Recognized only when the navigator visibly comes
// from the tab navigators; any other `navigator:` stays a violation.

/// Stands in for crux_workspace's `cruxTabNavigatorOf`.
NavigatorState? cruxTabNavigatorOf(BuildContext context) =>
    Navigator.maybeOf(context);

/// Stands in for crux_workspace's `CruxTabNavigators`.
class TabNavigators {
  NavigatorState? navigatorFor(String tabId) => null;
}

class TabNavigatorDialog extends ConsumerWidget {
  const TabNavigatorDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(perTabProvider)}');
}

Future<void> tabNavigatorDialog(BuildContext context) {
  return showCruxDialog<void>(
    context: context,
    navigator: cruxTabNavigatorOf(context),
    builder: (_) => const TabNavigatorDialog(),
  );
}

Future<void> activeTabNavigatorDialog(
  BuildContext context,
  TabNavigators navigators,
) {
  return showCruxDialog<void>(
    context: context,
    navigator: navigators.navigatorFor('tab-1'),
    builder: (_) => const TabNavigatorDialog(),
  );
}

class ArbitraryNavigatorDialog extends ConsumerWidget {
  const ArbitraryNavigatorDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(perTabProvider)}');
}

Future<void> arbitraryNavigatorDialog(BuildContext context) {
  return showCruxDialog<void>(
    context: context,
    navigator: Navigator.of(context, rootNavigator: true),
    builder: (_) => const ArbitraryNavigatorDialog(),
  );
}
