import '../../components/columns/data_column.dart';
import 'extractor_registry.dart';

/// Utility for extracting component data from component objects and writing to columns.
///
/// Uses type-safe extractors registered in ExtractorRegistry to eliminate
/// dynamic property access and improve performance.
class ComponentDataWriter {
  ComponentDataWriter._();

  /// Extract float values from component data.
  ///
  /// Uses registered extractors for type-safe extraction.
  /// Falls back to default extractors for unregistered component types.
  static List<double> extractFloats(final Object data) {
    final extractor = ExtractorRegistry.instance.getExtractorFor(data);
    return extractor.extractFloats(data);
  }

  /// Write component data to column based on column type.
  ///
  /// Handles FloatColumn, IntColumn, Uint8Column, and ObjectColumn.
  /// Uses type-safe extractors for data extraction.
  static void writeToColumn(
    final DataColumn column,
    final int rowIndex,
    final Object data,
  ) {
    final extractor = ExtractorRegistry.instance.getExtractorFor(data);

    switch (column) {
      case final FloatColumn c:
        final floats = extractor.extractFloats(data);
        for (int i = 0; i < floats.length && i < c.stride; i++) {
          c.setValue(rowIndex, i, floats[i]);
        }
      case final IntColumn c:
        final intValue = extractor.extractInt(data);
        if (intValue != null) {
          c.setValueAt(rowIndex, intValue);
        }
      case final Uint8Column c:
        final intValue = extractor.extractInt(data);
        if (intValue != null) {
          c.setValue(rowIndex, intValue);
        }
      case final ObjectColumn c:
        // ObjectColumn requires dynamic call due to generic type parameter
        // This is the only remaining dynamic usage, which is necessary for ObjectColumn<T>
        final object = extractor.extractObject(data);
        if (object != null) {
          (c as dynamic).setValue(rowIndex, object);
        }
    }
  }
}
