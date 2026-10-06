import 'dart:typed_data';

/// A fixed-capacity set of beat ids over the contiguous id space, stored
/// as 64-bit words.
///
/// Columnar membership for the projection's hot loops: a freshness test
/// is one word-AND instead of per-id hash lookups, and a union is a word
/// copy. Ids are 1-based, matching the beat-graph id contract.
final class IdBitSet {
  /// Creates an empty set able to hold ids `1..capacity`.
  IdBitSet(final int capacity)
    : _words = Uint64List(capacity <= 0 ? 1 : (capacity + 63) ~/ 64);

  final Uint64List _words;

  /// Sets [id].
  void add(final int id) {
    final i = id - 1;
    _words[i >> 6] |= _bit(i);
  }

  /// Sets every id in [ids].
  void addAll(final Iterable<int> ids) {
    ids.forEach(add);
  }

  /// Whether [id] is set.
  bool contains(final int id) {
    final i = id - 1;
    if (i < 0 || i >= _words.length << 6) return false;
    return _words[i >> 6] & _bit(i) != 0;
  }

  /// Sets every bit that is set in [other].
  void union(final IdBitSet other) {
    final n = _words.length < other._words.length ? _words.length : other._words.length;
    for (var i = 0; i < n; i++) {
      _words[i] |= other._words[i];
    }
  }

  /// Whether any bit is set here that is clear in [excluded] — "this has
  /// something fresh the excluded set does not cover".
  bool hasAnyOutside(final IdBitSet excluded) {
    final n = _words.length < excluded._words.length
        ? _words.length
        : excluded._words.length;
    for (var i = 0; i < n; i++) {
      if (_words[i] & ~excluded._words[i] != 0) return true;
    }
    for (var i = n; i < _words.length; i++) {
      if (_words[i] != 0) return true;
    }
    return false;
  }

  static int _bit(final int i) => 1 << (i & 63);
}
