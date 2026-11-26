import 'dart:developer';
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';

void main() {
  final position = FloatColumn(stride: 2);
  final velocity = FloatColumn(stride: 2);
  for (var i = 0; i < 3; i++) {
    position.addBlank();
    velocity.addBlank();
    position.setValue(i, 0, i.toDouble());
    position.setValue(i, 1, 10);
    velocity.setValue(i, 0, 1);
    velocity.setValue(i, 1, -1);
  }

  final window = position.simdWindow;
  log(
    'stride2 vectors=${window.vectors.length} tailFloats=${window.tailFloats}',
  );
  updatePositionSimd(position, velocity, 0.5);
  for (var i = 0; i < position.length; i++) {
    log('p$i=(${position.getValue(i, 0)}, ${position.getValue(i, 1)})');
  }

  final wide = FloatColumn(stride: 4, initialCapacity: 4)..addBlank();
  wide.set(0, Float32List.fromList([1, 2, 3, 4]));
  final simd = wide.simdView;
  if (simd != null) {
    simd[0] = simd[0] + Float32x4(1, -1, 0, 0);
  }
  log(
    'stride4=(${wide.getValue(0, 0)}, ${wide.getValue(0, 1)}, '
    '${wide.getValue(0, 2)}, ${wide.getValue(0, 3)})',
  );
}
