import 'package:ecsly/ecsly.dart';

/// Small object component for the most minimal example.
///
/// Object components are normal Dart objects. They are the easiest authoring
/// path and are a good default for cold data, small examples, and state that is
/// not updated across thousands of entities every frame.
class CounterComponent extends Component {
  CounterComponent(this.value);

  int value;
}

/// Registers [CounterComponent] using object storage.
///
/// This helper keeps the minimal example focused on world/entity/query flow
/// while still showing that component storage must be declared before use.
void registerCounterComponents(final World world) {
  // Registration gives ecsly a compact ComponentId and tells the world to store
  // CounterComponent values in an ObjectColumn.
  world.components.registerObjectComponent<CounterComponent>();
}

/// Example-only extension component for hot numeric data.
///
/// This class is intentionally just a marker. The actual per-entity numeric
/// data lives in FloatColumn and is accessed through the Energy extension type.
class EnergyComponent extends Component {
  const EnergyComponent();
}

/// Typed facade over one row of [EnergyComponent] column storage.
///
/// The facade stores only the row [index]. The actual values live in the static
/// [FloatColumn] connected by [_EnergyFacadeFactory.initialize]. Query APIs
/// create this facade for each matching row so user code can read/write fields
/// as named Dart properties while the data remains packed in typed storage.
extension type Energy._(int index) {
  static late FloatColumn _column;

  /// Connects all [Energy] facades to the column currently being queried.
  ///
  /// Application code should not call this directly. ecsly calls the facade
  /// factory when a query or entity extension needs typed access to a column.
  // ignore: avoid_setters_without_getters
  static set column(final FloatColumn column) {
    _column = column;
  }

  /// Current energy value stored at column slot `0`.
  double get current => _column.getValueUnsafe(index, 0);

  /// Maximum energy value stored at column slot `1`.
  double get max => _column.getValueUnsafe(index, 1);

  /// Per-schedule-tick regeneration stored at column slot `2`.
  double get regenPerTick => _column.getValueUnsafe(index, 2);

  /// Updates the current energy value in column slot `0`.
  set current(final double value) => _column.setValue(index, 0, value);

  /// Updates the maximum energy value in column slot `1`.
  set max(final double value) => _column.setValue(index, 1, value);

  /// Updates the regeneration value in column slot `2`.
  set regenPerTick(final double value) => _column.setValue(index, 2, value);
}

/// Creates the typed column used to store [EnergyComponent] data.
///
/// The stride is `3` because each entity row stores `current`, `max`, and
/// `regenPerTick`. This factory is registered with `registerExtension` so ecsly
/// knows how to allocate storage whenever an archetype contains
/// [EnergyComponent].
final class _EnergyColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(stride: 3, initialCapacity: initialCapacity);
}

/// Creates [Energy] facades for rows in an energy column.
///
/// Column factories own storage creation. Facade factories own typed access to
/// that storage. ecsly wires them together during queries and entity-extension
/// lookups, which is why user code can call
/// `queryExt<EnergyComponent, Energy>()` and receive named getters/setters.
final class _EnergyFacadeFactory extends ComponentFacadeFactory<Energy> {
  @override
  Energy create(final int index) => Energy._(index);

  @override
  /// Gives [Energy] facades access to the concrete [FloatColumn].
  ///
  /// ecsly calls this before creating facades for a column. The covariant
  /// parameter keeps this example compact because [_EnergyColumnFactory] always
  /// creates [FloatColumn] storage for [EnergyComponent].
  void initialize(covariant final FloatColumn column) {
    Energy.column = column;
  }
}

/// Cold debug metadata stored as an object component.
///
/// This intentionally uses object storage because labels are not part of the
/// hot numeric loop.
class DebugNoteComponent extends Component {
  const DebugNoteComponent(this.text);

  final String text;
}

/// Registers the advanced example components.
///
/// [DebugNoteComponent] uses object storage because it is cold readable
/// metadata. [EnergyComponent] uses extension storage because it represents
/// compact numeric data that a system may update frequently.
void registerEnergyExampleComponents(final World world) {
  // The debug note is cold, readable metadata, so object storage is clearer.
  world.components.registerObjectComponent<DebugNoteComponent>();

  // Energy is compact numeric data, so the example stores it in a FloatColumn
  // and exposes typed access through the Energy facade.
  world.components.registerExtension<EnergyComponent, Energy>(
    columnFactory: _EnergyColumnFactory(),
    facadeFactory: _EnergyFacadeFactory(),
  );
}
