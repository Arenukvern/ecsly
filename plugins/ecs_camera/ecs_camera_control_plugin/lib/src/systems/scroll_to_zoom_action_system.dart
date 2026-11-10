import 'package:ecsly/ecsly.dart';
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

/// System that processes scroll events into input actions.
///
/// Converts ScrollEvent delta directions into zoom actions for camera control.
/// Alternative to direct scrollZoomSystem for applications using InputActionEvent pipeline.
void scrollToZoomActionSystem(final World world) {
  final stateTracker = world.getResource<InputStateTracker>();
  final writer = world.events.writer<InputActionEvent>();

  for (final scrollEvent in world.events.reader<ScrollEvent>().iter()) {
    // Check scroll direction: positive delta = zoom out, negative delta = zoom in
    final isZoomOut = scrollEvent.delta.dy > 0;
    final scrollAction = isZoomOut ? InputAction.zoomOut : InputAction.zoomIn;

    // Send pressed event (will be released by inputCleanupSystem.advance() at end of frame)
    writer.send(
      InputActionEvent(
        action: scrollAction,
        state: InputState.pressed,
        timestamp: scrollEvent.timestamp,
        value: scrollEvent.delta.dy.abs(), // Use magnitude for zoom speed
      ),
    );

    // Update state tracker for impulse (pressed then released)
    stateTracker.updateState(scrollAction, InputState.pressed);
  }
}
