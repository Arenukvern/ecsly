/// Column type for ECS component storage.
enum EcsColumnType {
  /// `FloatColumn` — 32-bit float (Float32List). Use for positions, velocities.
  float32,

  /// `IntColumn` — 32-bit int (Int32List). Use for handles, IDs.
  int32,

  /// `Uint8Column` — 8-bit unsigned (Uint8List). Use for health, tags, state.
  uint8,
}

/// Marks an `abstract final class ... extends Component` for column
/// infrastructure code generation.
///
/// Generates:
/// - `{Name}ColumnFactory` — creates the appropriate typed column
/// - `{Facade}FacadeFactory` — creates zero-cost facade instances
///
/// The extension type facade itself stays hand-written — custom domain
/// logic, helpers, and computed properties belong there.
///
/// ```dart
/// @EcsComponent(column: EcsColumnType.float32, stride: 4, facade: 'Position')
/// abstract final class PositionComponent extends Component {}
///
/// // Hand-written facade (not generated):
/// extension type const Position((int, FloatColumn) data) {
///   double get x => data.$2.getValue(data.$1, 0);
///   set x(double v) => data.$2.setValue(data.$1, 0, v);
///   // ... custom domain logic
/// }
/// ```
class EcsComponent {
  const EcsComponent({
    required this.column,
    required this.facade,
    this.stride = 1,
  });

  /// Column storage type.
  final EcsColumnType column;

  /// Number of values per entity row. Only relevant for FloatColumn/IntColumn.
  /// Uint8Column ignores stride (always 1 byte per slot).
  final int stride;

  /// Name of the hand-written extension type facade (e.g., 'Position').
  /// Used to generate the matching FacadeFactory.
  final String facade;
}
