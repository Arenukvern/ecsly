import '../component_data_extractor.dart';

/// Extractor for primitive num/int components.
///
/// Handles components that are themselves numeric values.
class PrimitiveExtractor implements ComponentDataExtractor<Object> {
  @override
  List<double> extractFloats(final Object data) {
    // Handle case where component data is directly a num
    if (data case final num number) {
      return [number.toDouble()];
    }
    return [];
  }

  @override
  // Handle case where component data is directly an int or num
  int? extractInt(final Object data) => switch (data) {
    final int number => number,
    final num number => number.toInt(),
    _ => null,
  };

  @override
  // If component is a primitive value, return it as object
  Object? extractObject(final Object data) => data;
}
