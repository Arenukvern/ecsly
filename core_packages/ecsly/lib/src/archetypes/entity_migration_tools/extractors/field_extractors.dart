// ignore_for_file: unsafe_variance

import '../component_data_extractor.dart';

/// Extractor for components with a value field (Health, Score, etc.).
///
/// Supports both numeric and integer value fields.
class ValueFieldExtractor<T> implements ComponentDataExtractor<T> {
  ValueFieldExtractor({required this.getValue});

  /// Function to extract value from component.
  final num Function(T) getValue;

  @override
  List<double> extractFloats(final T component) {
    final value = getValue(component);
    return [value.toDouble()];
  }

  @override
  int? extractInt(final T component) {
    final value = getValue(component);
    return value.toInt();
  }

  @override
  Object? extractObject(final T component) => null;
}

/// Extractor for components with x and y fields (Position, Transform, Velocity).
///
/// Type-safe extraction using generic constraints.
class XYFieldExtractor<T> implements ComponentDataExtractor<T> {
  XYFieldExtractor({required this.getX, required this.getY});

  /// Function to extract x value from component.
  final double Function(T) getX;

  /// Function to extract y value from component.
  final double Function(T) getY;

  @override
  List<double> extractFloats(final T component) => [
    getX(component),
    getY(component),
  ];

  @override
  int? extractInt(final T component) => null;

  @override
  Object? extractObject(final T component) => null;
}
