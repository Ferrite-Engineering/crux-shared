# crux_async

Cross-suite pure-Dart async/timing primitives. One implementation today:
**`Debouncer`**, coalescing a burst of calls into a single trailing
invocation.

```dart
import 'package:crux_async/crux_async.dart';

final _filterDebouncer = Debouncer(); // 200 ms default

TextField(
  onChanged: (v) => _filterDebouncer.run(() => notifier.setFilter(v)),
);

@override
void dispose() {
  _filterDebouncer.dispose(); // cancels any still-pending call
  super.dispose();
}
```

## Why the package exists

Extracted from `lintcrux/lib/core/util/debouncer.dart`, the only debouncer in
the suite, once a cross-product audit found the shape it prevents going wrong
twice more:

- A dashboard filter field elsewhere in the suite carried a doc comment
  claiming it was "debounced" while its `onChanged` called the setter on
  every keystroke — there was no debouncer there at all, hand-rolled or
  otherwise, so nothing enforced the claim.
- A log-panel Clear button elsewhere in the suite cleared the field but never
  cancelled the pending debounced call, so a keystroke landing inside the
  delay window re-applied the old filter text right after Clear ran.

Both are cancel/dispose-discipline bugs, not timing bugs: the fix is a
debouncer whose owner *cannot* forget to cancel it, not a smarter delay.

## The contract

- **`run(action)`** cancels any previously-scheduled, unfired `action` and
  reschedules `action` to run once, `duration` after this call. A rapid
  sequence of calls therefore fires the reaction exactly once, with the
  *last* call's closure — the closure captures whatever value that call
  cared about, so there is no separate "last value" to thread through.
- **`cancel()`** drops a pending call without running it. This is what a
  Clear/Reset affordance next to whatever `run` drives should call, so a
  keystroke that landed just before Clear cannot un-clear it afterward.
- **`flush()`** runs a pending call immediately, exactly once, instead of
  waiting out the rest of `duration` — e.g. a widget navigating away should
  apply a still-pending filter rather than silently drop it. A no-op when
  nothing is pending.
- **`dispose()`** cancels any pending call and marks the debouncer disposed.
  **Owners must call it** (typically from a widget's `dispose` or a
  notifier's teardown), or a callback scheduled just before teardown fires
  into whatever is left — a disposed widget's `setState`, or a notifier
  nobody is listening to anymore.
- **`run()`/`flush()` after `dispose()` assert.** `assert` is stripped in
  release builds, where the same call is a no-op instead — never a fresh
  `Timer`, never a stray fire, in either build mode. `cancel()` after
  `dispose()` is always a plain no-op; a teardown path that calls `cancel()`
  defensively before `dispose()` should never need to care about ordering.
- **`isActive`** reports whether a callback is currently scheduled and not
  yet fired.

## What this package deliberately does not do

No `ValueNotifier`/`TextEditingController` wrapper. Every call site surveyed
at extraction time drives its own `TextEditingController` and calls
`run`/`cancel` directly from `onChanged`/`dispose` — there was no second
shape to generalize over. A wrapper can be added here later the same way
`Debouncer` itself was: lifted from a second, proven call site, not designed
ahead of one.

## Scope

Deliberately tiny, like `crux_io`: pure Dart, `dart:async` only, no
dependency on any other Crux package or on Flutter, so it is usable from a
headless `dart build cli` binary as readily as from a widget's `onChanged`.
