# crux_app_info

About-box extension-point models for the EDACrux suite.

Every product in the suite ships an About dialog that displays the application edition, build metadata, and company branding. The dialog itself is [`crux_about_dialog`](../crux_about_dialog); this package owns the *data shapes* it consumes, so all four products carry consistent fields.

## Surface

This package is small on purpose — two immutable models and nothing else:

- `ApplicationBuildInfo` — immutable model carrying version, build number, git SHA, OS, architecture, Dart/Flutter SDK versions.
- `ApplicationBranding` — immutable model carrying company name, logo asset paths, copyright year, and website URL.

The edition is not a model here: `CruxAboutDialog` takes the edition label as a plain string, and the edition chip is `EditionBadge` in `crux_license`, which reads the active tier directly.

Deliberately **pure Dart**: no Flutter, no Riverpod. Each product supplies the values (its own `applicationBuildInfoProvider` / `applicationBrandingProvider`, since build metadata is necessarily per-product) and passes them to `CruxAboutDialog.show`. Keeping the providers per-product and the models here is what lets the models stay dependency-free while the rendering stays shared.

## Why this lives in `crux_shared`

The About-box data shapes are domain-neutral and identical across all four products. Keeping them here ensures the four About dialogs stay structurally consistent and that white-label tweaks (different company branding) are made in one place.
