# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## 0.1.0

- Initial release. `CruxAboutDialog` — one About dialog for the whole suite,
  presented via `CruxAboutDialog.show` as a modal on desktop and a pushed
  full-screen route on mobile.
- The host supplies branding, build metadata, edition label, localized chrome
  strings (`CruxAboutStrings`, with `CruxAboutStringsEn` as the English
  default), an app icon, optional `AboutAttributionSection`s, and the ordered
  list of `AboutAction` buttons.
- Tier and beta-period state are read from `crux_license` providers, so the
  embedded EDU badge and "Public Beta" chip stay consistent across products
  without each one re-deriving them.
- `AboutSectionHeader` is shared between the dialog body and the attribution
  section but deliberately kept off the public surface.
