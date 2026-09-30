# crux_shortcut_action

Cross-suite shared action infrastructure for the EDACrux suite.

The shape is deliberately minimal:

- **`ActionCategory`** — the suite-wide grouping enum used by every product's menu bar, mobile overflow menu, and command palette to organize actions (`app`, `file`, `view`, `navigate`, `search`, `tools`, `help`).
- **`CruxAction`** — abstract interface every product's specific action enum implements. Carries just `id` (unique identifier for serialization, telemetry, command palette IDs) and `category` (which menu group the action belongs to).

The product-specific bits stay in each product:

- The actual action **enum** (`ShortcutAction` in WaveCrux; analogous enums in NetCrux, LintCrux and SimCrux) lives in the product. It implements `CruxAction` and adds however many specific values the product needs (WaveCrux has 280+).
- The **localized labels** for each action stay in the product because labels reference each product's own L10N.
- The **`Intent` subclass** that carries an action through Flutter's Actions/Shortcuts tree stays in the product (it can be a typedef over a future generic if a second product needs the same dispatch shape).
- The **default key bindings** map stay in the product (each product has its own canonical shortcut layout).
- The **menu-hidden filter** and **`groupedActions` helpers** stay in the product (they reference the product-specific enum directly).

## Status

Extracted from WaveCrux open-core when a second product needed it. The `ActionCategory` enum is lifted verbatim from `wavecrux/lib/core/shortcuts/action_category.dart`; `CruxAction` is a new interface designed to let each product specialize while sharing the category taxonomy.

## Usage pattern

```dart
// In crux_shortcut_action:
abstract interface class CruxAction {
  String get id;
  ActionCategory get category;
}

enum ActionCategory { app, file, view, navigate, search, tools, help }

// In wavecrux:
enum ShortcutAction implements CruxAction {
  openFile,
  closeFile,
  zoomIn,
  // ... 280+ more values

  @override
  String get id => 'wavecrux.$name';

  @override
  ActionCategory get category => switch (this) {
        ShortcutAction.openFile => ActionCategory.file,
        ShortcutAction.zoomIn => ActionCategory.view,
        // ...
      };
}

// In another Crux product later:
enum OtherCruxAction implements CruxAction {
  elaborate,
  traceSignal,
  // ...
}
```

Generic infrastructure (menu builders, command palette widgets, telemetry sinks) can be written against `CruxAction` and `ActionCategory` and work for every product's enum without modification.
