# crux_command_palette

Cross-suite VS Code-style command palette widget for the EDACrux suite.

A single generic `CommandPalette<T extends CruxAction>` Flutter widget that any Crux product can use to provide a fuzzy-search keyboard-shortcut launcher. Behavior:

- Typing in the search field fuzzy-filters the list of actions in real time.
- ↑/↓ navigate the list; Enter executes the selected action; Escape dismisses.
- Each visible row shows the localized action label and its configured keyboard shortcut.
- The dialog is type-parameterized over each product's specific action enum so dispatch stays type-safe (`onAction: void Function(T)`).

## What the palette does NOT do

The widget deliberately doesn't read any state from its environment. All the gating logic — which actions to show, which to hide based on app state (e.g. "addDecoder only when a file is loaded"), which to gate by license tier — happens **in the caller**, before the action list is handed to the widget. This keeps the package free of Riverpod / specific provider dependencies and lets each product apply its own context rules.

## Parameters

```dart
CommandPalette<T extends CruxAction>(
  // The actions to display, in caller-decided order. The caller pre-filters
  // for visibility (hides keyboard-only aids, gates by app state, etc.).
  required List<T> actions,

  // Maps an action to its localized label. Called for every visible action;
  // the widget itself never touches localization.
  required String Function(T) labelFor,

  // Called with the selected action AFTER the dialog has closed.
  required void Function(T) onAction,

  // Search-field placeholder and "no results" text — caller-localized.
  required String hintText,
  required String noResultsLabel,

  // Optional keyboard-shortcut bindings shown to the right of each row.
  // Empty by default; pass the product's configured bindings to display them.
  Map<T, ShortcutActivator?> bindings = const {},

  // Optional shortcut formatter (defaults to a Material-style "⌘+P" / "Ctrl+P"
  // renderer). Override to use product-specific conventions.
  String Function(ShortcutActivator?)? activatorLabel,

  // Optional builder that wraps the inner scrolling list with a product-
  // specific scroll-event listener (e.g. WaveCrux's TrackpadScrollListener
  // that forwards iPad Magic Keyboard trackpad scroll into the controller).
  // Default identity (no wrapper).
  Widget Function(BuildContext, ScrollController, Widget child)? scrollWrapperBuilder,
)
```

## Status

Extracted from WaveCrux open-core's `CommandPaletteDialog`. The widget tree (search field, results list, command row) is lifted verbatim; the wavecrux-specific filtering / provider-reading / L10N-coupled bits are now caller responsibilities exposed as constructor parameters.

## Usage pattern

```dart
// In WaveCrux (lib/features/command_palette/widgets/command_palette_dialog.dart):
class CommandPaletteDialog extends ConsumerStatefulWidget {
  // Reads wavecrux providers, computes the filtered ShortcutAction list,
  // delegates to crux_command_palette's CommandPalette<ShortcutAction>.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final actions = _filteredActions(ref);  // wavecrux-specific filtering
    return CommandPalette<ShortcutAction>(
      actions: actions,
      labelFor: (a) => a.label(l10n),
      onAction: (a) => Actions.maybeInvoke(
        context,
        ShortcutActionIntent(a),
      ),
      hintText: l10n.commandPaletteSearchHint,
      noResultsLabel: l10n.commandPaletteNoResults,
      bindings: bindings,
      activatorLabel: formatShortcutLabel,
      scrollWrapperBuilder: (ctx, ctrl, child) =>
          TrackpadScrollListener(controller: ctrl, child: child),
    );
  }
}
```

All four products use the generic widget verbatim — each defines its own action enum, gating logic, and L10N keys, but the widget tree is the same.
