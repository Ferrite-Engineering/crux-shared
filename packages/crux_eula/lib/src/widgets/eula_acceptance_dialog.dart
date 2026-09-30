// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_eula/src/crux_eula_strings.dart';
import 'package:crux_eula/src/eula_document.dart';
import 'package:crux_eula/src/widgets/eula_metrics.dart';
import 'package:flutter/material.dart';

/// The first-launch licence agreement — shown until the user accepts it.
///
/// A dumb leaf: it owns nothing but the checkbox position and reports the
/// user's decision through [onAccept] / [onDecline]. The hosting
/// `CruxEulaGate` owns the acceptance store and the visibility gate.
///
/// **The checkbox is the point, and it is not decoration.** Accept is disabled
/// until it is ticked, so acceptance takes a deliberate second act rather than
/// one reflexive click on the only enabled button. That is what makes the
/// section 2.1 record ("indicating acceptance in the Application") worth
/// something: an agreement dismissed by a user who never registered there was
/// an agreement is weak evidence of assent, and the tick is cheap to give and
/// hard to give by accident.
///
/// **The agreement is present, not linked.** The full text scrolls inside the
/// dialog rather than sitting behind a "view licence" affordance, because a
/// user cannot have read what the application never showed them. The online
/// link is an addition to that, never a substitute, and it is hidden entirely
/// when the host binds no launcher — a dead link on this surface would be worse
/// than none.
///
/// **Declining is available and it is honest about its cost.** Section 2.1 says
/// the application does not proceed without acceptance, so the button says
/// "Decline and quit" rather than a softer word that would imply a third
/// outcome. It is hidden when the host binds no decline handler, rather than
/// rendering a button that does nothing.
///
/// Presentation follows the layout idiom the host already uses: a full-screen
/// sheet at phone widths ([isPhoneLayout]), a centred dialog card otherwise.
/// The package introduces no breakpoint of its own.
///
/// **It is a dialog to a keyboard and a screen reader, not only to the eye.**
/// Focus opens on the agreement itself, a Tab stop that scrolls with the arrow
/// and Page keys, and Tab cycles through the dialog's own controls without
/// leaving it. A screen reader announces the dialog by its title as focus
/// enters, and Escape does not dismiss it. The gate that mounts it keeps the
/// app behind it out of reach.
class CruxEulaAcceptanceDialog extends StatefulWidget {
  /// Creates the acceptance dialog.
  const CruxEulaAcceptanceDialog({
    required this.onAccept,
    this.strings = const CruxEulaStrings(),
    this.metrics = const CruxEulaMetrics(),
    this.isPhoneLayout = false,
    this.isReacceptance = false,
    this.onDecline,
    this.onOpenOnline,
    super.key,
  });

  /// Copy for the prose and the controls.
  final CruxEulaStrings strings;

  /// Sizing supplied by the host; hit targets are floored at
  /// [kCruxEulaMinTarget] regardless of what is passed.
  final CruxEulaMetrics metrics;

  /// Whether to render the full-screen sheet (phone) rather than the centred
  /// dialog card (tablet / desktop).
  final bool isPhoneLayout;

  /// Whether a *different, earlier* version was accepted before.
  ///
  /// Switches the line under the title from "please read and accept" to the
  /// section 2.3 notice, so a returning user is told why they are being asked
  /// again rather than left to assume the app forgot.
  final bool isReacceptance;

  /// Invoked when the user accepts.
  final VoidCallback onAccept;

  /// Invoked when the user declines. The button is hidden when this is null.
  final VoidCallback? onDecline;

  /// Invoked when the user opens the published agreement. The link is hidden
  /// when this is null.
  final VoidCallback? onOpenOnline;

  @override
  State<CruxEulaAcceptanceDialog> createState() =>
      _CruxEulaAcceptanceDialogState();
}

class _CruxEulaAcceptanceDialogState extends State<CruxEulaAcceptanceDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final content = _AcceptanceContent(
      strings: widget.strings,
      metrics: widget.metrics,
      isReacceptance: widget.isReacceptance,
      accepted: _accepted,
      onAcceptedChanged: (value) => setState(() => _accepted = value),
      onAccept: widget.onAccept,
      onDecline: widget.onDecline,
      onOpenOnline: widget.onOpenOnline,
    );

    // The system back gesture does not close the agreement: Accept and Decline
    // are the only answers, and a back press is neither. Leaving without
    // answering — quitting, closing the window — records nothing, and the
    // agreement is presented again on the next launch, because the gate mounts
    // it whenever the stored version is not the current one.
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          CruxModalSurface(
            label: widget.strings.title,
            child: widget.isPhoneLayout
                ? Material(
                    key: const Key('cruxEulaSheet'),
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: content,
                      ),
                    ),
                  )
                : Center(
                    child: SafeArea(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 640,
                          maxHeight: 720,
                        ),
                        child: Card(
                          key: const Key('cruxEulaDialog'),
                          // The surface names the dialog; a semantic
                          // container here would gather the loose prose
                          // into one unnamed node around every control.
                          semanticContainer: false,
                          margin: const EdgeInsets.all(24),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: content,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Title, the scrolling agreement, the open-source note, the checkbox and the
/// two buttons — identical in the sheet and the dialog, so the two
/// presentations cannot disagree about what the user was shown.
class _AcceptanceContent extends StatelessWidget {
  const _AcceptanceContent({
    required this.strings,
    required this.metrics,
    required this.isReacceptance,
    required this.accepted,
    required this.onAcceptedChanged,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenOnline,
  });

  final CruxEulaStrings strings;
  final CruxEulaMetrics metrics;
  final bool isReacceptance;
  final bool accepted;
  final ValueChanged<bool> onAcceptedChanged;
  final VoidCallback onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onOpenOnline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = metrics.effectiveTouchTarget;

    // The available height *at this point in the tree* — after the host's
    // card margin and padding, so it is the real budget the content has to
    // work with, not the window's raw size. Read before the scroll view
    // below, because that view's own main axis is unbounded and would
    // otherwise hide the number this depends on.
    return LayoutBuilder(
      builder: (context, outer) {
        final available = outer.maxHeight.isFinite
            ? outer.maxHeight
            : MediaQuery.sizeOf(context).height * 0.7;
        // The agreement's own viewport: whatever is left after a fixed
        // reserve for the chrome around it (title, checkbox, buttons — about
        // 390 lp with both optional controls bound, measured against the
        // shipped English copy), clamped to a sensible reading-pane range. A
        // bound, not a flex factor, precisely so this can sit inside the
        // scroll below — a `Flexible` here would need that scroll's main
        // axis to be finite, and it is not.
        final licenceHeight = (available - 400.0).clamp(72.0, 220.0);
        return _content(context, theme, target, licenceHeight);
      },
    );
  }

  Widget _content(
    BuildContext context,
    ThemeData theme,
    double target,
    double licenceHeight,
  ) {
    // The whole surface scrolls as a last resort. At every size this
    // package documents supporting, the content below fits without it —
    // this exists so a smaller window, or a larger text scale than that,
    // degrades to "scroll to reach Accept" rather than to a clipped or
    // overflowing dialog.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(strings.title, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 4),
          Text(
            isReacceptance ? strings.updatedNotice : strings.subtitle,
            style: TextStyle(
              fontSize: metrics.bodyFontSize,
              color: isReacceptance
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // The agreement itself, in a bounded box with its own scrollbar:
          // an Accept button that has scrolled off the bottom of a
          // 90-paragraph contract is not an available choice.
          //
          // It is also where focus opens, and a Tab stop in its own right: a
          // keyboard user scrolls it with the arrow and Page keys, and a
          // screen reader reads the dialog from the top rather than landing
          // on a checkbox about a text it has not reached.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: licenceHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: CruxScrollRegion(
                key: const Key('cruxEulaDocument'),
                semanticLabel: strings.documentLabel,
                autofocus: true,
                builder: (context, controller) => Scrollbar(
                  controller: controller,
                  child: SingleChildScrollView(
                    key: const Key('cruxEulaDocumentScroll'),
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    child: _Document(metrics: metrics),
                  ),
                ),
              ),
            ),
          ),
          if (onOpenOnline != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: target),
                child: TextButton.icon(
                  key: const Key('cruxEulaOpenOnlineButton'),
                  onPressed: onOpenOnline,
                  icon: Icon(Icons.open_in_new, size: metrics.iconSize),
                  label: Text(strings.openOnline),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            strings.openSourceNote,
            style: TextStyle(
              fontSize: metrics.bodyFontSize - 1,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 24),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: target),
            child: CheckboxListTile(
              key: const Key('cruxEulaAcceptCheckbox'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                strings.acceptCheckboxLabel,
                style: TextStyle(fontSize: metrics.bodyFontSize),
              ),
              value: accepted,
              onChanged: (value) => onAcceptedChanged(value ?? false),
            ),
          ),
          const SizedBox(height: 12),
          // `OverflowBar` rather than `Row`: at a phone width, or with
          // either button's label grown by translation or text scale, two
          // side-by-side buttons stop fitting. It lays them out as a row
          // when they fit and stacks them, still right-aligned, when they
          // do not — never clipping or overflowing either way.
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 12,
            overflowSpacing: 8,
            children: [
              if (onDecline != null)
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: target),
                  child: TextButton(
                    key: const Key('cruxEulaDeclineButton'),
                    onPressed: onDecline,
                    child: Text(strings.declineButton),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: target),
                child: FilledButton(
                  key: const Key('cruxEulaAcceptButton'),
                  // Disabled until the checkbox is ticked. This is the whole
                  // reason the checkbox exists; wiring Accept to fire
                  // regardless would leave a tick that means nothing.
                  onPressed: accepted ? onAccept : null,
                  child: Text(strings.acceptButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The agreement's blocks, headings styled and paragraphs spaced.
///
/// Built from [kCruxEulaDocument] rather than from a single string so headings
/// carry real emphasis without the dialog parsing prose at build time.
class _Document extends StatelessWidget {
  const _Document({required this.metrics});

  final CruxEulaMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in kCruxEulaDocument)
          Padding(
            padding: EdgeInsets.only(top: block.isHeading ? 14 : 8),
            child: Text(
              block.text,
              style: TextStyle(
                fontSize: metrics.bodyFontSize,
                height: 1.45,
                fontWeight: block.isHeading ? FontWeight.w700 : FontWeight.w400,
                color: block.isHeading
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
