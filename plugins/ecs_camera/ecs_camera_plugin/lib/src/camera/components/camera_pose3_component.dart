import 'package:ecsly/ecsly.dart';

/// Column factory for CameraPose3 component.
/// Stores posZ + quaternion + clip + optional zoom/fov override.
class CameraPose3ColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(initialCapacity: initialCapacity, stride: 8);
}

/// Component marker for CameraPose3.
abstract final class CameraPose3Component extends Component {}

/// Factory for CameraPose3 facade.
class CameraPose3FacadeFactory extends ComponentFacadeFactory<CameraPose3> {
  /// Creates a facade factory for 3D camera pose data.
  CameraPose3FacadeFactory();

  late FloatColumn _column;

  @override
  CameraPose3 create(final int index) => CameraPose3((index, _column));

  @override
  void initialize(covariant final FloatColumn column) {
    _column = column;
  }
}

/// Zero-cost facade for 3D pose fields consumed by render packet extraction.
extension type const CameraPose3((int index, FloatColumn column) data) {
  /// Camera world-space Z position.
  double get posZ => data.$2.getValue(data.$1, 0);
  set posZ(final double value) => data.$2.setValue(data.$1, 0, value);

  /// Quaternion X component.
  double get rotX => data.$2.getValue(data.$1, 1);
  set rotX(final double value) => data.$2.setValue(data.$1, 1, value);

  /// Quaternion Y component.
  double get rotY => data.$2.getValue(data.$1, 2);
  set rotY(final double value) => data.$2.setValue(data.$1, 2, value);

  /// Quaternion Z component.
  double get rotZ => data.$2.getValue(data.$1, 3);
  set rotZ(final double value) => data.$2.setValue(data.$1, 3, value);

  /// Quaternion W component.
  double get rotW => data.$2.getValue(data.$1, 4);
  set rotW(final double value) => data.$2.setValue(data.$1, 4, value);

  /// Optional zoom/fov override.
  /// Use `double.nan` sentinel to keep `CameraPosition.zoom`.
  double get zoomOrFovOverride => data.$2.getValue(data.$1, 5);
  set zoomOrFovOverride(final double value) =>
      data.$2.setValue(data.$1, 5, value);

  /// Near clip plane.
  double get near => data.$2.getValue(data.$1, 6);
  set near(final double value) => data.$2.setValue(data.$1, 6, value);

  /// Far clip plane.
  double get far => data.$2.getValue(data.$1, 7);
  set far(final double value) => data.$2.setValue(data.$1, 7, value);
}
