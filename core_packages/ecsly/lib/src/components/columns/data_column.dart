import 'dart:typed_data';

part 'float_column.dart';
part 'int_column.dart';
part 'object_column.dart';
part 'uint8_column.dart';

/// Columns provide unified storage for components in a Structure-of-Arrays (SoA) layout.
/// This abstraction enables cache-friendly memory layout and SIMD-optimized operations.
sealed class DataColumn {
  /// Current capacity (may be larger than length).
  int get capacity;

  /// Number of elements (entities) in this column.
  int get length;

  /// Add a blank element at the end.
  void addBlank();

  /// Clear all elements (sets length to 0, doesn't deallocate).
  void clear();

  /// Copy element from this column to another column.
  void copyTo(
    final int sourceIndex,
    final DataColumn destination,
    final int destIndex,
  );

  /// Move element from this column to another column (clears source).
  void moveTo(
    final int sourceIndex,
    final DataColumn destination,
    final int destIndex,
  );

  /// Resize column to new capacity.
  void resize(final int newCapacity);

  /// Swap two elements at given indices (O(1)).
  void swap(final int indexA, final int indexB);

  /// Remove element at index by swapping with last (O(1)).
  void swapRemove(final int index);
}
