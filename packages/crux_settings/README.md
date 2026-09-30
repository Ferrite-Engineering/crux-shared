# crux_settings

Cross-suite shared settings infrastructure for the EDACrux suite.

Provides:

- **`CoreSettings`** — the shared subset of application settings (theme, locale, diagnostics flag, plugin directories, theme overrides, restore-tabs-on-launch, etc.). 14 fields that every product in the suite has reason to honor.
- **`SettingsCodec<T>`** — abstract codec interface defining how a typed settings model is read from and written to `SharedPreferences`.
- **`CoreSettingsCodec`** — concrete codec for `CoreSettings`. Uses the exact same `settings.*` key namespace WaveCrux open-core has shipped with since v0, so existing user preferences survive the migration to the cross-suite shape.
- **`SettingsService<T>`** — generic service that ties a codec to `SharedPreferences.getInstance()`. Each product instantiates it with its own product-specific codec that delegates the `CoreSettings` portion to `CoreSettingsCodec`.

## Status

Production code lifted from WaveCrux open-core when a second product needed it.

## Usage pattern

```dart
// crux_settings: shared
class CoreSettings {
  final AppThemeMode themeMode;
  final String locale;
  // … 12 more generic fields
}

// wavecrux: per-product
class AppSettings {
  const AppSettings({required this.core, required this.waveformFontSize, ...});
  final CoreSettings core;
  // wavecrux-specific:
  final double waveformFontSize;
  final DisplayFormat defaultDisplayFormat;
  // … 4 more wavecrux fields

  // Forwarder getters preserve consumer ergonomics (settings.themeMode
  // works without `.core.` traversal).
  AppThemeMode get themeMode => core.themeMode;
  String get locale => core.locale;
  // …
}

class WaveCruxSettingsCodec implements SettingsCodec<AppSettings> {
  @override
  Future<AppSettings> load(SharedPreferences prefs) async {
    final core = await const CoreSettingsCodec().load(prefs);
    return AppSettings(core: core, waveformFontSize: ..., ...);
  }

  @override
  Future<void> save(SharedPreferences prefs, AppSettings settings) async {
    await const CoreSettingsCodec().save(prefs, settings.core);
    // … wavecrux-specific writes
  }
}
```

Each product's settings provider wraps `SettingsService<TheirAppSettings>(TheirSettingsCodec())`.
