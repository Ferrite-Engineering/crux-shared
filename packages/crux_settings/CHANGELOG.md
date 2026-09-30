# Changelog

## 0.0.1

- Initial extraction from WaveCrux open-core. `CoreSettings` model (14 generic
  fields lifted from WaveCrux's `AppSettings`); `AppThemeMode`,
  `AutoReloadMode`, `OrientationLockMode` enums lifted verbatim;
  `SettingsCodec<T>` abstract interface; `CoreSettingsCodec` concrete codec
  preserving WaveCrux's `settings.*` `SharedPreferences` key namespace;
  generic `SettingsService<T>`.
