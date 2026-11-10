/// Normalized viewport rect (0–1). Host multiplies by surface size for pixel rect.
///
/// Used for split-screen, minimap, or multiple camera viewports. Default is full
/// screen (0, 0, 1, 1).
class ViewportRect {
  final double x;
  final double y;
  final double w;
  final double h;

  const ViewportRect({this.x = 0.0, this.y = 0.0, this.w = 1.0, this.h = 1.0});

  /// Full screen: (0, 0, 1, 1).
  static const ViewportRect fullScreen = ViewportRect();

  /// Pixel rect for this viewport given surface [width] and [height].
  ({double left, double top, double width, double height}) toPixel(
    double width,
    double height,
  ) => (left: x * width, top: y * height, width: w * width, height: h * height);
}
