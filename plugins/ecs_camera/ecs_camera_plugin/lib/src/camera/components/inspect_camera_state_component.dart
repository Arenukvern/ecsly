import 'package:ecsly/ecsly.dart';

/// Column factory for inspect camera state.
class InspectCameraStateColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 6);
}

/// Component marker for inspect camera state.
abstract final class InspectCameraStateComponent extends Component {}

/// Factory for inspect camera state facade.
class InspectCameraStateFacadeFactory
    extends ComponentFacadeFactory<InspectCameraState> {
  /// Creates a facade factory for inspect-camera orbit state.
  InspectCameraStateFacadeFactory();

  late FloatColumn _column;

  @override
  InspectCameraState create(final int index) =>
      InspectCameraState((index, _column));

  @override
  void initialize(covariant final FloatColumn column) {
    _column = column;
  }
}

/// Zero-cost facade for inspect camera orbit state.
extension type const InspectCameraState((int index, FloatColumn column) data) {
  /// Orbit target X coordinate.
  double get targetX => data.$2.getValue(data.$1, 0);
  set targetX(final double value) => data.$2.setValue(data.$1, 0, value);

  /// Orbit target Y coordinate.
  double get targetY => data.$2.getValue(data.$1, 1);
  set targetY(final double value) => data.$2.setValue(data.$1, 1, value);

  /// Orbit target Z coordinate.
  double get targetZ => data.$2.getValue(data.$1, 2);
  set targetZ(final double value) => data.$2.setValue(data.$1, 2, value);

  /// Orbit yaw in degrees.
  double get yawDeg => data.$2.getValue(data.$1, 3);
  set yawDeg(final double value) => data.$2.setValue(data.$1, 3, value);

  /// Orbit pitch in degrees.
  double get pitchDeg => data.$2.getValue(data.$1, 4);
  set pitchDeg(final double value) => data.$2.setValue(data.$1, 4, value);

  /// Orbit distance from target.
  double get distance => data.$2.getValue(data.$1, 5);
  set distance(final double value) => data.$2.setValue(data.$1, 5, value);

  /// Updates orbit target coordinates.
  void setTarget(final double x, final double y, final double z) {
    targetX = x;
    targetY = y;
    targetZ = z;
  }

  /// Updates yaw/pitch/distance in one call.
  void setPose({
    required final double yawDeg,
    required final double pitchDeg,
    required final double distance,
  }) {
    this.yawDeg = yawDeg;
    this.pitchDeg = pitchDeg;
    this.distance = distance;
  }
}
