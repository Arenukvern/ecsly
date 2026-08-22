// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'main.dart';

// **************************************************************************
// EcsComponentGenerator
// **************************************************************************

class ExamplePositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 2);
}

class ExamplePositionFacadeFactory
    extends ComponentFacadeFactory<ExamplePosition> {
  late FloatColumn _column;

  @override
  ExamplePosition create(final int index) => ExamplePosition((index, _column));

  @override
  void initialize(final DataColumn column) {
    if (column case final FloatColumn column) {
      _column = column;
      return;
    }
    throw ArgumentError(
      'ExamplePosition requires FloatColumn, got ${column.runtimeType}.',
    );
  }
}

final class ExamplePositionRegistration {
  const ExamplePositionRegistration._();

  /// Register this component with [world].
  ///
  /// Equivalent to:
  /// ```dart
  /// world.components.registerExtension<ExamplePositionComponent, ExamplePosition>(
  ///   columnFactory: ExamplePositionColumnFactory(),
  ///   facadeFactory: ExamplePositionFacadeFactory(),
  /// );
  /// ```
  static ComponentId register(final World world) => world.components
      .registerExtension<ExamplePositionComponent, ExamplePosition>(
        columnFactory: ExamplePositionColumnFactory(),
        facadeFactory: ExamplePositionFacadeFactory(),
      );
}
