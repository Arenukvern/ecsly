// ignore_for_file: cascade_invocations

import '../../../resources/resources/resources.dart';
import '../../../world/world.dart';
import 'performance_resource.dart';

/// Performance monitoring system: Track FPS and entity count.
///
/// Updates [PerformanceResource] each frame with current FPS
/// (rolling average over 60 frames) and entity count.
void performanceSystem(final World world) {
  final dt = world.getResource<DeltaTimeResource>().deltaTime;
  final entityCount = world.entities.count;
  final performance = world.getResource<PerformanceResource>();
  performance.update(dt, entityCount);
  // Direct mutation - no push needed
}
