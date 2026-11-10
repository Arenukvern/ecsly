/// Gesture types recognized by the unified input system.
///
/// Each gesture type represents a specific user interaction pattern
/// that can be handled by interactive elements in the ECS world.
enum GestureType {
  /// No active gesture (pointer down but not yet classified)
  none,

  /// Single quick tap
  tap,

  /// Two quick taps in sequence
  doubleTap,

  /// Long press (pointer held down for extended period)
  longPress,

  /// Pointer dragged across screen
  drag,

  /// Two-finger pinch gesture (zoom/scale)
  pinch,

  /// Scroll wheel or multi-touch scroll gesture
  scroll,

  /// Secondary tap (right-click or secondary touch)
  secondaryTap,
}
