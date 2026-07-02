import '../component_data_extractor.dart';

/// Extractor for components that are `List<num>`.
///
/// Handles multi-value components stored as lists.
class ListExtractor implements ComponentDataExtractor<Object> {
  @override
  List<double> extractFloats(final Object data) {
    // Handle case where component data is directly a List<num>
    if (data case final List<num> list) {
      return list.map((final e) => e.toDouble()).toList();
    }
    return [];
  }

  @override
  int? extractInt(final Object data) => null;

  @override
  Object? extractObject(final Object data) {
    // If component is a List, return it as object
    if (data case final List list) {
      return list;
    }
    return null;
  }
}
