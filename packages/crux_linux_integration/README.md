# crux_linux_integration

AppImage first-run desktop self-integration for the EDACrux suite. Pure Dart,
`dart:io`, no Flutter.

```dart
import 'package:crux_linux_integration/crux_linux_integration.dart';

// Early in bootstrap(), before runApp — inert off Linux and off AppImage.
await maybeIntegrateDesktopEntry(
  LinuxDesktopApp(
    appId: 'com.ferriteengineering.simcrux_pro',
    name: 'SimCrux Pro',
    comment: 'Simulation regression runner and dashboard for HDL testbenches',
    execName: 'simcrux_pro',
    fileTypes: [
      // Ours: declared in the installed package, and named in the entry.
      LinuxMimeType.declared(
        name: 'application/x-simcrux-workspace',
        comment: 'SimCrux workspace',
        extensions: const ['simcrux-workspace'],
        subClassOf: 'application/json',
      ),
      // The system's: named in the entry, never re-declared.
      const LinuxMimeType.registered('application/x-yaml'),
      // Left alone on purpose, with the reason a coverage check prints.
      LinuxMimeType.unmapped(
        extensions: const ['f'],
        reason: 'a .f file is Fortran to every Linux desktop',
      ),
    ],
  ),
);
```

## Why the package exists

Each app's AppImage recipe (`scripts/package_appimage.sh`) installs a
`.desktop` file and hicolor icons keyed on the application id — but only
*inside* the AppDir. Nothing is written to the host, so the Wayland compositor
has no host-side `.desktop` whose `StartupWMClass` matches the running window's
`app_id` (the GTK runner sets it to that same application id), and GNOME/Ubuntu
shows a generic dock icon. Native/deb installs don't have this problem;
AppImages do.

The standard fix is AppImage self-integration: on launch, when running from an
AppImage, the app writes its own `.desktop` + icons into `~/.local/share`,
idempotently. That is all this package does.

## What `integrate` does

1. If `APPIMAGE` is unset → skip (not an AppImage; native installs already own
   a host entry).
2. If the per-app marker at `~/.local/share/crux/<appId>.appimage-integrated`
   already records the current AppImage path + mtime → skip (already current).
3. Write `<data home>/applications/<appId>.desktop` with
   `Exec="<appImagePath>" %F`, `Icon=<appId>`, `StartupWMClass=<appId>` and
   `MimeType=` (every type the app claims, ours and the system's).
4. Write `<data home>/mime/packages/<appId>.xml` declaring the app's **own**
   types, or delete the one it left behind when it declares none.
5. Copy each `<size>/apps/<appId>.png` from the mounted AppDir's hicolor theme
   (`$APPDIR/usr/share/icons/hicolor`) to the matching host path.
6. Best-effort `update-mime-database` (only when the package changed), then
   `update-desktop-database` + `gtk-update-icon-cache` — each may be absent or
   fail, and every error is swallowed.
7. Write the marker.

The data home is `$XDG_DATA_HOME`, or `~/.local/share` when the session does
not set it.

## Why file associations take two halves

`MimeType=` in the entry says which types the application handles, but a file
manager types the file *first* and looks for handlers second. Nothing on a
stock desktop maps `*.simcrux-workspace`, so the file is typed as JSON, and an
entry that lists `application/x-simcrux-workspace` matches nothing. The
installed `shared-mime-info` package is what supplies the mapping — and the
description the "Kind" column shows.

The rule the API enforces: **a type is declared, or it is registered, never
both**. A type the desktop already maps (`application/x-yaml`, and the source
types of a product's own trade) is named in the entry and left alone, because
our `<comment>` would replace the description every file of that type shows on
the user's machine. Declaring one of the generic types in
`kLinuxSystemMimeTypes` throws; a product passes the further types it names to
`checkLinuxMimeCoverage` as `additionalSystemTypes`, since those names belong
in the product. A `subClassOf` parent is different, and encouraged: a desktop
that knows nothing of our type still treats the file as JSON, YAML or text.

**An extension another type already claims is shared, not taken.** `.vcd` is
globbed to a Video CD playlist on a stock database, and a heavier glob would
retype every `.vcd` on the machine. So a type in that position takes a
`globWeight` *below* the default 50 and a `magic` match on the tokens its own
header carries: a real Video CD keeps its type, and a waveform is recognised by
what is in it.

```dart
LinuxMimeType.declared(
  name: 'application/x-wavecrux-vcd',
  comment: 'Value change dump',
  extensions: const ['vcd'],
  globWeight: 40,
  magic: LinuxMimeMagic(
    priority: 60,
    matches: const [
      LinuxMimeMagicMatch(value: r'$date', offsetEnd: 64),
      LinuxMimeMagicMatch(value: r'$version', offsetEnd: 64),
    ],
  ),
);
```

An extension the app registers elsewhere but deliberately does not claim here
is recorded with `LinuxMimeType.unmapped` and a reason — `.f` is Fortran to
every Linux desktop — so `checkLinuxMimeCoverage` can report it instead of
calling it a hole. That check is the guard a product's test runs against the
extensions its macOS bundle registers.

`integrate` never throws — every path resolves to a `DesktopIntegrationResult`.
A moved or updated AppImage changes the marker signature and re-integrates, so
`Exec=` keeps pointing at the live AppImage.

## Testing

All logic is injectable — `homeDir`, `env`, and the cache-refresh runner — so
the whole flow is unit-tested off-Linux against a fake `HOME`/`APPDIR` tree.
`maybeIntegrateDesktopEntry` is the only symbol that touches the real
`Platform`, and it no-ops unless `Platform.isLinux`.
