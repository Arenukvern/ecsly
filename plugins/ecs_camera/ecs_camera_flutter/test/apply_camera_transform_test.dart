import 'dart:ui' as ui;

import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:ecs_camera_flutter/ecs_camera_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('applyCameraTransform compiles and runs', (tester) async {
    final camera = EcsCamera2D(zoom: 2.0, centerX: 10, centerY: -5);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(100, 100);
    applyCameraTransform(canvas, size, camera);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    picture.dispose();
  });
}
