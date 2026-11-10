import 'package:ecsly/ecsly.dart';

/// Viewport size (pure doubles). Updated by host (e.g. Flutter widget).
class ViewportSizeResource extends Resource {
  double width;

  double height;
  ViewportSizeResource({this.width = 800.0, this.height = 600.0});

  double get aspectRatio => height != 0 ? width / height : 1.0;

  void updateSize(final double w, final double h) {
    width = w;
    height = h;
  }
}
