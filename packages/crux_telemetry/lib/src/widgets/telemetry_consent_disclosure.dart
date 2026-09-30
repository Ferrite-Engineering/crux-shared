// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_telemetry/src/crux_telemetry_strings.dart';
import 'package:crux_telemetry/src/widgets/telemetry_consent_metrics.dart';
import 'package:flutter/material.dart';

/// The first-launch telemetry disclosure — shown until the user answers it,
/// and never again after.
///
/// A dumb leaf: it owns nothing but the pending toggle position and reports the
/// user's decision through [onContinue]. The hosting `TelemetryConsentGate`
/// owns the consent store, the visibility gate, and the documentation launch.
///
/// **Pre-armed on where that is lawful, and honest about it.** In most of the
/// world the toggle ships in the `enabled` position, because the suite makes
/// open-core collection default-on with an opt-out; everything else about the
/// surface is built so that the default is the *only* thumb on the scale. The
/// switch sits directly above Continue — not behind a "customise" affordance,
/// not below the fold, not styled down — and it carries a plain-language
/// label. There is exactly one button, so declining costs one tap (flip the
/// switch) and accepting costs zero; that gap is the default, and nothing else
/// widens it.
///
/// In the EEA, the UK, Switzerland and South Korea it ships **off**, because
/// consent must come first there. [initialEnabled] carries that decision in,
/// and it is required rather than defaulted precisely so no call site can
/// arrive at the old unconditional `true` by omission — the failure mode would
/// be silent, and it would be collection without consent.
///
/// **The prose is short by decision, not by omission.** An earlier revision
/// rendered the full collect / never-collect lists inline; they read as a
/// warning rather than a request, which is a poor trade when the honest
/// summary fits in two lines. What moved out did not disappear — the
/// exhaustive lists live on the suite telemetry page, and
/// [TelemetryConsentDisclosure.onLearnMore] is the only route a user has to
/// them from here. That makes the link part of the disclosure rather than a
/// convenience: a host that wires it to nothing has shipped a claim with no
/// way to check it.
///
/// Presentation follows the layout idiom the host already uses: a full-screen
/// sheet at phone widths ([isPhoneLayout]), a centred dialog card otherwise.
/// The package introduces no breakpoint of its own — the host passes the
/// classification it already made.
///
/// **It is a dialog to a keyboard and a screen reader, not only to the eye.**
/// Focus opens on the disclosure text itself, so a screen reader reads what is
/// being asked before any control, and Tab cycles through the documentation
/// link, the switch and Continue without leaving the dialog. The dialog is
/// announced by its title as focus enters, and Escape does not dismiss it. The
/// gate that mounts it keeps the app behind it out of reach.
class TelemetryConsentDisclosure extends StatefulWidget {
  /// Creates the disclosure.
  const TelemetryConsentDisclosure({
    required this.strings,
    required this.initialEnabled,
    required this.onContinue,
    required this.onLearnMore,
    this.metrics = const CruxTelemetryConsentMetrics(),
    this.isPhoneLayout = false,
    super.key,
  });

  /// Localized copy for the prose, the toggle and the buttons.
  final CruxTelemetryStrings strings;

  /// The position the toggle arrives in — `false` in the opt-in regions.
  ///
  /// Only the *initial* position: the user can move the switch either way from
  /// here, and [onContinue] reports where they left it. Hosts read this from
  /// `telemetryDefaultConsentProvider`.
  final bool initialEnabled;

  /// Sizing supplied by the host; hit targets are floored at
  /// [kTelemetryConsentMinTarget] regardless of what is passed.
  final CruxTelemetryConsentMetrics metrics;

  /// Whether to render the full-screen sheet (phone) rather than the centred
  /// dialog card (tablet / desktop).
  final bool isPhoneLayout;

  /// Invoked with the toggle's final position when the user taps Continue.
  final ValueChanged<bool> onContinue;

  /// Invoked when the user taps the documentation link.
  final VoidCallback onLearnMore;

  @override
  State<TelemetryConsentDisclosure> createState() =>
      _TelemetryConsentDisclosureState();
}

class _TelemetryConsentDisclosureState
    extends State<TelemetryConsentDisclosure> {
  late bool _enabled = widget.initialEnabled;

  @override
  Widget build(BuildContext context) {
    final content = _DisclosureContent(
      strings: widget.strings,
      metrics: widget.metrics,
      enabled: _enabled,
      onEnabledChanged: (value) => setState(() => _enabled = value),
      onContinue: () => widget.onContinue(_enabled),
      onLearnMore: widget.onLearnMore,
    );

    // The system back gesture does not close the disclosure: Continue is the
    // only way to answer, and a back press is not an answer. Leaving without
    // answering — quitting, closing the window — records nothing: consent
    // stays `unset`, which collects nothing, and the disclosure is shown again
    // on the next launch, because the gate mounts it whenever the stored
    // consent is `unset`. Only an answer stops it returning.
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          CruxModalSurface(
            label: widget.strings.consentTitle,
            child: widget.isPhoneLayout
                ? Material(
                    key: const Key('telemetryConsentSheet'),
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
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Card(
                          key: const Key('telemetryConsentDialog'),
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

/// Title, the two lists, the documentation link, the toggle, and Continue —
/// identical in the sheet and the dialog, so the two presentations cannot
/// disagree about what the user was told.
class _DisclosureContent extends StatelessWidget {
  const _DisclosureContent({
    required this.strings,
    required this.metrics,
    required this.enabled,
    required this.onEnabledChanged,
    required this.onContinue,
    required this.onLearnMore,
  });

  final CruxTelemetryStrings strings;
  final CruxTelemetryConsentMetrics metrics;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onContinue;
  final VoidCallback onLearnMore;

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
        // The prose's own viewport: generous when there is room, but capped
        // so it can never be the reason the documentation link, the switch
        // and Continue below it have none left. A bound, not a flex
        // factor, precisely so this can sit inside the scroll below — a
        // `Flexible` here would need that scroll's main axis to be finite,
        // and it is not.
        final bodyHeight = (available * 0.4).clamp(120.0, 320.0);
        return _content(context, theme, target, bodyHeight);
      },
    );
  }

  Widget _content(
    BuildContext context,
    ThemeData theme,
    double target,
    double bodyHeight,
  ) {
    // The whole surface scrolls as a last resort. At every size this
    // package documents supporting, the content below fits without it —
    // this exists so a smaller window, or a larger text scale than that,
    // degrades to "scroll to reach Continue" rather than to a clipped or
    // overflowing dialog.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.consentTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          // Still scrollable, and still only the prose. The body is two
          // lines at most locales but wraps far longer at large text
          // scales, and the documentation link, the switch and Continue
          // must stay pinned below it — an off switch that has scrolled off
          // the bottom is not an available choice.
          //
          // It is also where focus opens, and a Tab stop in its own right
          // whose name is the text: a screen reader reads what is being asked
          // before it reaches the switch, and a keyboard can scroll the text
          // when a large text scale makes it overflow.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bodyHeight),
            child: CruxScrollRegion(
              key: const Key('telemetryConsentBody'),
              semanticLabel: strings.consentBody,
              excludeContentSemantics: true,
              autofocus: true,
              builder: (context, controller) => SingleChildScrollView(
                key: const Key('telemetryConsentBodyScroll'),
                controller: controller,
                child: Text(
                  strings.consentBody,
                  style: TextStyle(
                    fontSize: metrics.bodyFontSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: target),
              child: TextButton.icon(
                key: const Key('telemetryConsentLearnMoreButton'),
                onPressed: onLearnMore,
                icon: Icon(Icons.open_in_new, size: metrics.iconSize),
                label: Text(strings.learnMore),
              ),
            ),
          ),
          const Divider(height: 24),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: target),
            child: SwitchListTile(
              key: const Key('telemetryConsentSwitch'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                strings.consentToggleLabel,
                style: TextStyle(fontSize: metrics.bodyFontSize),
              ),
              value: enabled,
              onChanged: onEnabledChanged,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: target),
            child: FilledButton(
              key: const Key('telemetryConsentContinueButton'),
              onPressed: onContinue,
              child: Text(strings.consentContinue),
            ),
          ),
        ],
      ),
    );
  }
}
