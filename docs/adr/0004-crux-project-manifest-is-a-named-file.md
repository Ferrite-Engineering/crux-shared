# ADR 0004 — The suite design manifest is a named `<design>.crux-project` file

**Status:** Accepted (2026-09-15)
**Scope:** Cross-suite — the suite design manifest read by WaveCrux, NetCrux,
LintCrux and SimCrux through `crux_project`.
**Supersedes:** ADR 0001's Context table (corrected below), and — for the suite
design manifest only — its "no backwards-compat shim is provided" consequence.

## Context

`crux_project` read a suite design manifest named exactly `.crux-project`. The
dotfile was chosen so the manifest sorted with the other repo-root dotfiles and
could not be mistaken for a source file by a glob, accepting that every product
would need an explicit entry for it in its file picker.

But the manifest is a file users open themselves: from each product's file
picker, on its command line, and through Finder's Open With. That is the class
ADR 0001 forbids a pure dotfile name for, and the friction it names is real
here too:

- The macOS handler of `file_picker`, which the products use for their Open
  dialogs, sets `showsHiddenFiles = false`. A picker filtered on `crux-project`
  accepts the file — macOS reads the whole dotted name as its extension — but
  does not show it until the user presses Cmd+Shift+. in the dialog. GTK
  pickers on Linux hide dotfiles as well.
- Finder hides it, so Open With is unreachable without the same toggle.
- The one usage pattern under which a dotfile is defensible — tooling that
  discovers the file by scanning a directory, as editors do with
  `.editorconfig` — had no caller in any product.

Nothing had to be migrated: no example design, test fixture or EDU pack
carried a `.crux-project`, and no product writes one. A user who hand-wrote one
from the published documentation would still be broken by a hard rename.

ADR 0001's table had also gone stale. It described `.netcrux-project` and
`.lintcrux-session` as metadata "not a user-opened project file". Both are now
opened from pickers — and both were already ADR 0001 shape 2, a user-named file
with a product extension (`cdc-capture.netcrux-project`,
`tab.lintcrux-session`), so they comply. Only the description was wrong.

## Decision

1. **The manifest is `<design>.crux-project`** — ADR 0001 shape 2 with a
   suite-owned extension: any non-empty stem, extension `crux-project`, for
   example `uart_tx/uart_tx.crux-project`. By convention the stem is the design
   directory's name; it should not begin with a dot.
2. **Recognition is by extension**, compared ASCII case-insensitively as file
   pickers and Finder compare it (`CruxProjectParser.isManifestPath`). Picker
   filters and macOS document types keep the value the products already use,
   `crux-project` (`kCruxProjectExtension`).
3. **A directory holds exactly one manifest.** Directory discovery
   (`CruxProjectParser.findIn`, `CruxProjectParser.locate`) never chooses
   between several: it throws `CruxProjectAmbiguousException` naming every
   candidate, and the legacy file beside a named one counts as two. A path that
   names one file is never ambiguous.
4. **The legacy bare `.crux-project` is read for one release** — `crux_project`
   0.1.x — with a deprecation warning first in the manifest's warnings that
   names the file to rename it to. `CruxProjectParser.isLegacyManifestPath`
   lets a product localize that message. Reading the legacy name is removed in
   `crux_project` 0.2.0.
5. **The file name is not the design's identity.** The CXP `design_id` stays
   derived from the manifest's directory, so renaming a legacy manifest changes
   no design id and breaks no cross-probe join.

## Consequences

- The manifest appears in every product's Open dialog and in Finder without a
  hidden-files toggle.
- `crux_project` 0.1.1 widens `isManifestPath`, adds `kCruxProjectExtension`,
  `isLegacyManifestPath`, `locate` and `CruxProjectAmbiguousException`, and
  deprecates `kCruxProjectFileName`. No signature changes, so every product
  still compiles against it.
- Each product accepts `crux-project` in its picker and on its command line,
  registers the extension in `CFBundleDocumentTypes`, names its fixtures and
  documentation `<design>.crux-project`, and inverts any test that asserted a
  named `*.crux-project` is not a manifest. The deprecation warning reaches
  users wherever a product already shows manifest warnings.
- Unlike ADR 0001's SimCrux rename, a compatibility read is provided. The
  manifest shipped as a documented, hand-authored format, so an existing file
  keeps opening while the warning tells its author what to do.
- Removing the legacy read in 0.2.0 is a separate change: `isManifestPath`
  then rejects the bare name and `kCruxProjectFileName` is deleted, recorded in
  the `crux_project` CHANGELOG.
- **Considered and rejected:** ADR 0001 shape 1, a fixed `crux-project.yaml`.
  Its extension is `yaml`, so a picker filter or a Finder document type could
  only target every YAML file (SimCrux already claims `yaml` for
  `simcrux.yaml`), and each product's existing `crux-project` filter and
  document type would have to change.
- **Considered and rejected:** keeping the dotfile under a superseding ADR. Its
  only defensible premise is directory discovery, which no product performs,
  while the documented flow routes users through the pickers that hide it.

## ADR 0001's table, corrected

| Product | File | Opened by the user? | Shape |
|---|---|---|---|
| Suite (all four) | `<design>.crux-project` design manifest | Yes — picker, command line, Open With | 2 (user-named, suite extension) |
| SimCrux | `simcrux.yaml` | Yes | 1 (canonical name) |
| NetCrux | `<name>.netcrux-project` | Yes — picker and command line | 2 (user-named, product extension) |
| LintCrux | `<name>.lintcrux-session` | Yes — Open Session and Export Tab as Session | 2 (user-named, product extension) |
| WaveCrux | `<name>.wavecrux` session export | Yes | 2 (user-named, product extension) |
