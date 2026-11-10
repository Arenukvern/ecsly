import 'package:ecsly/ecsly.dart';

/// Unified resource that manages both selection and dragging state for entities.
///
/// Provides a single source of truth for entity interaction state. Dragging is always
/// tied to selection - only selected entities can be dragged.
///
/// **Q: Why not store selection state as a `SelectedComponent` marker component?**
///
/// **A:** Avoids archetype fragmentation. If we used `SelectedComponent`:
/// - Selected entities → `[Position, Selectable, Selected]` archetype
/// - Unselected entities → `[Position, Selectable]` archetype
/// - Every selection change triggers archetype migration (expensive)
/// - `Set<Entity>` in Resource provides O(1) lookup without fragmentation
///
/// **Trade-off**: Requires manual cleanup of dead entities (addressed by cleanup system).
///
/// @ai Check this resource in selection and dragging systems.
/// Use [isSelected] and [isDragging] for quick entity checks.
class SelectionManager extends Resource {
  SelectionManager({this.mode = SelectionMode.single});

  /// Current selection mode
  SelectionMode mode;

  /// Currently selected entities (single mode: max 1, multi mode: unlimited)
  final Set<Entity> _selected = {};

  /// Set of entities currently being dragged (only selected entities can be dragged)
  final Set<Entity> _dragging = {};

  /// Count of active drag pointers (supports multi-touch scenarios)
  int activeDragPointers = 0;

  /// Whether any entities are currently selected
  bool get hasSelection => _selected.isNotEmpty;

  /// Whether any entities are currently being dragged
  bool get isAnyDragging => _dragging.isNotEmpty;

  /// All currently selected entities
  List<Entity> get selectedEntities => List.unmodifiable(_selected);

  /// The single selected entity (convenience getter for single mode)
  Entity? get selectedEntity => _selected.isNotEmpty ? _selected.first : null;

  /// Number of currently selected entities
  int get selectionCount => _selected.length;
}

extension SelectionManagerOps on SelectionManager {
  bool addToSelection(final Entity entity) =>
      selectionManagerAddToSelection(this, entity);

  void clearSelection() => selectionManagerClearSelection(this);

  void endDrag(final Entity entity) => selectionManagerEndDrag(this, entity);

  bool isDragging(final Entity entity) =>
      selectionManagerIsDragging(this, entity);

  bool isSelected(final Entity entity) =>
      selectionManagerIsSelected(this, entity);

  bool removeFromSelection(final Entity entity) =>
      selectionManagerRemoveFromSelection(this, entity);

  void removeInvalidEntities(final World world) =>
      selectionManagerRemoveInvalidEntities(this, world);

  void select(final Entity? entity) => selectionManagerSelect(this, entity);

  void selectMultiple(final List<Entity> entities) =>
      selectionManagerSelectMultiple(this, entities);

  void startDrag(final Entity entity) =>
      selectionManagerStartDrag(this, entity);

  bool toggleSelection(final Entity entity) =>
      selectionManagerToggleSelection(this, entity);
}

bool selectionManagerAddToSelection(
  final SelectionManager state,
  final Entity entity,
) {
  if (state.mode == SelectionMode.single) {
    if (state._selected.isEmpty || !state._selected.contains(entity)) {
      selectionManagerSelect(state, entity);
      return true;
    }
    return false;
  }
  return state._selected.add(entity);
}

void selectionManagerClearSelection(final SelectionManager state) {
  state._selected.clear();
}

void selectionManagerEndDrag(
  final SelectionManager state,
  final Entity entity,
) {
  state._dragging.remove(entity);
  state.activeDragPointers = state.activeDragPointers > 0
      ? state.activeDragPointers - 1
      : 0;
}

bool selectionManagerIsDragging(
  final SelectionManager state,
  final Entity entity,
) => state._dragging.contains(entity);

bool selectionManagerIsSelected(
  final SelectionManager state,
  final Entity entity,
) => state._selected.contains(entity);

bool selectionManagerRemoveFromSelection(
  final SelectionManager state,
  final Entity entity,
) => state._selected.remove(entity);

void selectionManagerRemoveInvalidEntities(
  final SelectionManager state,
  final World world,
) {
  state._selected.removeWhere(
    (final entity) => !world.entities.isAlive(entity),
  );
  state._dragging.removeWhere(
    (final entity) => !world.entities.isAlive(entity),
  );
}

void selectionManagerSelect(
  final SelectionManager state,
  final Entity? entity,
) {
  state._selected.clear();
  if (entity != null) {
    state._selected.add(entity);
  }
}

void selectionManagerSelectMultiple(
  final SelectionManager state,
  final List<Entity> entities,
) {
  if (state.mode == SelectionMode.single) {
    selectionManagerSelect(state, entities.first);
    return;
  }
  state._selected
    ..clear()
    ..addAll(entities);
}

void selectionManagerStartDrag(
  final SelectionManager state,
  final Entity entity,
) {
  if (!state._selected.contains(entity)) return;
  state._dragging.add(entity);
  state.activeDragPointers++;
}

bool selectionManagerToggleSelection(
  final SelectionManager state,
  final Entity entity,
) {
  if (state._selected.contains(entity)) {
    state._selected.remove(entity);
    return false;
  }
  return selectionManagerAddToSelection(state, entity);
}

/// Selection mode for entity selection behavior.
enum SelectionMode {
  /// Only one entity can be selected at a time
  single,

  /// Multiple entities can be selected simultaneously
  multi,
}
