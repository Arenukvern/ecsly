import 'dart:math' as math;

/// Canonical inspect camera presets for orbit-style 3D camera hosts.
enum InspectCameraPreset { front, back, left, right, top, iso, reset }

/// Resolved inspect camera pose.
class InspectCameraPose {
  const InspectCameraPose({
    required this.targetX,
    required this.targetY,
    required this.targetZ,
    required this.yawDeg,
    required this.pitchDeg,
    required this.distance,
  });

  final double targetX;
  final double targetY;
  final double targetZ;
  final double yawDeg;
  final double pitchDeg;
  final double distance;
}

const double _kIsoYawDeg = 45.0;
const double _kIsoPitchDeg = 35.264389682754654;
const double _kTopPitchDeg = 90.0;

/// Resolves a preset into a clamped inspect camera pose.
InspectCameraPose resolveInspectCameraPresetPose({
  required final InspectCameraPreset preset,
  required final double targetX,
  required final double targetY,
  required final double targetZ,
  final double distance = 12.0,
  final double minPitchDeg = -89.0,
  final double maxPitchDeg = 89.0,
  final double minDistance = 0.1,
  final double maxDistance = 1000.0,
}) {
  final pose = switch (preset) {
    InspectCameraPreset.front => (yawDeg: 0.0, pitchDeg: 0.0),
    InspectCameraPreset.back => (yawDeg: 180.0, pitchDeg: 0.0),
    InspectCameraPreset.left => (yawDeg: -90.0, pitchDeg: 0.0),
    InspectCameraPreset.right => (yawDeg: 90.0, pitchDeg: 0.0),
    InspectCameraPreset.top => (yawDeg: 0.0, pitchDeg: _kTopPitchDeg),
    InspectCameraPreset.iso => (yawDeg: _kIsoYawDeg, pitchDeg: _kIsoPitchDeg),
    InspectCameraPreset.reset => (yawDeg: 0.0, pitchDeg: 0.0),
  };

  return InspectCameraPose(
    targetX: targetX,
    targetY: targetY,
    targetZ: targetZ,
    yawDeg: pose.yawDeg,
    pitchDeg: _clampFinite(pose.pitchDeg, minPitchDeg, maxPitchDeg),
    distance: _clampFinite(distance, minDistance, maxDistance),
  );
}

double _clampFinite(final double value, final double min, final double max) {
  final bounded = value.isFinite ? value : min;
  return math.max(min, math.min(max, bounded));
}
