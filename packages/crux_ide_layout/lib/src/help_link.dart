// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A small, unobtrusive help icon that opens [url] in the system browser —
/// the suite-standard contextual documentation link.
///
/// Renders as a muted `Icons.help_outline` icon button. Hosts place one
/// beside a setting section header or in a complex dialog's title row,
/// pointing at the product website's matching documentation page.
///
/// [tooltip] is caller-supplied and already localized (the suite copy is
/// "Learn more"). In tests, supply [onTap] to intercept the launch call
/// without requiring a platform channel.
class CruxHelpLink extends StatelessWidget {
  /// Creates a help link for [url].
  const CruxHelpLink({
    required this.url,
    required this.tooltip,
    this.onTap,
    super.key,
  });

  /// The documentation URL to open.
  final String url;

  /// Localized tooltip shown on hover / long-press.
  final String tooltip;

  /// Optional tap handler for tests. When non-null, [url] is not launched.
  @visibleForTesting
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? () => launchUrl(Uri.parse(url)),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.help_outline, size: 16, color: color),
        ),
      ),
    );
  }
}
