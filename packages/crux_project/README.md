# crux_project

The `<design>.crux-project` suite design manifest: one checked-in pointer file
naming a design's RTL, waveform dump, lint project and regression config, so
opening a design in four products is one ritual instead of four. Pure Dart.

```yaml
# uart_tx/uart_tx.crux-project
version: 1
name: uart_tx

design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v

artifacts:
  waveform:   sim/uart_tx.vcd
  lint:       project.lintcrux
  simulation: simcrux.yaml
```

```dart
import 'package:crux_project/crux_project.dart';

final manifest = const CruxProjectParser().parseFile(manifestPath);
final plan = const CruxProjectOpenPlanner().plan(manifest, kind: 'waveform');
final path = plan.artifactPath;
if (path != null) {
  openInThisProduct(path, designId: plan.designId);
} else {
  reportNothingToOpen(plan.refusal);
}
```

## Surface

| Symbol | Purpose |
|---|---|
| `CruxProjectParser` | `parse` / `parseFile`; `isManifestPath` (the cheap by-filename predicate a file-open dispatcher branches on — true for `<stem>.crux-project` and the legacy `.crux-project`); `isLegacyManifestPath` (the legacy name, for a product that localizes the deprecation message); `findIn` (the one manifest inside a directory) and `locate` (a manifest path or a design directory, resolved to the manifest). |
| `CruxProjectManifest` | The parsed file. Every path is resolved against the manifest's own directory, never the process working directory; the raw strings are kept for round-trip. |
| `CruxProjectOpenPlanner`, `CruxProjectOpenPlan`, `CruxOpenRefusal` | What one product should do with a manifest: an artifact path to hand to its existing open flow, or a plain reason there is nothing to open. |
| `CruxProjectFormatException` | The file is not a manifest, or cannot be read. |
| `CruxProjectAmbiguousException` | A directory holds more than one manifest; carries every candidate. |
| `kCruxProjectExtension`, `kCruxProjectSchemaVersion` | The extension a picker filter or document type takes (`crux-project`, no dot), and the schema version this build authors. |
| `kCruxProjectFileName` | Deprecated: the legacy bare name. Removed in 0.2.0. |

## The file name

A manifest is `<design>.crux-project` — any non-empty stem, the `crux-project`
extension — so `uart_tx/uart_tx.crux-project`. Native file pickers and Finder
hide dotfiles, and a file a user has to open from a picker cannot be one; see
[ADR 0004](../../docs/adr/0004-crux-project-manifest-is-a-named-file.md).

- **Legacy name.** A bare `.crux-project` still opens for this release. The
  parse puts a deprecation warning first in `warnings`, naming the file to
  rename it to, and `isLegacyManifestPath` lets a product show its own
  localized text instead. Reading it stops in 0.2.0.
- **One per directory.** `findIn` and `locate` throw
  `CruxProjectAmbiguousException` when a directory holds more than one
  manifest — two named ones, or a named one beside the legacy file — and name
  every candidate. Neither is ranked above the other: whichever lost could
  describe the design differently. A path naming one file is never ambiguous.
- **The name is not the identity.** The design id comes from the manifest's
  directory, so renaming the file changes nothing a peer sees.

A product that opens manifests from its picker filters on
`kCruxProjectExtension` and hands the chosen path to
`CruxProjectParser.isManifestPath` → `parseFile` → `CruxProjectOpenPlanner.plan`,
exactly as before.

## The rule this package exists to enforce

The CXP `design_id` comes from the manifest's **directory**, not from whichever
artifact a product opened. Opening the manifest and opening the dump beside it
directly must yield the same id, or cross-probe between manifest-opened designs
silently stops joining. `CruxProjectOpenPlan.designId` is populated even when
the plan refuses, because a product with nothing to open may still want to join
the design's cross-probe identity.

That derivation is why this is shared rather than copied four times: one
product getting it wrong is enough to break cross-probe for everyone.

## Tolerant, and strict in exactly one place

A missing or non-integer `version` is fatal — it is the only thing standing
between "this is a manifest" and "this is some YAML file that happened to be
selected". Everything else degrades to a warning and the rest of the file is
kept: a manifest is a pointer file, and a partially understood one is still
useful. Absence is not failure either; a manifest naming a dump that has not
been generated yet is normal, and the missing file surfaces when something
tries to open it.

## Artifact kinds are opaque strings

A kind is the manifest key verbatim, and this package never enumerates them.
Naming the kinds here would put single-product vocabulary into shared code,
which the domain-neutrality charter forbids. Each product owns the constant for
the kind it consumes. A key this build has never heard of is kept, not
rejected, so a manifest written for a later suite version opens unchanged.

## Not to be confused with `crux_projects`

Singular. `crux_projects` is the unrelated multi-project workspace layer behind
the project switcher.
