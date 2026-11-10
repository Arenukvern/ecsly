import 'package:ecsly/ecsly.dart';

/// Column factory for CameraPosition component.
/// Creates FloatColumn with stride 6 (x, y, targetX, targetY, zoom, targetZoom).
class CameraPositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 6);
}

/// Component marker for CameraPosition.
abstract final class CameraPositionComponent extends Component {}

/// Factory for CameraPosition facade.
class CameraPositionFacadeFactory
    extends ComponentFacadeFactory<CameraPosition> {
  /// Creates a facade factory for camera position data.
  CameraPositionFacadeFactory();

  late FloatColumn _column;

  @override
  CameraPosition create(final int index) => CameraPosition((index, _column));

  @override
  void initialize(covariant final FloatColumn column) {
    _column = column;
  }
}

/// Zero-cost facade for CameraPosition component.
/// Stores camera position, target position, and zoom levels.
extension type const CameraPosition((int index, FloatColumn column) data) {
  /// Target X position (for lerp smoothing)
  double get targetX => data.$2.getValue(data.$1, 2);
  set targetX(final double value) => data.$2.setValue(data.$1, 2, value);

  /// Target Y position (for lerp smoothing)
  double get targetY => data.$2.getValue(data.$1, 3);
  set targetY(final double value) => data.$2.setValue(data.$1, 3, value);

  /// Target zoom level (for smooth zoom interpolation)
  double get targetZoom => data.$2.getValue(data.$1, 5);
  set targetZoom(final double value) => data.$2.setValue(data.$1, 5, value);

  /// Current X position (world coordinates of camera center)
  double get x => data.$2.getValue(data.$1, 0);
  set x(final double value) => data.$2.setValue(data.$1, 0, value);

  /// Current Y position (world coordinates of camera center)
  double get y => data.$2.getValue(data.$1, 1);
  set y(final double value) => data.$2.setValue(data.$1, 1, value);

  /// Current zoom level (1.0 = normal, >1.0 = zoomed in, <1.0 = zoomed out)
  double get zoom => data.$2.getValue(data.$1, 4);
  set zoom(final double value) => data.$2.setValue(data.$1, 4, value);

  /// Set the target position for camera movement.
  /// The camera will smoothly interpolate to this position over time.
  void setTarget(final double x, final double y) {
    targetX = x;
    targetY = y;
  }

  /// Set the target zoom level.
  /// Values should be clamped externally (typically 0.1 to 5.0).
  // ignore: use_setters_to_change_properties
  void setZoom(final double newZoom) {
    targetZoom = newZoom;
  }
}
