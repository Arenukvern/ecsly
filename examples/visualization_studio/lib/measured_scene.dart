import 'dart:ui' as ui;

import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter_scene/scene.dart' show RenderView;

import 'startup_trace.dart';

/// Observe the public renderer seam without changing its drawing behavior.
final class MeasuredScene extends Scene {
  MeasuredScene(this.trace);
  final StartupTrace trace;
  @override
  void renderViews(
    List<RenderView> views,
    ui.Canvas canvas, {
    ui.Rect? region,
    double? pixelRatio,
  }) {
    final area = region ?? canvas.getLocalClipBounds();
    final measurable = views.isNotEmpty && !area.isEmpty;
    if (measurable) trace.mark('firstSceneRenderEntered');
    super.renderViews(views, canvas, region: region, pixelRatio: pixelRatio);
    if (measurable) trace.mark('firstSceneRenderReturned');
  }
}
