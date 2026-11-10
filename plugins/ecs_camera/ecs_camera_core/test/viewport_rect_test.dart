import 'package:ecs_camera_core/ecs_camera_core.dart';
import 'package:test/test.dart';

void main() {
  test('fullScreen is 0,0,1,1', () {
    expect(ViewportRect.fullScreen.x, equals(0));
    expect(ViewportRect.fullScreen.y, equals(0));
    expect(ViewportRect.fullScreen.w, equals(1));
    expect(ViewportRect.fullScreen.h, equals(1));
  });

  test('custom rect stores normalized values', () {
    const r = ViewportRect(x: 0.25, y: 0.5, w: 0.5, h: 0.25);
    expect(r.x, equals(0.25));
    expect(r.y, equals(0.5));
    expect(r.w, equals(0.5));
    expect(r.h, equals(0.25));
  });

  test('toPixel scales by surface size', () {
    const r = ViewportRect(x: 0.25, y: 0.5, w: 0.5, h: 0.25);
    final p = r.toPixel(800, 600);
    expect(p.left, equals(200));
    expect(p.top, equals(300));
    expect(p.width, equals(400));
    expect(p.height, equals(150));
  });

  test('fullScreen toPixel equals full surface', () {
    final p = ViewportRect.fullScreen.toPixel(800, 600);
    expect(p.left, equals(0));
    expect(p.top, equals(0));
    expect(p.width, equals(800));
    expect(p.height, equals(600));
  });
}
