# ADR 0001 — Project config filename convention

**Status:** Accepted (2026-05-26). Context table and, for the suite design
manifest, the no-shim consequence superseded by
[ADR 0004](0004-crux-project-manifest-is-a-named-file.md).
**Scope:** Cross-suite — applies to WaveCrux, all future Crux products, and any
future Crux product that ships a per-project config file.
**Supersedes:** the dotfile convention SimCrux used for its per-project config
in its pre-release builds.

## Context

Each Crux product reads a per-project config file at the root of the user's
HDL project directory:

| Product   | Pre-ADR filename       | Post-ADR canonical filename |
|-----------|------------------------|-----------------------------|
| WaveCrux  | (no per-project file — uses workspace `.wavecrux-workspace` + session export `.wavecrux`) | (unchanged) |
| SimCrux   | `.simcrux`             | `simcrux.yaml`              |
| NetCrux   | `<name>.netcrux-project` (a user-named project file, opened from the picker — shape 2) | (unchanged) |
| LintCrux  | `<name>.lintcrux-session` (a user-named session file, opened from the picker — shape 2) | (unchanged) |

The NetCrux and LintCrux rows are corrected: they first described those files
as metadata no user opens. The suite design manifest, `<design>.crux-project`,
is recorded in ADR 0004.

SimCrux's per-project YAML was named as a dotfile to keep tooling metadata out
of `ls` output, mirroring `.gitignore` / `.editorconfig`. In practice the
choice caused real user pain: macOS Finder and most native file pickers hide
dotfiles by default, so opening the canonical project file required toggling
"show hidden files" on every dialog. The Slack / Mail file-attach flows have
the same limitation. None of the other Crux products carry this friction —
they either use the extension-on-named-file pattern (`team-debug.wavecrux`,
a named `project.<ext>` file) or had no per-project file at all.

## Decision

**Per-project config files for Crux products use a named-file pattern**, not a
dotfile-name pattern.

Two acceptable shapes:

1. **Canonical name + extension** — a fixed filename with a recognizable
   extension, e.g. `pubspec.yaml`, `Cargo.toml`. The user does
   not name the file; the product does.
2. **User-named + product extension** — a user-chosen filename with the
   product's extension, e.g. `team-debug.wavecrux`. The
   user names the file; the product owns the extension.

**Forbidden**: pure dotfile names like `.wavecrux-config`, `.<product>rc`, etc.
A leading dot is allowed only when:

- The file is genuinely supplementary tool metadata that the user is not
  expected to open via a file picker (e.g. `.gitignore`, tool cache dirs),
  AND
- The product never asks the user to find or share this file via a UI surface.

## Consequences

- SimCrux's canonical project file is renamed from `.simcrux` to
  `simcrux.yaml`. Fixture projects, importer output filenames, CLI help text,
  ARB strings, documentation, and tests are updated to match.
- SimCrux's FuseSoC importer is simplified to always write the canonical named
  form (previously it derived a dotfile-prefixed name to differentiate when
  multiple cores lived in one directory; that multi-core workflow is now a
  known edge case the caller manages).
- Products that already followed the named-file convention are unaffected.
- WaveCrux is unaffected (no per-project file).
- Remaining products are verified (and, if needed, remediated) as they
  approach release.
- Engineers with old shell aliases or scripts referencing the dotfile name will
  see "file not found" errors and need to update. No backwards-compat shim is
  provided — the dotfile was an early mistake, not a deliberate API.

## Notes for future config files

When introducing a new per-project, per-user, or per-suite config file in any
Crux product:

- If users open or share the file directly: use a named-file pattern. Default
  to the canonical-name shape (`<product>.yaml` or `<product>.<ext>`) unless
  the product needs multiple coexisting variants per directory.
- If the file is true tooling cache or invisible metadata that the user
  never touches: a dotfile name is acceptable; document why.
- Consult this ADR before introducing the dotfile pattern; the burden of
  proof is on the new dotfile.

## References

- The SimCrux rename commits, in the `simcrux` open-core repo, around the date
  of this ADR.
- Original user friction report: the file picker required a "show hidden files"
  toggle to find SimCrux's canonical project file.
