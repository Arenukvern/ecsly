// A factory function for creating a Column instance for a component type.
import '../errors/ecs_errors.dart';
import 'columns/columns.dart';
import 'component.dart';
import 'component_facade_factory.dart';
import 'component_facade_registry.dart';
import 'sparse_type_list.dart';

enum ComponentStorageTier { soa, object }

/// A simple, stateless registry for component types.
///
/// Its sole responsibility is to map a component `Type` to a stable integer ID.
/// Column creation is handled by ColumnFactory. It does NOT queue or process any commands.
class ComponentRegistry {
  ComponentRegistry({
    final ColumnFactoryRegistry? columnFactoryRegistry,
    final ComponentFacadeRegistry? componentFacadeRegistry,
  }) : _columnFactoryRegistry =
           columnFactoryRegistry ?? ColumnFactoryRegistry(),
       _componentFacadeRegistry =
           componentFacadeRegistry ?? ComponentFacadeRegistry();

  final SparseTypeList _typeToId = SparseTypeList();
  final Map<ComponentId, Type> _idToType = {};
  final List<ComponentStorageTier?> _idToTier =
      List<ComponentStorageTier?>.filled(ComponentId.maxValue + 1, null);
  final ColumnFactoryRegistry _columnFactoryRegistry;
  final ComponentFacadeRegistry _componentFacadeRegistry;
  int _nextId = 0;

  ColumnFactoryRegistry get columnFactoryRegistry => _columnFactoryRegistry;
  ComponentFacadeRegistry get componentFacadeRegistry =>
      _componentFacadeRegistry;

  /// Creates a new Column instance for the given component type.
  /// Uses ColumnFactory to determine the appropriate column type.
  DataColumn createColumnFor(final Type type, {final int initialCapacity = 8}) {
    final componentId = getComponentIdByType(type);
    if (componentId == null) {
      throw ComponentNotRegisteredError(type);
    }
    return _columnFactoryRegistry.createColumn(
      componentId,
      initialCapacity: initialCapacity,
      type: type,
    );
  }

  /// Gets the ComponentId for a given component type.
  ComponentId getComponentId<T extends Component>() {
    final id = _typeToId.get(T);
    if (id == null) {
      throw ComponentNotRegisteredError(T);
    }
    return id;
  }

  /// Gets the ComponentId for a given component Type (non-generic version)
  ComponentId? getComponentIdByType(final Type componentType) =>
      _typeToId.get(componentType);

  /// Gets the Type for a given ComponentId.
  Type getType(final ComponentId id) {
    final type = _idToType[id];
    if (type == null) {
      throw EcsStateError('ComponentId $id is not registered');
    }
    return type;
  }

  ComponentStorageTier getStorageTier(final ComponentId id) {
    final tier = _idToTier[id.value];
    if (tier == null) {
      throw EcsStateError('ComponentId $id is not registered');
    }
    return tier;
  }

  bool isObjectComponent(final ComponentId id) =>
      getStorageTier(id) == ComponentStorageTier.object;

  /// Register a SoA (typed-data) component for hot simulation paths.
  ComponentId registerSoAComponent<T extends Component>({
    required final ColumnFactory columnFactory,
  }) => _registerComponentInternal<T>(
    columnFactory: columnFactory,
    tier: ComponentStorageTier.soa,
  );

  /// Register an object component for cold paths.
  ComponentId registerObjectComponent<T extends Component>({
    final ColumnFactory? columnFactory,
  }) => _registerComponentInternal<T>(
    columnFactory: columnFactory ?? ObjectColumnFactory<T>(),
    tier: ComponentStorageTier.object,
  );

  /// Register a presence-only SoA tag component backed by a compact byte column.
  ComponentId registerTagComponent<T extends Component>() =>
      _registerComponentInternal<T>(
        columnFactory: _TagColumnFactory(),
        tier: ComponentStorageTier.soa,
      );

  ComponentId _registerComponentInternal<T extends Component>({
    required final ColumnFactory columnFactory,
    required final ComponentStorageTier tier,
  }) {
    if (_typeToId.contains(T)) {
      final existingId = _typeToId.get(T)!;
      final existingTier = _idToTier[existingId.value];
      if (existingTier != null && existingTier != tier) {
        throw EcsStateError(
          'Component $T is already registered as $existingTier and '
          'cannot be re-registered as $tier.',
        );
      }
      return existingId;
    }

    if (_nextId > ComponentId.maxValue) {
      throw EcsStateError('Maximum component types exceeded (256)');
    }

    final id = ComponentId(_nextId++);
    _typeToId.set(T, id);
    _idToType[id] = T;
    _idToTier[id.value] = tier;

    _columnFactoryRegistry.registerFactory(id, columnFactory);

    return id;
  }

  /// Registers a new extension component type.
  /// Returns the ComponentId assigned to this extension component type.
  ///
  /// [columnFactory] - The factory to create the column for the extension component.
  /// [facadeFactory] - The factory to create the facade for the extension component.
  ///
  /// **Usage:**
  /// ```dart
  /// final id = ecsWorld.components.registerExtension<PositionComponent, Position>(
  ///   columnFactory: PositionColumnFactory(),
  ///   facadeFactory: PositionFacadeFactory(),
  /// );
  /// ```
  ComponentId registerExtension<T extends Component, TExtension>({
    required final ColumnFactory columnFactory,
    required final ComponentFacadeFactory<TExtension> facadeFactory,
  }) {
    final id = registerSoAComponent<T>(columnFactory: columnFactory);
    _componentFacadeRegistry.registerFactory<TExtension>(id, facadeFactory);
    return id;
  }

  void unregisterColumnFactory(final ComponentId componentId) =>
      _columnFactoryRegistry.unregisterFactory(componentId);

  void unregisterFacadeFactory(final ComponentId componentId) =>
      _componentFacadeRegistry.unregisterFactory(componentId);
}

final class _TagColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}
