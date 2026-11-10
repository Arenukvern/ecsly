import 'package:ecsly/ecsly.dart';

/// Component that marks entities as selectable and defines selection behavior.
///
/// Entities with this component can be selected via tap gestures in selection mode.
/// The constraint system allows fine-grained control over when entities can be selected.
///
/// @ai Add this component to entities that should respond to selection gestures.
/// Use [SelectionConstraint.zoomDependent] for entities that should only be selectable
/// at high zoom levels (e.g., small UI elements).
class SelectableComponent extends Component {
  SelectableComponent({
    this.constraint = SelectionConstraint.normal,
    this.minZoomForSelection = 1.0,
  });

  /// Constraint determining when this entity can be selected
  final SelectionConstraint constraint;

  /// Minimum zoom level required for selection (only used with zoomDependent constraint)
  final double minZoomForSelection;

  /// Whether this entity can currently be selected based on current state.
  ///
  /// [currentZoom] Current camera zoom level
  bool canBeSelected(final double currentZoom) => switch (constraint) {
    SelectionConstraint.disabled => false,
    SelectionConstraint.normal => true,
    SelectionConstraint.zoomDependent => currentZoom >= minZoomForSelection,
  };
}

/// Constraints for entity selection behavior.
enum SelectionConstraint {
  /// Entity can be selected normally
  normal,

  /// Entity selection is disabled
  disabled,

  /// Entity can only be selected when zoomed in beyond threshold
  zoomDependent,
}
