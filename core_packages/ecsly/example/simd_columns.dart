import 'dart:developer';
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

class SimdVectorComponent extends Component {
  const SimdVectorComponent();
}

extension type SimdVector._(int index) {
  static late FloatColumn column;

  double get x => column.getValueUnsafe(index, 0);
  double get y => column.getValueUnsafe(index, 1);
  double get z => column.getValueUnsafe(index, 2);
  double get w => column.getValueUnsafe(index, 3);

  set x(final double value) => column.setValue(index, 0, value);
  set y(final double value) => column.setValue(index, 1, value);
  set z(final double value) => column.setValue(index, 2, value);
  set w(final double value) => column.setValue(index, 3, value);
}

final class _SimdVectorColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(stride: 4, initialCapacity: initialCapacity);
}

final class _SimdVectorFacadeFactory
    extends ComponentFacadeFactory<SimdVector> {
  @override
  SimdVector create(final int index) => SimdVector._(index);

  @override
  void initialize(covariant final FloatColumn column) {
    SimdVector.column = column;
  }
}

void main() {
  final world = World();
  world.components.registerExtension<SimdVectorComponent, SimdVector>(
    columnFactory: _SimdVectorColumnFactory(),
    facadeFactory: _SimdVectorFacadeFactory(),
  );

  for (var i = 0; i < 4; i++) {
    final entity = world.reserveEmptyEntity().entity;
    world.spawnBundle(
      entity,
      ComponentBundle.fromExtensionList(const [
        (SimdVectorComponent, SimdVector),
      ]),
    );
  }
  world.flush();

  var row = 0;
  for (final (_, vector) in world.queryExt<SimdVectorComponent, SimdVector>()) {
    vector.x = row.toDouble();
    vector.y = row.toDouble() + 10;
    vector.z = 0;
    vector.w = 1;
    row += 1;
  }

  final simd = SimdVector.column.simdView;
  if (simd != null) {
    final delta = Float32x4(1, -1, 0, 0);
    for (var i = 0; i < SimdVector.column.length; i++) {
      simd[i] = simd[i] + delta;
    }
  }

  for (final (_, vector) in world.queryExt<SimdVectorComponent, SimdVector>()) {
    log('vector=(${vector.x}, ${vector.y}, ${vector.z}, ${vector.w})');
  }
}
