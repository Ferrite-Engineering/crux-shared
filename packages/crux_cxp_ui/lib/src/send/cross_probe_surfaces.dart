// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cxp_strings.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_providers.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_runtime.dart';
import 'package:crux_cxp_ui/src/send/cross_probe_dispatcher.dart';
import 'package:crux_cxp_ui/src/send/cross_probe_targets.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets a product reword a shared line that is genuinely its own (the port
/// help that names its other protocol, the "nothing selected" noun). The
/// default changes nothing.
final Provider<CruxCxpStrings Function(CruxCxpStrings base)>
cruxCxpStringsCustomizerProvider =
    Provider<CruxCxpStrings Function(CruxCxpStrings base)>(
      (_) => _unchanged,
      name: 'cruxCxpStringsCustomizerProvider',
    );

CruxCxpStrings _unchanged(CruxCxpStrings base) => base;

/// The shared CXP strings for [context]'s locale, naming this product and
/// with its customizations applied.
CruxCxpStrings cruxCxpStringsOf(BuildContext context, CruxCxpReader read) {
  final product = cruxCxpDisplayName(
    read(cruxCxpProductBindingProvider).productName,
  );
  final base = CruxCxpStrings.of(context, product: product);
  return read(cruxCxpStringsCustomizerProvider)(base);
}

/// Tells the user how [outcome] ended: a failure is an error toast (which
/// is also announced), a send that landed is announced only, and a denial
/// was already explained by the gate.
void reportCrossProbeOutcome(
  BuildContext context,
  CrossProbeOutcome outcome,
  CruxCxpStrings strings,
) {
  final message = outcome.message(strings);
  if (message == null || !context.mounted) return;
  if (outcome.isFailure) {
    showCruxErrorSnack(
      context,
      message,
      key: const ValueKey('crossProbeOutcome'),
    );
  } else {
    announceCrux(context, message);
  }
}

/// Sends [selection] to [peer] through the gate and the dispatcher and
/// reports the outcome. The one send every surface uses.
Future<CrossProbeOutcome> sendCrossProbe(
  BuildContext context,
  WidgetRef ref, {
  required PeerIdentity peer,
  required CrossProbeSelection? selection,
  String? label,
}) async {
  // Read before any await: the surface that started the send may close.
  final strings = cruxCxpStringsOf(context, ref.read);
  final dispatcher = ref.read(crossProbeDispatcherProvider);
  final gate = ref.read(crossProbeGateProvider);
  if (gate != null && !await gate.admit(context, peer)) {
    return CrossProbeOutcome(
      CrossProbeOutcomeKind.denied,
      target: label ?? cruxCxpDisplayName(peer.productName),
    );
  }
  final outcome = await dispatcher.send(peer, selection, label: label);
  if (context.mounted) reportCrossProbeOutcome(context, outcome, strings);
  return outcome;
}

/// The menu entries for [targets]: one item per product, and a submenu of
/// windows for a product running in several.
List<CruxMenuEntry> _targetEntries(
  BuildContext context,
  WidgetRef ref,
  List<CrossProbeTarget> targets,
  CruxCxpStrings strings,
  CrossProbeSelection? Function() selection,
) {
  CruxMenuItem item(PeerIdentity peer, String label, String keyName) =>
      CruxMenuItem(
        key: ValueKey('crossProbeTarget:$keyName'),
        label: label,
        onSelected: () => unawaited(
          sendCrossProbe(
            context,
            ref,
            peer: peer,
            selection: selection(),
            label: label,
          ),
        ),
      );
  return <CruxMenuEntry>[
    for (final target in targets)
      if (!target.hasSeveralInstances)
        item(target.instances.single, target.label, target.productName)
      else
        CruxSubmenu(
          key: ValueKey('crossProbeTarget:${target.productName}'),
          label: target.label,
          entries: <CruxMenuEntry>[
            for (var i = 0; i < target.instances.length; i++)
              item(
                target.instances[i],
                strings.instanceLabel(target.label, i + 1),
                target.instances[i].peerId,
              ),
          ],
        ),
  ];
}

/// The "Cross-probe to" submenu for a context menu (a [CruxContextMenuRegion]
/// or [CruxOverflowMenu]) on anything selectable.
///
/// [selection] is resolved when a target is chosen, not when the menu is
/// built. With no peer running the entry is one disabled item, "Cross-probe
/// to (no peers running)", whose tooltip says what to start.
CruxMenuEntry crossProbeMenuEntry(
  BuildContext context,
  WidgetRef ref, {
  required CrossProbeSelection? Function() selection,
  IconData icon = Icons.sensors,
}) {
  final strings = cruxCxpStringsOf(context, ref.read);
  final targets = ref.read(crossProbeTargetsProvider);
  if (targets.isEmpty) {
    return CruxSubmenu(
      key: const ValueKey('crossProbeSubmenu'),
      label: strings.noPeersRunning,
      tooltip: strings.noPeersRunningHelp,
      icon: icon,
      enabled: false,
      entries: const <CruxMenuEntry>[],
    );
  }
  return CruxSubmenu(
    key: const ValueKey('crossProbeSubmenu'),
    label: strings.crossProbeTo,
    icon: icon,
    entries: _targetEntries(context, ref, targets, strings, selection),
  );
}

/// The Cross-probe Selection command (palette, menu bar, and the
/// Cmd/Ctrl+Shift+Enter binding).
///
/// One target: sends at once. Several: opens the same target list as a menu
/// at [anchor] (the selection's position in global coordinates; the focused
/// control's corner when null), never a dialog. Nothing selected, the server
/// off or no peer running is reported, never silent.
///
/// The keyboard binding must not fire while a text field has focus: check
/// `cruxTextInputFocused()` (crux_ide_layout) before calling this from a
/// shortcut, and leave the key to the field.
Future<void> runCrossProbeSelection(
  BuildContext context,
  WidgetRef ref, {
  required CrossProbeSelection? selection,
  Offset? anchor,
}) async {
  final strings = cruxCxpStringsOf(context, ref.read);
  void report(CrossProbeOutcomeKind kind) =>
      reportCrossProbeOutcome(context, CrossProbeOutcome(kind), strings);
  if (selection == null || selection.isEmpty) {
    report(CrossProbeOutcomeKind.nothingSelected);
    return;
  }
  if (!ref.read(cruxCxpServerStatusProvider).running) {
    report(CrossProbeOutcomeKind.serverOff);
    return;
  }
  final targets = ref.read(crossProbeTargetsProvider);
  if (targets.isEmpty) {
    report(CrossProbeOutcomeKind.noPeers);
    return;
  }
  if (targets.length == 1 && !targets.single.hasSeveralInstances) {
    final target = targets.single;
    await sendCrossProbe(
      context,
      ref,
      peer: target.instances.single,
      selection: selection,
      label: target.label,
    );
    return;
  }
  final position =
      anchor ??
      FocusManager.instance.primaryFocus?.rect.bottomLeft ??
      Offset.zero;
  await showCruxContextMenu(
    context,
    globalPosition: position,
    entries: _targetEntries(context, ref, targets, strings, () => selection),
  );
}

/// A one-click "Cross-probe to WaveCrux" button for a surface with one
/// obvious target.
///
/// Sends to [productName]'s only window at once; with several windows it
/// opens them as a menu below itself. Disabled, saying why in its tooltip,
/// while that product is not running. The same send, outcome and gate as
/// every other surface.
class CrossProbeToButton extends ConsumerWidget {
  /// Creates the button.
  const CrossProbeToButton({
    required this.productName,
    required this.selection,
    this.icon = Icons.open_in_new,
    this.tooltip,
    super.key,
  });

  /// The target product's wire name: `wavecrux`.
  final String productName;

  /// Resolves the selection when pressed.
  final CrossProbeSelection? Function() selection;

  /// The glyph.
  final IconData icon;

  /// The tooltip and accessible name; "Cross-probe to WaveCrux" by default.
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = cruxCxpStringsOf(context, ref.read);
    final target = ref
        .watch(crossProbeTargetsProvider)
        .where((t) => t.productName == productName.toLowerCase())
        .firstOrNull;
    final label = strings.crossProbeToProduct(
      cruxCxpDisplayName(productName),
    );
    return IconButton(
      key: ValueKey('crossProbeTo:$productName'),
      icon: Icon(icon),
      tooltip: target == null
          ? '${tooltip ?? label}. ${strings.noPeersRunningHelp}'
          : tooltip ?? label,
      onPressed: target == null
          ? null
          : () => _press(context, ref, target, strings),
    );
  }

  void _press(
    BuildContext context,
    WidgetRef ref,
    CrossProbeTarget target,
    CruxCxpStrings strings,
  ) {
    if (!target.hasSeveralInstances) {
      unawaited(
        sendCrossProbe(
          context,
          ref,
          peer: target.instances.single,
          selection: selection(),
          label: target.label,
        ),
      );
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final entries = _targetEntries(
      context,
      ref,
      <CrossProbeTarget>[
        target,
      ],
      strings,
      selection,
    );
    // A single several-window target renders as one submenu; open its
    // windows directly.
    final windows = entries.single is CruxSubmenu
        ? (entries.single as CruxSubmenu).entries
        : entries;
    unawaited(
      showCruxContextMenu(context, globalPosition: anchor, entries: windows),
    );
  }
}
