# Changelog

## 0.1.0

- Initial extraction. `Debouncer` lifted from
  `lintcrux/lib/core/util/debouncer.dart`, the only debouncer in the suite,
  after an audit found two products with cancel/dispose-discipline bugs a
  shared implementation is meant to make hard to repeat: a filter field
  documented as debounced that fired on every keystroke, and a Clear action
  that did not cancel a pending debounced call.
- Added `flush()` (run a pending call immediately, exactly once) alongside
  the existing `run()` / `cancel()` / `dispose()` / `isActive`, since a
  shared implementation is the right place to add the capability rather than
  each consumer growing its own.
- `run()`/`flush()` after `dispose()` now assert (stripped in release
  builds, where the same call is a no-op) rather than being silently
  accepted, so a callback wired to a disposed owner is caught in debug and
  test builds.
