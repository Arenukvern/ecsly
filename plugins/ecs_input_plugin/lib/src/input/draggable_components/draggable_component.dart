import 'package:ecsly/ecsly.dart';

export 'hit_shape.dart';
export 'interactive_element.dart';
export 'selectable_component.dart';
export 'selection_highlight_component.dart';

/// Drag constraint modes for entity movement.
enum DragConstraint {
  /// Free movement in both X and Y directions
  free,

  /// Movement constrained to X axis only
  horizontal,

  /// Movement constrained to Y axis only
  vertical,

  /// Movement constrained to grid (snaps to grid points)
  grid,

  /// No dragging allowed (component still present for identification)
  disabled,
}

/// Component that defines drag behavior for entities.
///
/// Entities with this component can be dragged when selected in multi-mode.
/// The constraint system allows different movement behaviors like grid snapping
/// or axis constraints.
///
/// @ai Add this component to entities that should be draggable.
/// Use [DragConstraint.grid] for editor tools, [DragConstraint.free] for game objects.
class DraggableComponent extends Component {
  DraggableComponent({
    this.constraint = DragConstraint.free,
    this.dragSpeed = 1.0,
    this.gridSize = 16.0,
    this.snapToGrid = false,
  });

  /// Constraint determining how dragging behaves
  final DragConstraint constraint;

  /// Speed multiplier for drag movement (1.0 = direct 1:1 with cursor)
  final double dragSpeed;

  /// Grid size for grid-constrained movement (world units)
  final double gridSize;

  /// Whether to snap to grid points (alternative to DragConstraint.grid)
  final bool snapToGrid;

  /// Whether this entity can currently be dragged
  bool get canBeDragged => constraint != DragConstraint.disabled;

  /// Apply drag constraint to movement delta.
  ///
  /// [deltaX] Raw X movement delta
  /// [deltaY] Raw Y movement delta
  /// Returns constrained (x, y) deltas
  (double, double) constrainDelta(final double deltaX, final double deltaY) {
    final constrainedX = switch (constraint) {
      DragConstraint.vertical => 0.0,
      _ => deltaX * dragSpeed,
    };

    final constrainedY = switch (constraint) {
      DragConstraint.horizontal => 0.0,
      _ => deltaY * dragSpeed,
    };

    // Apply grid snapping if enabled
    if (constraint == DragConstraint.grid || snapToGrid) {
      return (
        (constrainedX / gridSize).round() * gridSize,
        (constrainedY / gridSize).round() * gridSize,
      );
    }

    return (constrainedX, constrainedY);
  }
}
