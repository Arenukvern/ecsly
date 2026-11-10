import 'dart:math' as math;

/// Pure 2D camera (zoom + translation). No dart:ui, no Canvas.
class EcsCamera2D {
  double zoom;

  double centerX;
  double centerY;
  EcsCamera2D({this.zoom = 1.0, this.centerX = 0.0, this.centerY = 0.0});

  /// Screen coords (sx, sy) → world (wx, wy).
  (double wx, double wy) screenToWorld(
    double sx,
    double sy, {
    required double viewportW,
    required double viewportH,
  }) {
    final t = screenToWorldTransform(
      viewportW: viewportW,
      viewportH: viewportH,
    );
    return ((sx - t.invTx) * t.invScale, (sy - t.invTy) * t.invScale);
  }

  /// Screen → world transform: worldX = (screenX - invTx) * invScale, etc.
  ({double invScale, double invTx, double invTy}) screenToWorldTransform({
    required double viewportW,
    required double viewportH,
  }) {
    final halfW = viewportW / 2;
    final halfH = viewportH / 2;
    return (
      invScale: 1.0 / zoom,
      invTx: halfW - centerX * zoom,
      invTy: halfH - centerY * zoom,
    );
  }

  /// World bounds visible in viewport (with optional padding).
  math.Rectangle<double> viewBounds({
    required double viewportW,
    required double viewportH,
    double padding = 0.0,
  }) {
    final halfW = viewportW / zoom / 2 + padding;
    final halfH = viewportH / zoom / 2 + padding;
    return math.Rectangle<double>(
      centerX - halfW,
      centerY - halfH,
      halfW * 2,
      halfH * 2,
    );
  }

  /// World coords (wx, wy) → screen (sx, sy).
  (double sx, double sy) worldToScreen(
    double wx,
    double wy, {
    required double viewportW,
    required double viewportH,
  }) {
    final t = worldToScreenTransform(
      viewportW: viewportW,
      viewportH: viewportH,
    );
    return (wx * t.scale + t.tx, wy * t.scale + t.ty);
  }

  /// World → screen transform: screenX = (worldX - centerX) * scale + tx, etc.
  ({double scale, double tx, double ty}) worldToScreenTransform({
    required double viewportW,
    required double viewportH,
  }) {
    return (
      scale: zoom,
      tx: viewportW / 2 - centerX * zoom,
      ty: viewportH / 2 - centerY * zoom,
    );
  }
}
