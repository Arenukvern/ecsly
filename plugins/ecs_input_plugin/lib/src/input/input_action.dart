/// Input action types that can be mapped to keys and gestures.
///
/// These actions represent the logical operations that can be triggered
/// by various input sources (keyboard, mouse, gestures, etc.).
enum InputAction {
  /// Move up (W, ArrowUp)
  moveUp,

  /// Move down (S, ArrowDown)
  moveDown,

  /// Move left (A, ArrowLeft)
  moveLeft,

  /// Move right (D, ArrowRight)
  moveRight,

  /// Jump (Space)
  jump,

  /// Interact (E)
  interact,

  /// Attack (Mouse Left, X)
  attack,

  /// Special ability (Q)
  special,

  /// Pause game (Escape)
  pause,

  /// Camera zoom in (Mouse Wheel Up, +)
  zoomIn,

  /// Camera zoom out (Mouse Wheel Down, -)
  zoomOut,

  /// Camera pan (Middle Mouse, Drag)
  cameraPan,

  /// Camera reset (R)
  cameraReset,
}
