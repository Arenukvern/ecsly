import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:test/test.dart';

void main() {
  group('EcsCamera2D', () {
    test('viewBounds is deterministic for zoom and padding', () {
      final cam = EcsCamera2D(zoom: 2.0, centerX: 100, centerY: 50);
      final b = cam.viewBounds(viewportW: 800, viewportH: 600, padding: 10);
      // halfW = 800/2/2 + 10 = 210, halfH = 600/2/2 + 10 = 160
      expect(b.left, closeTo(100 - 210, 1e-9));
      expect(b.top, closeTo(50 - 160, 1e-9));
      expect(b.width, closeTo(420, 1e-9));
      expect(b.height, closeTo(320, 1e-9));
    });

    test('worldToScreen then screenToWorld round-trip', () {
      final cam = EcsCamera2D(zoom: 1.5, centerX: -10, centerY: 20);
      const vw = 640.0;
      const vh = 480.0;
      final (sx, sy) = cam.worldToScreen(
        100,
        -30,
        viewportW: vw,
        viewportH: vh,
      );
      final (wx, wy) = cam.screenToWorld(sx, sy, viewportW: vw, viewportH: vh);
      expect(wx, closeTo(100, 1e-9));
      expect(wy, closeTo(-30, 1e-9));
    });

    test('center maps to viewport center', () {
      final cam = EcsCamera2D(zoom: 2.0, centerX: 5, centerY: -5);
      final (sx, sy) = cam.worldToScreen(5, -5, viewportW: 100, viewportH: 100);
      expect(sx, closeTo(50, 1e-9));
      expect(sy, closeTo(50, 1e-9));
    });
  });
}
