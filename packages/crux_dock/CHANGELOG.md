# Changelog

## 0.1.1

- `CruxDockRestoreBar` buttons are named buttons. An icon `InkWell` with only
  a tooltip merged into the bar's region node, so a screen reader announced
  the region name as bare text ("Panel dock, text") instead of the tab it
  restores.

## 0.1.0

- Initial release. `CruxDock` — the cross-suite VSCode-style tabbed region
  container for `CruxIdeLayout` regions: tab strip with `Badge.count` badges
  and per-tab close, auto-hiding single-pinned-entry header presentation,
  collapse / maximize / pop-out action cluster, and post-frame auto-reveal of
  newly appearing on-demand entries.
- `CruxDockEntry` — host-assembled tab descriptor whose `onClose` carries the
  suite's presence semantics (pinned vs. on-demand), generalized from
  WaveCrux's `BottomDockTab` plugin seam.
- `CruxDockPopOut` — the multi-window pop-out affordance configuration,
  rendered-but-disabled until Flutter multi-window reaches stable.
