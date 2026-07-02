/// Type-safe extractor for component data during entity migration.
///
/// Extracts data from Component objects and converts them to column-compatible formats.
/// Eliminates dynamic property access by using type-safe extraction strategies.
///
/// Note: Accepts Object to handle both Component objects and raw data `(List<num>, num)`.
abstract class ComponentDataExtractor<T> {
  /// Extract float values from component data.
  ///
  /// Returns list of doubles that can be written to FloatColumn.
  /// Empty list if component doesn't contain float data.
  List<double> extractFloats(final T data);

  /// Extract integer value from component data.
  ///
  /// Returns integer value that can be written to IntColumn or Uint8Column.
  /// Null if component doesn't contain integer data.
  int? extractInt(final T data);

  /// Extract object from component data.
  ///
  /// Returns object that can be written to ObjectColumn.
  /// Null if component doesn't contain object data.
  Object? extractObject(final T data);
}
