// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A bounded map that drops its least-recently-used entries.
///
/// Insertion-ordered, so the first key is the one used longest ago: a read
/// through [operator []] or [putIfAbsent] moves the entry to the
/// most-recently-used end, and an insert that takes the cache past its
/// bounds evicts from the other end. Two bounds, whichever binds first:
/// [maxEntries], and, when a [weigh] function is given, [maxWeight] over the
/// sum of every value's weight. The entry bound alone is the wrong bound for
/// a cache of variable-size values — a count that says three files can hide
/// one generated multi-hundred-thousand-line source behind it — so a cache
/// whose values differ in size bounds the weight that tracks memory.
///
/// Three rules every copy of this cache in the suite got right in a different
/// way, fixed here:
///
/// - **A cached `null` is a hit.** Two call sites memoize nullable values
///   where `null` is a real answer ("this element has no name" is not "not
///   cached"). Presence is decided with `containsKey`, never with a null
///   check on `remove`, so [putIfAbsent] calls its builder once for such a
///   key and not on every read.
/// - **The newest entry is never the victim.** The entry just inserted or
///   just promoted is what the caller is about to use; a single value heavier
///   than [maxWeight] is kept rather than making the cache one that can never
///   hold the value being read.
/// - **An entry still in use is never evicted.** [isPinned] names the values
///   the cache must keep whatever the bounds say (a buffer with a live
///   listener, a layout mid-paint); when every candidate is pinned the cache
///   stays over its bounds rather than pulling a value out from under its
///   user.
///
/// [onEvict] receives every value the cache drops without handing it back,
/// through eviction or [clear], so a value that owns a resource (a text
/// layout, a stream controller) is released exactly once. [remove] hands the
/// value to the caller instead and does not call it.
///
/// Weights are read at eviction time, not stored at insertion, so a value
/// that grows after it was cached (a log buffer still being appended to) is
/// weighed as it is now. Over a cache of a few hundred entries that fold is
/// paid once per insert, not per read.
///
/// Not thread-safe, like every Dart collection, and the callbacks must not
/// touch the cache: they run while it is being pruned.
class LruCache<K, V> {
  /// Creates a cache holding at most [maxEntries] entries and, when [weigh]
  /// is given, at most [maxWeight] total weight.
  ///
  /// [maxWeight] requires [weigh]; [weigh] without [maxWeight] only serves
  /// [totalWeight].
  LruCache({
    required this.maxEntries,
    this.maxWeight,
    this.weigh,
    this.onEvict,
    this.isPinned,
  }) : assert(maxEntries >= 1, 'maxEntries must be at least 1'),
       assert(
         maxWeight == null || weigh != null,
         'maxWeight needs a weigh function',
       ),
       assert(
         maxWeight == null || maxWeight >= 1,
         'maxWeight must be at least 1',
       );

  /// Maximum entries retained. The least recently used go first.
  final int maxEntries;

  /// Maximum total weight retained, as summed by [weigh]; `null` bounds by
  /// entries only.
  final int? maxWeight;

  /// The weight of a value, read at eviction time. `null` weighs every
  /// entry as 1.
  final int Function(V value)? weigh;

  /// Called with every entry the cache drops through eviction or [clear],
  /// after it has left the cache. Not called by [remove], which hands the
  /// value back instead.
  final void Function(K key, V value)? onEvict;

  /// Whether an entry must survive eviction, asked for each candidate while
  /// pruning. `null` pins nothing.
  final bool Function(K key, V value)? isPinned;

  /// Insertion-ordered, least recently used first.
  final Map<K, V> _entries = <K, V>{};

  int _evictionCount = 0;

  /// Entries currently held.
  int get length => _entries.length;

  /// Whether the cache holds nothing.
  bool get isEmpty => _entries.isEmpty;

  /// Whether the cache holds anything.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// The keys, least recently used first. A live view: do not mutate the
  /// cache while iterating it.
  Iterable<K> get keys => _entries.keys;

  /// The values, least recently used first. A live view, like [keys].
  Iterable<V> get values => _entries.values;

  /// The entries, least recently used first. A live view, like [keys].
  Iterable<MapEntry<K, V>> get entries => _entries.entries;

  /// The sum of [weigh] over every value, or [length] without one.
  int get totalWeight {
    final weigh = this.weigh;
    if (weigh == null) return _entries.length;
    var sum = 0;
    for (final value in _entries.values) {
      sum += weigh(value);
    }
    return sum;
  }

  /// How many entries the bounds have evicted since construction. [clear]
  /// and [remove] do not count.
  int get evictionCount => _evictionCount;

  /// Whether [key] is cached. The only presence test that is right for a
  /// nullable `V`.
  bool containsKey(K key) => _entries.containsKey(key);

  /// The value for [key], promoted to most recently used, or `null` when
  /// absent.
  ///
  /// For a nullable `V` the two are indistinguishable here: use
  /// [putIfAbsent], or [containsKey] first.
  V? operator [](K key) {
    if (!_entries.containsKey(key)) return null;
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return value;
  }

  /// The value for [key] without promoting it, or `null` when absent.
  ///
  /// For walking [keys] and reading each entry without reordering the cache
  /// underneath the iteration.
  V? peek(K key) => _entries[key];

  /// Stores [value] under [key] as the most recently used entry, replacing
  /// any previous value without calling [onEvict] for it, then evicts past
  /// the bounds.
  void operator []=(K key, V value) {
    _entries
      ..remove(key)
      ..[key] = value;
    _evictToBounds();
  }

  /// The value for [key], promoted, or the result of [ifAbsent] stored under
  /// [key] when there is none.
  ///
  /// A cached `null` is a hit: [ifAbsent] runs only for a key the cache has
  /// never seen or has since evicted.
  V putIfAbsent(K key, V Function() ifAbsent) {
    if (_entries.containsKey(key)) return this[key] as V;
    final value = ifAbsent();
    _entries[key] = value;
    _evictToBounds();
    return value;
  }

  /// Removes [key] and hands its value back, or `null` when absent. Does not
  /// call [onEvict]: the caller holds the value now.
  V? remove(K key) => _entries.remove(key);

  /// Drops every entry, handing each to [onEvict].
  void clear() {
    final dropped = _entries.entries.toList(growable: false);
    _entries.clear();
    final onEvict = this.onEvict;
    if (onEvict == null) return;
    for (final entry in dropped) {
      onEvict(entry.key, entry.value);
    }
  }

  /// Evicts least-recently-used entries until both bounds hold, skipping the
  /// newest entry and every pinned one. Weights are read now, so a value
  /// that changed size since it was cached is weighed as it is.
  void _evictToBounds() {
    final weigh = this.weigh;
    final maxWeight = this.maxWeight;
    var weight = weigh == null ? _entries.length : totalWeight;
    bool within() =>
        _entries.length <= maxEntries &&
        (maxWeight == null || weight <= maxWeight);
    if (within()) return;
    final newest = _entries.keys.last;
    final onEvict = this.onEvict;
    final isPinned = this.isPinned;
    // A snapshot: eviction mutates the map while the keys are walked.
    for (final key in _entries.keys.toList(growable: false)) {
      if (within()) return;
      if (key == newest) continue;
      final value = _entries[key] as V;
      if (isPinned != null && isPinned(key, value)) continue;
      _entries.remove(key);
      weight -= weigh?.call(value) ?? 1;
      _evictionCount++;
      onEvict?.call(key, value);
    }
  }

  @override
  String toString() =>
      'LruCache(${_entries.length}/$maxEntries entries'
      '${maxWeight == null ? '' : ', $totalWeight/$maxWeight weight'})';
}
