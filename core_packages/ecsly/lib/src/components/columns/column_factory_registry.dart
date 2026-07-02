import '../../errors/ecs_errors.dart';
import '../component.dart';
import 'column_factory.dart';
import 'data_column.dart';

/// Factory for creating appropriate column types based on component characteristics.
///
/// This factory maps component types to their optimal storage strategy.
///
/// Example:
/// ```markdown
/// - Position → FloatColumn(stride: 2)
/// - Velocity → FloatColumn(stride: 2)
/// - Health → Uint8Column (0-255 range)
/// - Complex types → ObjectColumn<T>
/// ```
class ColumnFactoryRegistry {
  factory ColumnFactoryRegistry() => ColumnFactoryRegistry._();
  ColumnFactoryRegistry._();
  static final ColumnFactoryRegistry instance = ColumnFactoryRegistry._();
  final Map<ComponentId, ColumnFactory> _factories = {};
  DataColumn createColumn(
    final ComponentId componentId, {
    required final Type type,
    final int initialCapacity = 8,
  }) {
    final factory = _factories[componentId];
    if (factory == null) {
      throw EcsStateError(
        'No factory registered for component $componentId $type',
      );
    }
    return factory.createColumn(componentId, initialCapacity: initialCapacity);
  }

  bool hasFactory(final ComponentId componentId) =>
      _factories.containsKey(componentId);

  void registerFactory(
    final ComponentId componentId,
    final ColumnFactory factory,
  ) {
    _factories[componentId] = factory;
  }

  /// Unregister column factory for component type.
  void unregisterFactory(final ComponentId componentId) {
    _factories.remove(componentId);
  }

  /// Create FloatColumn with specified stride.
  static FloatColumn createFloatColumn({
    required final int stride,
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: stride);

  /// Create IntColumn.
  static IntColumn createIntColumn({
    final int initialCapacity = 8,
    final int stride = 1,
  }) => IntColumn(initialCapacity: initialCapacity, stride: stride);

  /// Create ObjectColumn for a specific type.
  static ObjectColumn<T> createObjectColumn<T extends Object>({
    final int initialCapacity = 8,
  }) => ObjectColumn<T>(initialCapacity: initialCapacity);

  /// Create Uint8Column for small integers (0-255 range).
  static Uint8Column createUint8Column({final int initialCapacity = 8}) =>
      Uint8Column(initialCapacity: initialCapacity);
}
