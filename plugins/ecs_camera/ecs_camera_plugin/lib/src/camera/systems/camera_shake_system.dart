import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';

import '../components/camera_components.dart';

/// Static Random instance for shake system (non-cryptographic use).
final _shakeRandom = math.Random();

/// Camera shake system - applies and decays shake effects.
///
/// Generates random shake offsets and applies decay over time.
/// Requires CameraShake component. Shake is applied to camera position
/// during rendering (via CameraPosition offset).
void cameraShakeSystem(final World world) {
  final dt = world.getResource<DeltaTimeResource>().deltaTime;

  for (final (_, shake)
      in world.queryExt<CameraShakeComponent, CameraShake>()) {
    if (!shake.hasShake) continue;

    // Apply decay
    final decayFactor = math.pow(shake.decay, dt).toDouble();
    shake.offsetX *= decayFactor;
    shake.offsetY *= decayFactor;

    // Add random noise for shake effect (reduces over time)
    final intensity =
        math.sqrt(
          shake.offsetX * shake.offsetX + shake.offsetY * shake.offsetY,
        ) *
        0.1;
    if (intensity > 0.01) {
      shake.offsetX += (_shakeRandom.nextDouble() - 0.5) * intensity * dt * 10;
      shake.offsetY += (_shakeRandom.nextDouble() - 0.5) * intensity * dt * 10;
    }

    // Reset very small shake values
    if (shake.offsetX.abs() < 0.01) shake.offsetX = 0.0;
    if (shake.offsetY.abs() < 0.01) shake.offsetY = 0.0;
  }
}
