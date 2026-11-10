import 'package:ecsly/ecsly.dart';

/// Visual highlight mode for selected entities.
enum HighlightMode {
  /// Outline around the entity
  outline,

  /// Colored overlay on the entity
  overlay,

  /// Both outline and overlay
  both,

  /// No visual highlight (data-only selection)
  none,
}

/// Component that provides visual feedback for entity selection.
///
/// **Q: Is SelectionHighlightComponent automatically added/removed when entities are selected?**
///
/// **A:** No. `SelectionHighlightComponent` is a **persistent configuration component** that should be added to entities at creation time. Rendering systems check `SelectionManager.isSelected(entity)` to determine whether to render the highlight. This design avoids archetype fragmentation from component lifecycle changes.
///
/// Defines how the selection should be visually represented (outline, overlay, etc.).
///
/// @ai Add this component when creating selectable entities. Rendering systems will automatically use it when the entity is selected via SelectionManager.
/// Use different [HighlightMode] values for different entity types.
///
/// Example:
/// ```dart
/// // Add component when creating entity (persistent)
/// entityWrapper.insert(SelectionHighlightComponent(
///   outlineColor: (255, 200, 0, 255),
///   outlineWidth: 3,
/// ));
///
/// // Rendering checks SelectionManager state
/// if (selectionManager.isSelected(entity)) {
///   // Use SelectionHighlightComponent config for rendering
/// }
/// ```
class SelectionHighlightComponent extends Component {
  SelectionHighlightComponent({
    this.mode = HighlightMode.outline,
    this.outlineColor = const (255, 100, 100, 255), // Red outline
    this.outlineWidth = 2.0,
    this.overlayColor = const (255, 100, 100, 50), // Semi-transparent red
  });

  /// How to visually highlight the selected entity
  final HighlightMode mode;

  /// Outline color as (r, g, b, a) tuple (0-255)
  final (int, int, int, int) outlineColor;

  /// Outline width in pixels
  final double outlineWidth;

  /// Overlay color as (r, g, b, a) tuple (0-255)
  final (int, int, int, int) overlayColor;

  /// Whether outline highlighting is enabled
  bool get showOutline =>
      mode == HighlightMode.outline || mode == HighlightMode.both;

  /// Whether overlay highlighting is enabled
  bool get showOverlay =>
      mode == HighlightMode.overlay || mode == HighlightMode.both;
}
