# crux_collections

Cross-suite pure-Dart collection primitives. One class today, `LruCache`, and the
bar for the next one is the same as for every package here: written several times
across the suite, differently each time.

## `LruCache<K, V>`

A bounded, insertion-ordered map that promotes on read and evicts its
least-recently-used entries.

```dart
import 'package:crux_collections/crux_collections.dart';

final layouts = LruCache<String, TextLayout>(
  maxEntries: 2048,
  onEvict: (_, layout) => layout.dispose(),
);
final layout = layouts.putIfAbsent(key, () => buildLayout(key));

final sources = LruCache<String, SourceFile>(
  maxEntries: 32,
  maxWeight: 200000,                 // lines, whichever bound binds first
  weigh: (file) => file.lineCount,
);

final buffers = LruCache<String, LogBuffer>(
  maxEntries: 256,
  maxWeight: 200000,
  weigh: (buffer) => buffer.lineCount,   // read at eviction time
  isPinned: (_, buffer) => buffer.hasListener,
  onEvict: (_, buffer) => buffer.close(),
);
```

## Why the package exists

The same cache had been written four times: a schematic painter's text-layout
cache, a source-file loader, a per-cycle sample memo in a Pro overlay and a
per-test log-buffer store. All four used the same shape (an insertion-ordered
`Map`, remove-and-reinsert on read, evict `keys.first` past a cap), and between
them they needed four things no single copy had:

| Need | Who had it |
|---|---|
| An optional **weight** bound, because entries is the wrong bound for values that differ in size | the source loader, the log store |
| An **`onEvict`** hook, because an evicted value may own a resource | the painter (`dispose`), the log store (`close`) |
| A **never-evict** predicate, because a value still being streamed into must not be pulled out from under its reader | the log store |
| **`containsKey`, not a null check on `remove`**, because two sites memoize nullable values where `null` is a real answer | the sample memo |

The last one is the trap. A promote-on-read written as
`final v = map.remove(k); if (v != null) …` turns every cached `null` into a
permanent miss, and no test catches it, because the answers stay correct and only
the work is repeated.

## The rules

- **A cached `null` is a hit.** `putIfAbsent` calls its builder once for such a
  key; `containsKey` is the presence test. `operator []` returns `null` for both
  absent and cached-null, so a nullable `V` uses the other two.
- **The newest entry is never the victim.** The entry just inserted or promoted
  is the one the caller is about to use, so a single value heavier than
  `maxWeight` is kept.
- **A pinned entry is skipped, not a stopping point.** When every candidate is
  pinned the cache stays over its bounds.
- **Weights are read at eviction time.** A log buffer still being appended to is
  weighed as it is now, not as it was when cached. The fold is paid once per
  insert, never per read.
- **`onEvict` fires for what the cache drops on its own** (eviction, `clear`),
  not for `remove`, which hands the value back.
- **`peek` reads without promoting**, so a caller can walk `keys` and read each
  entry without reordering the cache underneath the iteration.
