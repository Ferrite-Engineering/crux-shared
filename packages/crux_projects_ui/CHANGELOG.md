# Changelog

## Unreleased

- **Reopening a recent project that can no longer be loaded is reported
  and forgotten.** A persistent registry refuses a path that has gone from
  disk with a `ProjectLoadException` and keeps the entry. The recents
  panel's Reopen and the switcher's recent rows left that error uncaught:
  nothing was shown, and the entry stayed to fail the same way on the next
  press. Both now go through `reopenRecentProject`, which drops the entry
  and calls the host's `recentProjectUnavailableReporterProvider` (null by
  default, so this is additive; a host binds it to show its own localized
  message). An activation is reported only once the project has opened.
- `notifyProjectActivation`: `reportProjectActivation` for an observer read
  before an await the calling widget may not survive.

## 0.1.0

Initial release. Extracted from SimCrux's shipped project switcher when
LintCrux became the second consumer.

- `CruxProjectSwitcherDialog` — open + recent sections, filter on display
  name and path, arrow/Enter/Escape keyboard handling, per-row Close and
  Forget, active-project chip, optional cross-project-search footer.
- `CruxRecentProjectsPanel` — recents list with Reopen / Forget and the
  "crop, don't crush" bounded-height behavior.
- `CruxProjectsUiStrings` — host-supplied copy (no ARB in this package).
- `cruxProjectsUiBadgeBuilderProvider` — optional host tier badge.
- `crossProjectSearchOpenerProvider` — optional; absent hides the footer.

Behavior differences from the SimCrux original, both deliberate:

- The cross-project-search footer is **hidden** when no opener is
  installed, rather than rendered and inert.
- The tier badge is **optional** rather than hardcoded, since the package
  cannot know a host's tier model.
