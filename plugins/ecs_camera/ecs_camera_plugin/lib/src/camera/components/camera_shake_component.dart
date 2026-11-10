import 'package:ecsly/ecsly.dart';

/// Column factory for CameraShake component.
/// Creates FloatColumn with stride 3 (offsetX, offsetY, decay).
class CameraShakeColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 3);
}

/// Component marker for CameraShake.
abstract final class CameraShakeComponent extends Component {}

/// Factory for CameraShake facade.
class CameraShakeFacadeFactory extends ComponentFacadeFactory<CameraShake> {
  /// Creates a facade factory for camera shake data.
  CameraShakeFacadeFactory();

  late FloatColumn _column;

  @override
  CameraShake create(final int index) => CameraShake((index, _column));

  @override
  void initialize(covariant final FloatColumn column) {
    _column = column;
  }
}

/// Zero-cost facade for CameraShake component.
/// Stores camera shake offset and decay rate for screen shake effects.
extension type const CameraShake((int index, FloatColumn column) data) {
  /// Decay rate per second (0.0 to 1.0).
  /// Lower values = slower decay (shake lasts longer).
  /// Typical values: 0.5-0.9 for natural decay.
  double get decay => data.$2.getValue(data.$1, 2);
  set decay(final double value) => data.$2.setValue(data.$1, 2, value);

  /// Check if camera has active shake.
  bool get hasShake {
    const threshold = 0.01;
    return offsetX.abs() > threshold || offsetY.abs() > threshold;
  }

  /// Current shake offset in X direction (world units)
  double get offsetX => data.$2.getValue(data.$1, 0);

  set offsetX(final double value) => data.$2.setValue(data.$1, 0, value);

  /// Current shake offset in Y direction (world units)
  double get offsetY => data.$2.getValue(data.$1, 1);

  set offsetY(final double value) => data.$2.setValue(data.$1, 1, value);

  /// Add shake impulse to the camera.
  /// [intensityX] - Shake intensity in X direction (world units)
  /// [intensityY] - Shake intensity in Y direction (world units)
  void addShake(final double intensityX, final double intensityY) {
    offsetX += intensityX;
    offsetY += intensityY;
  }

  /// Reset shake to zero.
  void reset() {
    offsetX = 0.0;
    offsetY = 0.0;
  }
}
