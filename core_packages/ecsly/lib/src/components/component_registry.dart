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
    ColumnFactoryRegistry? columnFactoryRegistry,
    ComponentFacadeRegistry? componentFacadeRegistry,
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
  final List<Component?> _idToSample = List<Component?>.filled(
    ComponentId.maxValue + 1,
    null,
  );
  final List<String?> _idToName = List<String?>.filled(
    ComponentId.maxValue + 1,
    null,
  );
  final Map<String, ComponentId> _nameToId = {};
  int _nextId = 0;

  ColumnFactoryRegistry get columnFactoryRegistry => _columnFactoryRegistry;
  ComponentFacadeRegistry get componentFacadeRegistry =>
      _componentFacadeRegistry;

  /// Creates a new Column instance for the given component type.
  /// Uses ColumnFactory to determine the appropriate column type.
  DataColumn createColumnFor(Type type, {int initialCapacity = 8}) {
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
  ComponentId? getComponentIdByType(Type componentType) =>
      _typeToId.get(componentType);

  /// Gets the Type for a given ComponentId.
  Type getType(ComponentId id) {
    final type = _idToType[id];
    if (type == null) {
      throw EcsStateError('ComponentId $id is not registered');
    }
    return type;
  }

  /// All registered component types mapped to their IDs.
  ///
  /// Read-only view; useful for reflection-style tooling. Prefer
  /// [nameOf] / [componentIdByName] for stable cross-world identity.
  Map<ComponentId, Type> get registeredTypes => Map.unmodifiable(_idToType);

  /// Sample instance registered for [id], or null.
  ///
  /// Mirrors the event-side `sampleEvent` pattern: a representative instance
  /// provided at registration time so reflection-free tooling (serialization,
  /// replay) can construct components by ID without app-provided factories.
  Component? sampleFor(ComponentId id) => _idToSample[id.value];

  /// The stable name registered for [id], or null when the type was
  /// registered without one.
  ///
  /// Stable names are the cross-world identity used by serialization-style
  /// tooling: unlike `Type.toString()` they survive class renames, cannot
  /// collide across libraries, and are independent of compiler minification.
  String? nameOf(ComponentId id) => _idToName[id.value];

  /// The [ComponentId] registered under stable [name], or null.
  ComponentId? componentIdByName(String name) => _nameToId[name];

  ComponentStorageTier getStorageTier(ComponentId id) {
    final tier = _idToTier[id.value];
    if (tier == null) {
      throw EcsStateError('ComponentId $id is not registered');
    }
    return tier;
  }

  bool isObjectComponent(ComponentId id) =>
      getStorageTier(id) == ComponentStorageTier.object;

  /// Register a SoA (typed-data) component for hot simulation paths.
  ///
  /// [sample] is an optional representative instance used by reflection-free
  /// tooling such as snapshot restore to construct spawn-time placeholders.
  ComponentId registerSoAComponent<T extends Component>({
    required ColumnFactory columnFactory,
    T? sample,
    String? name,
  }) => _registerComponentInternal<T>(
    columnFactory: columnFactory,
    tier: ComponentStorageTier.soa,
    sample: sample,
    name: name,
  );

  /// Register an object component for cold paths.
  ///
  /// [sample] is an optional representative instance used by reflection-free
  /// tooling such as snapshot restore to construct spawn-time placeholders.
  /// [name] is an optional stable cross-world identity for serialization-style
  /// tooling; when omitted, tooling falls back to `Type.toString()`.
  ComponentId registerObjectComponent<T extends Component>({
    ColumnFactory? columnFactory,
    T? sample,
    String? name,
  }) => _registerComponentInternal<T>(
    columnFactory: columnFactory ?? ObjectColumnFactory<T>(),
    tier: ComponentStorageTier.object,
    sample: sample,
    name: name,
  );

  /// Register a presence-only SoA tag component backed by a compact byte column.
  ComponentId registerTagComponent<T extends Component>({
    String? name,
  }) => _registerComponentInternal<T>(
    columnFactory: _TagColumnFactory(),
    tier: ComponentStorageTier.soa,
    name: name,
  );

  ComponentId _registerComponentInternal<T extends Component>({
    required ColumnFactory columnFactory,
    required ComponentStorageTier tier,
    T? sample,
    String? name,
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

    if (name != null) {
      final existing = _nameToId[name];
      if (existing != null) {
        throw EcsStateError(
          'Component name "$name" is already registered for '
          '${_idToType[existing]}.',
        );
      }
    }

    if (_nextId > ComponentId.maxValue) {
      throw EcsStateError('Maximum component types exceeded (256)');
    }

    final id = ComponentId(_nextId++);
    _typeToId.set(T, id);
    _idToType[id] = T;
    _idToTier[id.value] = tier;
    _idToSample[id.value] = sample;
    if (name != null) {
      _idToName[id.value] = name;
      _nameToId[name] = id;
    }

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
    required ColumnFactory columnFactory,
    required ComponentFacadeFactory<TExtension> facadeFactory,
    String? name,
  }) {
    final id = registerSoAComponent<T>(columnFactory: columnFactory, name: name);
    _componentFacadeRegistry.registerFactory<TExtension>(id, facadeFactory);
    return id;
  }

  void unregisterColumnFactory(ComponentId componentId) =>
      _columnFactoryRegistry.unregisterFactory(componentId);

  void unregisterFacadeFactory(ComponentId componentId) =>
      _componentFacadeRegistry.unregisterFactory(componentId);
}

final class _TagColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    ComponentId componentId, {
    int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}
