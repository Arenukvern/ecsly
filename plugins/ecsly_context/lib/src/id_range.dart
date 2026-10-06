/// A closed, contiguous range of beat ids (`[start, end]`, both inclusive).
///
/// Ids are 1-based and monotonic, so a range names beat content without
/// holding any text.
// Value object with all-final fields; the lint's @immutable marker lives in
// package:meta, which this SDK-only package does not depend on.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
final class IdRange {
  /// Creates a range from [start] to [end], both inclusive.
  const IdRange(this.start, this.end)
    : assert(
        start >= 0,
        'start must be a non-negative beat id',
      ),
      assert(start <= end, 'start must not exceed end');

  /// Lowest beat id in the range.
  final int start;

  /// Highest beat id in the range.
  final int end;

  /// Number of ids in the range.
  int get length => end - start + 1;

  /// Whether the range names exactly one id.
  bool get isSingle => start == end;

  /// Whether [id] lies inside the range.
  bool contains(final int id) => id >= start && id <= end;

  /// Merges overlapping and adjacent ranges; returns the rest sorted.
  static List<IdRange> merge(final Iterable<IdRange> ranges) {
    final sorted = ranges.toList()
      ..sort((final a, final b) => a.start.compareTo(b.start));
    final merged = <IdRange>[];
    for (final range in sorted) {
      if (merged.isEmpty) {
        merged.add(range);
      } else {
        final last = merged.last;
        if (range.start <= last.end + 1 && range.end > last.end) {
          merged[merged.length - 1] = IdRange(last.start, range.end);
        } else if (range.start > last.end + 1) {
          merged.add(range);
        }
      }
    }
    return merged;
  }

  @override
  bool operator ==(final Object other) =>
      other is IdRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '#$start-$end';
}
