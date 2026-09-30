// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

/// Centered "nothing is open yet" splash rendered when the workspace has zero
/// tabs.
///
/// The widget is intentionally **content-slot driven**: the framework lays
/// out the title, optional subtitle, optional recent-files / recent-workspace
/// sections, and a row of caller-supplied primary actions, but every piece
/// of text and every list item comes from the host product. The package
/// knows nothing about waveforms, netlists, or test fixtures — only about
/// how to compose them into a polished empty-canvas surface.
///
/// Typical usage from a product's `PaneHost.emptyCanvasContent`:
///
/// ```dart
/// EmptyCanvasState(
///   title: l10n.welcomeTitle,
///   subtitle: l10n.welcomeSubtitle,
///   recentFilesSection: RecentFilesList(...),
///   recentWorkspacesSection: RecentWorkspacesList(...),
///   primaryActions: [
///     FilledButton.icon(onPressed: ..., icon: ..., label: Text('Open File…')),
///     OutlinedButton.icon(onPressed: ..., icon: ..., label: Text('New Tab')),
///   ],
/// );
/// ```
///
/// **Keyboard and screen reader.** The canvas is a named region
/// ([semanticLabel], defaulting to [title]) and the title is a heading. When
/// it appears and nothing else holds keyboard focus — at launch, or after
/// the last tab closes — it focuses its first primary action (the first
/// focusable control in [children] when those are supplied). Without that a
/// desktop screen reader has nothing to announce but the window's class
/// name, and keyboard shortcuts scoped below the focus have nothing to fire
/// from. Set [claimInitialFocus] to false to opt out.
class EmptyCanvasState extends StatefulWidget {
  /// Creates an empty-canvas widget.
  ///
  /// Pass [children] to take full control of the body composition (the host
  /// product supplies an ordered list of section widgets); when [children] is
  /// non-null the [title]/[subtitle]/[versionLabel]/[recentFilesSection]/
  /// [recentWorkspacesSection]/[primaryActions]/[peers]/[footer] convenience
  /// slots are ignored. When [children] is null (the default) the convenience
  /// composition is rendered, so existing callers are unaffected.
  const EmptyCanvasState({
    this.header,
    this.title,
    this.subtitle,
    this.versionLabel,
    this.recentFilesSection,
    this.recentWorkspacesSection,
    this.primaryActions = const [],
    this.peers,
    this.footer,
    this.children,
    this.useCard = true,
    this.maxContentWidth = _maxContentWidth,
    this.semanticLabel,
    this.claimInitialFocus = true,
    super.key,
  }) : assert(
         title != null || children != null,
         'EmptyCanvasState requires either a title or a children list.',
       );

  /// The region's accessible name. Null uses [title]; supply it when
  /// [children] replaces the title.
  final String? semanticLabel;

  /// Whether the canvas focuses its first action when nothing else holds
  /// focus. See the class documentation.
  final bool claimInitialFocus;

  /// Optional widget rendered centered above the [title] — typically the
  /// product's `CruxGlowingAppIcon`. Ignored when [children] is supplied
  /// (a fully caller-composed body places its own header).
  final Widget? header;

  /// Headline shown above the optional [subtitle]. Required unless [children]
  /// is supplied.
  final String? title;

  /// Optional one-line subtitle rendered immediately below the [title].
  final String? subtitle;

  /// Optional muted version line rendered immediately below the [subtitle] —
  /// e.g. `'Version 0.5.0'`.
  ///
  /// This exists mainly for the web builds. On desktop the version is
  /// reachable from the native menu bar's About entry, but on web there is no
  /// menu bar, so the welcome screen is the only always-visible place a user
  /// can read which version they are running. Products that already surface
  /// the version elsewhere can simply omit it.
  ///
  /// Carries the key `empty_canvas_version` so widget tests can assert on it
  /// without depending on the formatted string.
  final String? versionLabel;

  /// Optional widget rendered above [recentWorkspacesSection]. Typically a
  /// scrollable list of recent file paths.
  final Widget? recentFilesSection;

  /// Optional widget rendered above [primaryActions]. Typically a scrollable
  /// list of recent named workspaces.
  final Widget? recentWorkspacesSection;

  /// Caller-supplied buttons or other interactive widgets. Rendered in a
  /// horizontally-wrapping row with even spacing. Ignored when [children] is
  /// supplied.
  final List<Widget> primaryActions;

  /// Optional "More from EDACrux" block rendered below [primaryActions] and
  /// above [footer] — typically a `CruxSuitePeers`.
  ///
  /// A slot of its own rather than something the host stacks into [footer]:
  /// the gap above it, and the tighter gap between it and the line below,
  /// are then decided once here instead of four times. Ignored when
  /// [children] is supplied, where the caller composes its own body.
  final Widget? peers;

  /// Optional trailing line rendered last, below [peers] — typically
  /// a `CruxSuiteFooter`, and the place for any other quiet
  /// one-line-and-a-link footnote a product wants at the foot of its welcome
  /// screen.
  ///
  /// Separate from [children] so the three products on the convenience
  /// composition can adopt a shared footer without restating the whole body.
  /// Ignored when [children] is supplied, where the caller places its own.
  final Widget? footer;

  /// Optional fully caller-composed body. When non-null, this ordered list is
  /// rendered (inside the shared scroll + width-constraint chrome) in place of
  /// the convenience composition, so the host product controls section order
  /// and styling exactly. The widgets are laid out in a stretch [Column].
  final List<Widget>? children;

  /// Whether to wrap the body in a [Card]. Products that want a flat,
  /// card-less splash pass `false`. Defaults to `true`.
  final bool useCard;

  /// Maximum content width for the centered body. Defaults to 560.
  final double maxContentWidth;

  static const double _maxContentWidth = 560;
  static const double _phoneBreakpoint = 600;

  @override
  State<EmptyCanvasState> createState() => _EmptyCanvasStateState();
}

class _EmptyCanvasStateState extends State<EmptyCanvasState> {
  final FocusNode _bodyNode = FocusNode(
    debugLabel: 'EmptyCanvasState body',
    skipTraversal: true,
    canRequestFocus: false,
  );
  final FocusNode _actionsNode = FocusNode(
    debugLabel: 'EmptyCanvasState actions',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    if (widget.claimInitialFocus) {
      // After the frame, and then after the focus manager has applied the
      // autofocus requests that frame made, so a control that asked for
      // focus in the same frame keeps it.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scheduleMicrotask(_claimFocus),
      );
    }
  }

  @override
  void dispose() {
    _bodyNode.dispose();
    _actionsNode.dispose();
    super.dispose();
  }

  void _claimFocus() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    // A focused control elsewhere (a dock's search field, a dialog) keeps
    // its focus; only a bare scope, which announces nothing, is replaced.
    if (primary != null && primary is! FocusScopeNode) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    for (final source in <FocusNode>[_actionsNode, _bodyNode]) {
      for (final node in source.traversalDescendants) {
        if (node.context == null) continue;
        node.requestFocus();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isPhone = width < EmptyCanvasState._phoneBreakpoint;
    final pagePadding = isPhone ? 16.0 : 32.0;
    final cardPadding = isPhone ? 16.0 : 24.0;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.children ?? _convenienceChildren(theme),
    );

    final constrained = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
      child: widget.useCard
          ? Card(
              // Not a semantics container: the region above names the
              // canvas, and a container card would absorb the heading flag
              // and every loose line of text into one node that holds all
              // the buttons.
              semanticContainer: false,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: EdgeInsets.all(cardPadding),
                child: body,
              ),
            )
          : body,
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel ?? widget.title,
      child: Focus(
        focusNode: _bodyNode,
        includeSemantics: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: pagePadding,
              vertical: pagePadding,
            ),
            child: constrained,
          ),
        ),
      ),
    );
  }

  List<Widget> _convenienceChildren(ThemeData theme) {
    final header = widget.header;
    final subtitle = widget.subtitle;
    final versionLabel = widget.versionLabel;
    final recentFilesSection = widget.recentFilesSection;
    final recentWorkspacesSection = widget.recentWorkspacesSection;
    final primaryActions = widget.primaryActions;
    final peers = widget.peers;
    final footer = widget.footer;
    return [
      if (header != null) ...[
        Center(child: header),
        const SizedBox(height: 12),
      ],
      Semantics(
        header: true,
        container: true,
        child: Text(widget.title!, style: theme.textTheme.headlineMedium),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (versionLabel != null) ...[
        const SizedBox(height: 6),
        Text(
          versionLabel,
          key: const Key('empty_canvas_version'),
          // Full-strength onSurfaceVariant: at 11 px the line needs 4.5:1,
          // and the 70% tint it used to carry measured 3.88:1.
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (recentFilesSection != null) ...[
        const SizedBox(height: 24),
        recentFilesSection,
      ],
      if (recentWorkspacesSection != null) ...[
        const SizedBox(height: 16),
        recentWorkspacesSection,
      ],
      if (primaryActions.isNotEmpty) ...[
        const SizedBox(height: 24),
        Focus(
          focusNode: _actionsNode,
          includeSemantics: false,
          child: Wrap(spacing: 12, runSpacing: 12, children: primaryActions),
        ),
      ],
      if (peers != null) ...[
        const SizedBox(height: 24),
        peers,
      ],
      if (footer != null) ...[
        // Tighter than the gap above the peers block: the line restates, in
        // one quiet sentence, what the rows above it just said at length, so
        // it reads as their footnote rather than a fifth section.
        SizedBox(height: peers == null ? 16 : 4),
        footer,
      ],
    ];
  }
}
