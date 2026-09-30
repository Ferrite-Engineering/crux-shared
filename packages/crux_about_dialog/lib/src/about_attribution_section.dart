// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A collapsible third-party attribution block for the `CruxAboutDialog` body.
///
/// Shows a section header, a short description, and a tap-to-expand license
/// disclosure. When expanded the full license text is revealed in a selectable
/// monospace panel and scrolled into view. Products pass one of these per
/// bundled dependency they want to credit (e.g. WaveCrux credits the `wellen`
/// waveform parser); apps with nothing to attribute simply pass none.
class AboutAttributionSection extends StatefulWidget {
  /// Creates an attribution section.
  const AboutAttributionSection({
    required this.title,
    required this.description,
    required this.licenseHeader,
    required this.licenseText,
    super.key,
  });

  /// Section header (e.g. the dependency name, "Wellen").
  final String title;

  /// One- or two-sentence description of what the dependency provides and
  /// under which license it is used.
  final String description;

  /// Label for the expand/collapse disclosure row (e.g. "BSD 3-Clause
  /// License").
  final String licenseHeader;

  /// Full license text revealed when the disclosure is expanded.
  final String licenseText;

  @override
  State<AboutAttributionSection> createState() =>
      _AboutAttributionSectionState();
}

class _AboutAttributionSectionState extends State<AboutAttributionSection> {
  bool _expanded = false;
  final GlobalKey<State<StatefulWidget>> _licenseKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AboutSectionHeader(label: widget.title),
          const SizedBox(height: 6),
          Text(
            widget.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              final wasExpanded = _expanded;
              setState(() => _expanded = !_expanded);
              if (!wasExpanded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = _licenseKey.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(
                      ctx,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.licenseHeader,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Container(
              key: _licenseKey,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                widget.licenseText,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small primary-colored section header used throughout the About dialog body.
///
/// Exported so attribution sections and the main version section render the
/// same header style.
class AboutSectionHeader extends StatelessWidget {
  /// Creates a section header rendering [label].
  const AboutSectionHeader({required this.label, super.key});

  /// The header text.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}
