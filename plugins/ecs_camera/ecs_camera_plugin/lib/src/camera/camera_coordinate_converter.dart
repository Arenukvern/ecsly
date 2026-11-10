import 'dart:developer' as dev;
import 'dart:developer';
import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';

import 'camera_coordinate_utils.dart';
import 'components/camera_components.dart';
import 'resources/viewport_size_resource.dart';

/// Creates a camera-aware coordinate converter function for use with UnifiedInputWidget.
///
/// This function converts screen coordinates to world coordinates using the camera's
/// position and zoom. It accounts for camera transformations properly.
///
/// **Usage:**
/// ```dart
/// UnifiedInputWidget(
///   world: world,
///   toWorldCoords: createCameraToWorldConverter(world, cameraEntity),
///   child: GameLoopWidget(...),
/// )
/// ```
///
/// **Returns:** A function that converts screen coordinates to world coordinates.
/// If camera is not available or invalid, returns identity function (screen = world).
///
/// [world] ECS world containing the camera
/// [cameraEntity] Entity with CameraComponent and CameraPositionComponent
ui.Offset Function(ui.Offset screenPos, ui.Size viewportSize)
createCameraToWorldConverter(
  final World world,
  final Entity cameraEntity,
) => (final screenPos, final viewportSize) {
  try {
    final cameraExt = world.getEntityExtension(cameraEntity);
    if (!cameraExt.$2) return screenPos;

    final cameraPos = cameraExt.$1
        .getExtension<CameraPositionComponent, CameraPosition>();
    if (cameraPos == null) return screenPos;

    final (ext, valid) = world.getEntity(cameraEntity);
    if (!valid) return screenPos;

    final camera = ext.get<CameraComponent>();
    if (camera == null || !camera.isActive) return screenPos;

    // Prefer ViewportSizeResource if available (matches GameRenderer viewport)
    // Otherwise use the passed viewportSize parameter
    final effectiveViewportSize = world.resources.has<ViewportSizeResource>()
        ? world.getResource<ViewportSizeResource>().size
        : viewportSize;

    // Debug: Log viewport size mismatch if significant
    if (world.resources.has<ViewportSizeResource>()) {
      final resourceSize = world.getResource<ViewportSizeResource>().size;
      final sizeDiff =
          (resourceSize.width - viewportSize.width).abs() +
          (resourceSize.height - viewportSize.height).abs();
      if (sizeDiff > 1.0) {
        // Significant difference - this might cause coordinate mismatch
        // But don't print in production, just use the resource size
        dev.log('Viewport size mismatch: $sizeDiff');
      }
    }

    // Use proper camera coordinate conversion
    return CameraCoordinateUtils.screenToWorldFromComponent(
      screenPos,
      cameraPos,
      effectiveViewportSize,
    );
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    log('Error in createCameraToWorldConverter: $e');
    // Camera not available or error - return identity
    return screenPos;
  }
};

/// Creates a viewport size updater function for use with UnifiedInputWidget.
///
/// This function updates the ViewportSizeResource when viewport size changes.
/// It's type-safe and avoids dynamic resolution.
///
/// **Usage:**
/// ```dart
/// UnifiedInputWidget(
///   world: world,
///   onViewportSizeChanged: createViewportSizeUpdater(world),
///   child: GameLoopWidget(...),
/// )
/// ```
///
/// **Returns:** A function that updates ViewportSizeResource with new size.
/// If ViewportSizeResource doesn't exist, the function does nothing (no-op).
///
/// [world] ECS world containing ViewportSizeResource
void Function(ui.Size size) createViewportSizeUpdater(final World world) =>
    (final size) {
      // Update ViewportSizeResource with actual game viewport size
      // This ensures coordinate conversion uses the correct size
      if (world.resources.has<ViewportSizeResource>()) {
        final viewport = world.getResource<ViewportSizeResource>();
        viewport.update(size);
      } else {
        world.resources.push(
          ViewportSizeResource(width: size.width, height: size.height),
        );
      }
    };
