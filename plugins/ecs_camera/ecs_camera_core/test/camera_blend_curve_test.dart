import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:test/test.dart';

void main() {
  group('CameraBlendCurve', () {
    test('linear maps 0..1 to 0..1', () {
      expect(applyCameraBlendCurve(CameraBlendCurve.linear, 0), 0);
      expect(applyCameraBlendCurve(CameraBlendCurve.linear, 0.5), 0.5);
      expect(applyCameraBlendCurve(CameraBlendCurve.linear, 1), 1);
    });

    test('easeInOut is 0 at 0 and 1 at 1', () {
      expect(applyCameraBlendCurve(CameraBlendCurve.easeInOut, 0), 0);
      expect(applyCameraBlendCurve(CameraBlendCurve.easeInOut, 1), 1);
    });

    test('clamps t outside 0..1', () {
      expect(applyCameraBlendCurve(CameraBlendCurve.linear, -0.1), 0);
      expect(applyCameraBlendCurve(CameraBlendCurve.linear, 1.1), 1);
    });
  });
}
