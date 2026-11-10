part of 'camera.dart';

/// Camera adapter that reads from ECS camera entity.
/// Integrates ECS camera component system with Camera interface for rendering.
class EcsCamera extends Camera {
  /// Creates an ECS-backed camera adapter.
  EcsCamera({required this.world, final Entity? cameraEntity})
    : _cachedCamera = cameraEntity;

  /// The world instance to read from.
  final World world;

  /// Cache for performance
  Entity? _cachedCamera;

  /// The cached camera entity. If null, queries for active camera.
  Entity get cameraEntity =>
      _cachedCamera ??= _getCamera(); // If null, queries for active camera

  @override
  double get zoom {
    final maybePos = _getCameraPosition();
    if (maybePos == null) return 1;
    return maybePos.$2.zoom;
  }

  @override
  ui.Rect getViewBounds(final ui.Size viewport) {
    final maybePos = _getCameraPosition();
    if (maybePos == null) return ui.Rect.zero;
    final (entity, pos) = maybePos;

    final (ext, valid) = world.getEntity(entity);
    if (!valid) return ui.Rect.zero;

    final cameraComponent = ext.get<CameraComponent>();
    final padding = cameraComponent?.cullingPadding ?? 100.0;

    // Scale viewport size by inverse zoom (zoomed in = smaller bounds, zoomed out = larger bounds)
    final scaledW = viewport.width / pos.zoom;
    final scaledH = viewport.height / pos.zoom;

    return ui.Rect.fromLTWH(
      pos.x - scaledW / 2 - padding,
      pos.y - scaledH / 2 - padding,
      scaledW + padding * 2,
      scaledH + padding * 2,
    );
  }

  @override
  ui.Offset getViewportCenter() {
    final maybePos = _getCameraPosition();
    if (maybePos == null) return ui.Offset.zero;
    final (entity, pos) = maybePos;
    if (pos == null) return ui.Offset.zero;
    return ui.Offset(pos.x, pos.y);
  }

  @override
  @Deprecated('Use SceneCamera + GPU pipeline instead of Canvas rendering.')
  void transformCanvas(final ui.Canvas canvas, final ui.Size viewport) {
    final maybePos = _getCameraPosition();
    if (maybePos == null) return;
    final (entity, pos) = maybePos;
    if (pos == null) return;

    // Get shake offset if available
    final shake = _getCameraShake();
    final shakeX = shake?.offsetX ?? 0.0;
    final shakeY = shake?.offsetY ?? 0.0;

    // Apply zoom scaling centered on camera position
    canvas.scale(pos.zoom);
    // Transform so that camera position appears at screen center
    // Apply shake offset for screen shake effect
    canvas.translate(
      -pos.x - shakeX + (viewport.width / 2) / pos.zoom,
      -pos.y - shakeY + (viewport.height / 2) / pos.zoom,
    );
  }

  Entity _getCamera() {
    final cachedCamera = _cachedCamera;
    if (cachedCamera != null) {
      // Validate cached camera if it exists
      final (ext, valid) = world.getEntity(cachedCamera);
      if (!valid) {
        _cachedCamera = null; // Invalidate stale cache
      } else {
        final cameraComponent = ext.get<CameraComponent>();
        if (cameraComponent?.isActive != true) {
          _cachedCamera = null; // Invalidate if camera is no longer active
        }
      }
    }

    // Query for active camera if cache is invalid
    _cachedCamera ??= world
        .query<CameraComponent>()
        .where((final r) => r.$2.isActive)
        .firstOrNull
        ?.$1
        .entity;

    if (_cachedCamera == null) {
      throw StateError('No active camera found in world');
    }

    return _cachedCamera!;
  }

  (Entity, CameraPosition)? _getCameraPosition() {
    final entity = _getCamera();
    final (ext, valid) = world.getEntityExtension(entity);
    if (!valid) return null;
    final pos = ext.getExtension<CameraPositionComponent, CameraPosition>();

    if (pos == null) return null;
    return (entity, pos);
  }

  CameraShake? _getCameraShake() {
    final entity = _getCamera();
    final (ext, valid) = world.getEntityExtension(entity);
    if (!valid) return null;
    return ext.getExtension<CameraShakeComponent, CameraShake>();
  }
}
