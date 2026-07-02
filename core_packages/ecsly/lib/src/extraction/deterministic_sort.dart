import 'dart:typed_data';

/// Deterministic key used to order extracted rows.
///
/// Ordering contract:
/// - primary: render/collision layer
/// - secondary: material/group
/// - tertiary: depth bucket
/// - tieBreaker: entity index/generation-stable integer
typedef DeterministicOrderKey = (
  int primary,
  int secondary,
  int tertiary,
  int tieBreaker,
);

/// Compares two deterministic extraction keys.
int compareDeterministicOrderKey(
  final DeterministicOrderKey a,
  final DeterministicOrderKey b,
) {
  final primary = a.$1.compareTo(b.$1);
  if (primary != 0) return primary;

  final secondary = a.$2.compareTo(b.$2);
  if (secondary != 0) return secondary;

  final tertiary = a.$3.compareTo(b.$3);
  if (tertiary != 0) return tertiary;

  return a.$4.compareTo(b.$4);
}

/// Returns row indices sorted using deterministic integer keys.
List<int> deterministicSortedIndices(
  final int count, {
  required final int Function(int row) primary,
  required final int Function(int row) secondary,
  required final int Function(int row) tertiary,
  required final int Function(int row) tieBreaker,
}) {
  final indices = Int32List(count);
  for (var i = 0; i < count; i++) {
    indices[i] = i;
  }

  indices.sort((final a, final b) {
    final ka = (primary(a), secondary(a), tertiary(a), tieBreaker(a));
    final kb = (primary(b), secondary(b), tertiary(b), tieBreaker(b));
    return compareDeterministicOrderKey(ka, kb);
  });

  return List<int>.generate(count, (final i) => indices[i], growable: false);
}
