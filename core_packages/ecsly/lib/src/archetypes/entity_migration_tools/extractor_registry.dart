import 'package:meta/meta.dart';

import 'component_data_extractor.dart';
import 'extractors/primitive_extractors.dart';

/// Registry for component data extractors.
///
/// Maps component types to type-safe extractors for entity migration.
/// Provides fallback extractors for unregistered component types.
class ExtractorRegistry {
  ExtractorRegistry._();

  static final ExtractorRegistry _instance = ExtractorRegistry._();
  static ExtractorRegistry get instance => _instance;

  final Map<Type, ComponentDataExtractor<Object>> _extractors = {};
  final PrimitiveExtractor _primitiveExtractor = PrimitiveExtractor();

  /// Clear all registered extractors (for testing).
  @visibleForTesting
  void clear() => _extractors.clear();

  /// Get extractor for a component type, with fallback to default extractors.
  ComponentDataExtractor<Object> getExtractor(final Type componentType) {
    // Check registered extractors first
    final extractor = _extractors[componentType];
    if (extractor != null) {
      return extractor;
    }

    // Fallback: try default extractors based on component type
    // If component is num/int, use PrimitiveExtractor
    if (_isPrimitiveType(componentType)) {
      return _primitiveExtractor;
    }

    // Default: return primitive extractor (will handle basic cases)
    // List types are handled at runtime by the extractors themselves
    return _primitiveExtractor;
  }

  /// Get extractor for a component instance, using runtime type.
  ComponentDataExtractor<Object> getExtractorFor(final Object data) =>
      getExtractor(data.runtimeType);

  /// Register an extractor for a specific component type.
  void register<T>(final ComponentDataExtractor<T> extractor) {
    _extractors[T] = extractor as ComponentDataExtractor<Object>;
  }

  /// Check if a type is num/int.
  bool _isPrimitiveType(final Type type) =>
      type == num || type == int || type == double;
}
