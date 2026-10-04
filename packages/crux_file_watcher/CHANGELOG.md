# Changelog

## Unreleased

### Fixed

- **A change the platform watch misses can still be reported**
  (crux-shared#25). On macOS, `dart:io`'s directory watch can stop
  delivering events for the rest of the process, with no error and no done
  event, and a new watch in the same process hears nothing either. A host
  then raised one reload prompt and never another. `FileWatcherService`
  takes an optional `pollInterval`: while a watch is live, the file's size
  and modification time are read on that interval, and a change the watch
  did not report goes through the same debounce. A change both sources see
  is reported once. Off by default.

- **An attribute-only change is no longer reported as `modified`**
  (crux-shared#24). macOS writes an extended attribute to a file picked in
  the open dialog, and the watcher treated that as an edit, so a product
  offered to reload a file nobody had touched. A modify event that leaves
  the file's size and modification time as last seen is now dropped. The
  event's `contentChanged` flag is not consulted: a `touch` arrives with it
  false and still counts, because it moves the modification time. A file
  whose state cannot be read never suppresses an event. `FileWatcherService`
  takes an optional `statReader` for tests.
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

- `FileWatcherService.pollInterval`.
- `FileWatcherService.stopped`, `isWatching`, `watchedPath`.
- `FileWatchStopped` / `FileWatchStopReason`.
- `debounceDelay` and `maxWait` constructor parameters.

## 0.0.1

- Initial extraction from WaveCrux open-core. `FileWatcherService`, `FileWatchEvent`, `WatchFactory` lifted verbatim with no API changes.
