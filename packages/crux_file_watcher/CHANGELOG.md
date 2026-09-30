# Changelog

## Unreleased

### Fixed

- The debounce is now bounded by `maxWait` (default 2 s). Previously every
  filesystem event restarted the 500 ms timer with no ceiling, so a file
  under sustained writes — a simulator streaming into a dump for the
  duration of a run, which is the workload this package exists to serve —
  emitted **zero** events and auto-reload silently never triggered.
- Watch death is no longer swallowed. A platform watch error, a watch that
  ends on its own (deleted or renamed parent directory), and a watch that
  could never be established are all reported on the new
  `FileWatcherService.stopped` stream, and leave `isWatching` false so a
  host can take down its auto-reload affordance and offer a re-arm.
- A watch that dies with a debounced-but-unemitted event now flushes it
  before reporting the stop, so the final change (often the delete) is not
  lost.

### Added

- `FileWatcherService.stopped`, `isWatching`, `watchedPath`.
- `FileWatchStopped` / `FileWatchStopReason`.
- `debounceDelay` and `maxWait` constructor parameters.

## 0.0.1

- Initial extraction from WaveCrux open-core. `FileWatcherService`, `FileWatchEvent`, `WatchFactory` lifted verbatim with no API changes.
