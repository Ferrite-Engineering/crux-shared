# Changelog

## 0.1.0

- Initial extraction. `LruCache<K, V>`: a bounded, insertion-ordered map
  that promotes on read and evicts its least-recently-used entries, with an
  optional weight bound (`maxWeight` + `weigh`, read at eviction time so a
  value that grew after it was cached is weighed as it is), an `onEvict`
  hook for values that own a resource, and an `isPinned` predicate for
  values that must not be evicted while in use. Lifted from four copies in
  the suite: a schematic painter's text-layout cache (entries, disposal), a
  source-file loader (entries and lines), a per-cycle sample memo in a Pro
  overlay (entries, nullable values) and a per-test log-buffer store
  (buffers and lines, disposal, never-evict-while-streamed). The copies
  agreed on the shape and differed on the details that matter, so the shared
  form pins each: a cached `null` is a hit, the newest entry is never the
  victim, and a pinned entry is skipped rather than ending the pass.
