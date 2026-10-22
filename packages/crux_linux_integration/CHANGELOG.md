# Changelog

## Unreleased

- **An AppImage can register URL schemes.** `LinuxDesktopApp.urlSchemes`
  (for example `['wavecrux']`) makes the integrator write a hidden
  `<app id>-url-handler.desktop` beside the main entry, built by
  `buildUrlHandlerEntry`: `Exec="<AppImage>" %u`, `NoDisplay=true`,
  `MimeType=x-scheme-handler/<scheme>;` for each scheme, and no
  `StartupWMClass`, so the dock keeps matching the window to the main entry.
  It is a separate entry because a link has to arrive as one argument (`%u`)
  while the main entry passes files as paths (`%F`). The desktop database is
  refreshed as before; a release that no longer declares a scheme removes the
  entry; a malformed scheme fails integration before anything is written.
  With no schemes declared the integrator's output is byte-identical.
- **`DesktopIntegrator.uninstall` and `maybeUninstallDesktopEntry`** remove
  what integration installed: both entries, the MIME package, the icons and
  the marker, then refresh the caches. Never throws; returns the paths it
  deleted.
- **The `Exec` path is quoted by the Desktop Entry Specification's rules**
  (`quoteDesktopExecArgument`): `"`, `` ` ``, `$` and `\` are escaped inside
  the quotes, `%` is doubled, and the general string escapes are applied on
  top, so an AppImage under a path holding any of them is still launched as
  one argument. A path without those characters is written exactly as before.
- **A Linux file manager can offer the app for the files it opens.** The
  generated `.desktop` entry declared no `MimeType`, so "Open With" never
  listed it and a double-clicked project, waveform or source file went to some
  other application — the Linux half of the document types each macOS bundle
  registers. Closing it takes two halves, and `LinuxDesktopApp.fileTypes`
  carries both. It supersedes `mimeTypes`, whose bare names reach the entry
  and install nothing; that list keeps working until the four products have
  moved, and `checkLinuxMimeCoverage` reports it until they do.
  - `LinuxMimeType.declared` is a type of ours: it goes in the entry's
    `MimeType=` **and** in a `shared-mime-info` package the integrator installs
    at `<data home>/mime/packages/<app id>.xml`, with a glob per extension, the
    description a file manager shows in its "Kind" column, and an optional
    `subClassOf` parent so a desktop that knows nothing of the type still
    treats the file as JSON, YAML or text. Without that package nothing maps
    the extension, the file is typed as JSON, and the entry matches nothing.
    It also takes a `magic` content match and a `globWeight`, which is how an
    extension another type already claims is shared rather than taken: `.vcd`
    is a Video CD playlist to a stock database, so a waveform type sits below
    the default weight and is recognised by the tokens its header carries.
  - `LinuxMimeType.registered` names a type the system already maps. It is
    never re-declared: our `<comment>` would replace the description every file
    of that type shows on the machine. Declaring one of the generic types in
    `kLinuxSystemMimeTypes` throws, and a product holds its own further types
    to the same rule through `checkLinuxMimeCoverage`'s
    `additionalSystemTypes`.
  - `LinuxMimeType.unmapped` records an extension left to other applications
    on purpose, with the reason — `.f` is Fortran to every Linux desktop — so a
    gap is a decision somebody wrote down.
  - `checkLinuxMimeCoverage` is the guard products run against the extensions
    their macOS bundle registers: it reports an extension nothing maps, two
    types claiming one extension, and any disagreement between the entry and
    the installed package, and prints the deliberate gaps rather than failing
    on them.
- **`update-mime-database` runs when the package changes**, before
  `update-desktop-database`, and a package the application no longer declares
  is deleted and the database recompiled, so a withdrawn type does not outlive
  it. Like the rest of integration, a missing tool, an unwritable directory or
  a non-Linux host leaves the app running and reports the outcome instead of
  throwing.
- **`$XDG_DATA_HOME` is honoured** for the entry, the icons, the MIME package
  and the marker, falling back to `~/.local/share` as the specification says.
  Writing to the default while the session points elsewhere installed entries
  nothing reads.

## 0.1.0

- Initial release. AppImage first-run desktop self-integration:
  `LinuxDesktopApp`, `buildDesktopEntry`, `DesktopIntegrator` and the
  `maybeIntegrateDesktopEntry` platform entry point. On launch from an
  AppImage each suite app writes its own host-side `.desktop` + hicolor icons
  into `~/.local/share`, keyed on the application id, so the Wayland
  compositor matches the running window's `app_id` to the entry's
  `StartupWMClass` and shows the app's dock icon instead of a generic one.
  Idempotent via a per-app marker that tracks the AppImage path + mtime, so a
  moved or updated AppImage re-integrates and an unchanged one is a no-op.
