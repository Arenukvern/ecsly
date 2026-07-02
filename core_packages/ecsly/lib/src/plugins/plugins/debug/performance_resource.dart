import '../../../resources/resource.dart';

/// Resource tracking FPS, frame time, and entity count.
///
/// Updated each frame by [performanceSystem] to provide
/// rolling average FPS over the last 60 frames.
class PerformanceResource extends Resource {
  PerformanceResource({
    required this.fps,
    required this.frameTime,
    required this.entityCount,
    final List<double>? frameTimeSamples,
  }) : frameTimeSamples = frameTimeSamples ?? [];

  static const int maxSamples = 60; // Rolling average over 60 frames
  double fps;
  double frameTime;
  int entityCount;

  final List<double> frameTimeSamples;

  void update(final double dt, final int currentEntityCount) {
    final newFrameTime = dt * 1000; // Convert to milliseconds
    frameTimeSamples.add(newFrameTime);

    // Keep only the last maxSamples
    if (frameTimeSamples.length > maxSamples) {
      frameTimeSamples.removeAt(0);
    }

    // Calculate rolling average FPS
    final avgFrameTime = frameTimeSamples.isNotEmpty
        ? frameTimeSamples.reduce((final a, final b) => a + b) /
              frameTimeSamples.length
        : newFrameTime;

    frameTime = newFrameTime;
    fps = avgFrameTime > 0 ? 1000.0 / avgFrameTime : 0.0;
    entityCount = currentEntityCount;
  }
}
