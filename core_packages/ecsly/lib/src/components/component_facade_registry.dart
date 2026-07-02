import '../errors/ecs_errors.dart';
import 'columns/data_column.dart';
import 'component.dart';
import 'component_facade_factory.dart';

/// Registry for component facades.
/// Manages facade factories and creates facades for components.
class ComponentFacadeRegistry {
  /// Create a new registry instance (for testing or multiple worlds)
  factory ComponentFacadeRegistry() => ComponentFacadeRegistry._();

  ComponentFacadeRegistry._();

  /// Singleton instance (for convenience, can also be passed explicitly)
  static final ComponentFacadeRegistry instance = ComponentFacadeRegistry._();

  // Sparse arrays for O(1) access instead of HashMap (ComponentId.maxValue = 255)
  final List<ComponentFacadeFactory?> _factories = List.filled(
    ComponentId.maxValue + 1,
    null,
  );
  final List<Type?> _componentIdToExtensionType = List.filled(
    ComponentId.maxValue + 1,
    null,
  );

  // Track last initialized column per ComponentId to avoid redundant initialization
  final List<DataColumn?> _lastInitializedColumns = List.filled(
    ComponentId.maxValue + 1,
    null,
  );

  /// Create facade for component.
  ///
  /// [componentId] - The ID of the component to create a facade for.
  /// [index] - The index of the entity in the column.
  /// [column] - The column to create a facade for.
  T createFacade<T>(
    final ComponentId componentId,
    final int index,
    final DataColumn column,
  ) {
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    var factory = _factories[componentId.value];

    // Auto-generate facade factory for ObjectColumn if not registered
    if (factory == null) {
      if (column case final ObjectColumn c) {
        // Use type-erased factory - Component extends Object, so this is safe
        factory = _createAutoFacadeFactoryForObjectColumn(componentId, c);
      } else {
        throw EcsStateError('No facade factory for component $componentId');
      }
    }

    // Check if column already initialized to avoid redundant initialization
    final lastInitialized = _lastInitializedColumns[componentId.value];
    if (lastInitialized != column) {
      try {
        factory.initialize(column);
      } on Object catch (error, stackTrace) {
        throw EcsStateError(
          'Failed to initialize facade factory for component $componentId. '
          'Factory: ${factory.runtimeType}, column: ${column.runtimeType} '
          '(${_describeColumnKind(column)}). '
          'This usually means ComponentId mapping drift between worlds or an '
          'incorrectly registered component/facade pair.\n'
          'Original error: $error\n$stackTrace',
        );
      }
      _lastInitializedColumns[componentId.value] = column;
    }

    // Create facade (extension type constructor or object for ObjectColumn)
    return factory.create(index) as T;
  }

  /// Create facade with automatic type resolution for queries.
  ///
  /// Resolves the correct type to use based on ComponentId:
  /// - For extension type components: uses the extension type (looked up from ComponentId)
  /// - For ObjectColumn components: uses the Component class type [componentClass]
  ///
  /// This is used by query iterators to handle both extension types and ObjectColumn components.
  ///
  /// [componentId] - The ID of the component to create a facade for.
  /// [index] - The index of the entity in the column.
  /// [componentClass] - The Component class type (used for ObjectColumn components).
  dynamic createFacadeForQuery(
    final ComponentId componentId,
    final int index,
    final Type componentClass,
  ) {
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    final extensionType = getExtensionType(componentId);
    if (extensionType == null) {
      throw EcsStateError(
        'No facade factory for component $componentId. '
        'Factory must be registered or initialized before calling createFacadeForQuery.',
      );
    }

    final factory = _factories[componentId.value];
    if (factory == null) {
      throw EcsStateError('No facade factory for component $componentId');
    }

    final facade = factory.create(index);

    // If extension type is Object, it's an ObjectColumn - return as Component class type
    if (extensionType == Object) {
      return facade as Component;
    }

    // Otherwise, return the extension type facade directly (factory already creates correct type)
    return facade;
  }

  /// Create facade without initializing the column.
  ///
  /// Assumes the column has already been initialized via [initializeColumn].
  /// Use this in hot paths after initialization to avoid redundant static field writes.
  ///
  /// [componentId] - The ID of the component to create a facade for.
  /// [index] - The index of the entity in the column.
  T createFacadeWithoutInit<T>(final ComponentId componentId, final int index) {
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    final factory = _factories[componentId.value];
    if (factory == null) {
      throw EcsStateError(
        'No facade factory for component $componentId. '
        'Factory must be registered or initialized before calling createFacadeWithoutInit.',
      );
    }
    return factory.create(index) as T;
  }

  /// Get extension type for a component ID.
  /// Returns null if no factory is registered for the component.
  Type? getExtensionType(final ComponentId componentId) {
    if (!componentId.isValid) return null;
    return _componentIdToExtensionType[componentId.value];
  }

  /// Get factory for component ID (for query iterator optimization).
  /// Returns null if no factory is registered.
  ComponentFacadeFactory? getFactory(final ComponentId componentId) {
    if (!componentId.isValid) return null;
    return _factories[componentId.value];
  }

  /// Check if a factory is registered for the given component ID.
  bool hasFactory(final ComponentId componentId) {
    if (!componentId.isValid) return false;
    return _factories[componentId.value] != null;
  }

  /// Initialize column reference for a component factory.
  ///
  /// Call this once per archetype when the column changes.
  /// After initialization, use [createFacadeWithoutInit] to create facades
  /// without redundant initialization.
  ///
  /// [componentId] - The ID of the component.
  /// [column] - The column to initialize.
  ComponentFacadeFactory initializeColumn(
    final ComponentId componentId,
    final DataColumn column,
  ) {
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    var factory = _factories[componentId.value];

    // Auto-generate facade factory for ObjectColumn if not registered
    if (factory == null) {
      // For ObjectColumn, we need to determine the type from the column
      // Since we can't get T from ObjectColumn<T> at runtime, we'll create
      // a generic factory that works with any ObjectColumn
      if (column case final ObjectColumn c) {
        factory = _createAutoFacadeFactoryForObjectColumn(componentId, c);
      } else {
        throw EcsStateError('No facade factory for component $componentId');
      }
    }

    // Check if already initialized to avoid redundant initialization
    final lastInitialized = _lastInitializedColumns[componentId.value];
    if (lastInitialized != column) {
      try {
        factory.initialize(column);
      } on Object catch (error, stackTrace) {
        throw EcsStateError(
          'Failed to initialize facade factory for component $componentId. '
          'Factory: ${factory.runtimeType}, column: ${column.runtimeType} '
          '(${_describeColumnKind(column)}). '
          'This usually means ComponentId mapping drift between worlds or an '
          'incorrectly registered component/facade pair.\n'
          'Original error: $error\n$stackTrace',
        );
      }
      _lastInitializedColumns[componentId.value] = column;
    }
    return factory;
  }

  /// Register facade factory for component type.
  void registerFactory<TExtension>(
    final ComponentId componentId,
    final ComponentFacadeFactory<TExtension> factory,
  ) {
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    _factories[componentId.value] = factory;
    _componentIdToExtensionType[componentId.value] = TExtension;
  }

  /// Unregister facade factory for component type.
  void unregisterFactory(final ComponentId componentId) {
    if (!componentId.isValid) return;
    _factories[componentId.value] = null;
    _componentIdToExtensionType[componentId.value] = null;
    _lastInitializedColumns[componentId.value] = null;
  }

  /// Create auto-generated facade factory for ObjectColumn components.
  ///
  /// For ObjectColumn, the facade is just the object itself since ObjectColumn
  /// already stores Component objects directly.
  ///
  /// Note: This uses a type-erased factory since we can't extract T from [ObjectColumn<T>]
  /// at runtime. The returned object is cast to T when used.
  ComponentFacadeFactory _createAutoFacadeFactoryForObjectColumn(
    final ComponentId componentId,
    final DataColumn column,
  ) {
    if (column is! ObjectColumn) {
      throw ArgumentError('Expected ObjectColumn, got ${column.runtimeType}');
    }

    // Create a type-erased factory that works with any ObjectColumn
    final factory = _ObjectColumnFacadeFactoryErased(column);
    if (!componentId.isValid) {
      throw ArgumentError('Invalid ComponentId: $componentId');
    }
    _factories[componentId.value] = factory;
    // We can't determine the exact type, so we'll use Object
    // The actual type will be preserved when casting the result
    _componentIdToExtensionType[componentId.value] = Object;
    return factory;
  }

  String _describeColumnKind(final DataColumn column) => switch (column) {
    FloatColumn() => 'typed float column',
    IntColumn() => 'typed int column',
    Uint8Column() => 'typed uint8 column',
    ObjectColumn() => 'object column',
  };
}

/// Type-erased facade factory for ObjectColumn components.
///
/// For ObjectColumn, the facade is the object itself since ObjectColumn
/// already stores Component objects directly.
class _ObjectColumnFacadeFactoryErased extends ComponentFacadeFactory {
  _ObjectColumnFacadeFactoryErased(this._column);

  ObjectColumn _column;

  @override
  // For ObjectColumn, return the object directly
  Object create(final int index) => _column.getValue(index)!;

  @override
  void initialize(final DataColumn column) {
    if (column case final ObjectColumn c) {
      _column = c;
      return;
    }
    throw ArgumentError('Expected ObjectColumn, got ${column.runtimeType}');
  }
}
