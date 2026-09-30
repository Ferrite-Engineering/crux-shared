# Changelog

## 0.1.1

- The manifest is named `<design>.crux-project` — any non-empty stem with the
  `crux-project` extension — instead of the bare `.crux-project`, which file
  pickers and Finder hide. `CruxProjectParser.isManifestPath` accepts both
  names; `kCruxProjectExtension` is the value a picker filter takes.
- The legacy `.crux-project` still opens, with a deprecation warning first in
  `CruxProjectManifest.warnings` that names the file to rename it to.
  `CruxProjectParser.isLegacyManifestPath` detects it for a localized message.
  Reading it stops in 0.2.0.
- `kCruxProjectFileName` is deprecated; removed in 0.2.0.
- `CruxProjectParser.findIn` finds any `*.crux-project` in the directory and
  throws `CruxProjectAmbiguousException`, naming every candidate, when there
  is more than one — the legacy file beside a named one included.
- `CruxProjectParser.locate` resolves either a manifest path or a design
  directory to the manifest.
- The CXP `design_id` is still derived from the manifest directory, so the
  rename does not change any design's id.

## 0.1.0

- Initial release. `CruxProjectParser` and `CruxProjectManifest` for the
  `.crux-project` suite design manifest: fatal only on a missing or invalid
  `version`, warnings for everything else, and every path resolved against
  the manifest's directory.
- `CruxProjectOpenPlanner`, `CruxProjectOpenPlan` and `CruxOpenRefusal` — the
  per-product open plan, with the CXP `design_id` derived from the manifest
  directory in every case.
- Artifact kinds are opaque manifest keys; each product owns the constant for
  the kind it consumes, and unknown keys are retained.
