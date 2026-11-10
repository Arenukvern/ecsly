import 'package:ecsly/ecsly.dart';

/// Column factory for CameraVelocity component.
/// Creates FloatColumn with stride 3 (dx, dy, damping).
class CameraVelocityColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 3);
}

/// Component marker for CameraVelocity.
abstract final class CameraVelocityComponent extends Component {}

/// Factory for CameraVelocity facade.
class CameraVelocityFacadeFactory
    extends ComponentFacadeFactory<CameraVelocity> {
  /// Creates a facade factory for camera velocity data.
  CameraVelocityFacadeFactory();

  late FloatColumn _column;

  @override
  CameraVelocity create(final int index) => CameraVelocity((index, _column));

  @override
  void initialize(covariant final FloatColumn column) {
    _column = column;
  }
}

/// Zero-cost facade for CameraVelocity component.
/// Stores camera velocity for momentum-based movement.
extension type const CameraVelocity((int index, FloatColumn column) data) {
  /// Damping factor (0.0 to 1.0) applied each frame.
  /// Lower values = more damping (slower decay).
  /// Typical values: 0.85-0.95 for smooth momentum.
  double get damping => data.$2.getValue(data.$1, 2);
  set damping(final double value) => data.$2.setValue(data.$1, 2, value);

  /// Velocity in X direction (pixels per second)
  double get dx => data.$2.getValue(data.$1, 0);
  set dx(final double value) => data.$2.setValue(data.$1, 0, value);

  /// Velocity in Y direction (pixels per second)
  double get dy => data.$2.getValue(data.$1, 1);
  set dy(final double value) => data.$2.setValue(data.$1, 1, value);

  /// Check if camera has significant momentum.
  bool get hasMomentum {
    const threshold = 0.01;
    return dx.abs() > threshold || dy.abs() > threshold;
  }
}
