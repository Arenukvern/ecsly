import 'dart:math' as math;

/// Converts a quaternion to yaw/pitch degrees for camera orbit controls.
({double yawDeg, double pitchDeg}) quaternionToYawPitchDegrees({
  required final double x,
  required final double y,
  required final double z,
  required final double w,
}) {
  final normalized = normalizeQuaternion(x: x, y: y, z: z, w: w);
  final forward = _rotateVectorByQuaternion(
    x: 0,
    y: 0,
    z: -1,
    qx: normalized.x,
    qy: normalized.y,
    qz: normalized.z,
    qw: normalized.w,
  );
  final yaw = -math.atan2(forward.x, -forward.z);
  final pitch = math.asin(forward.y.clamp(-1.0, 1.0));
  return (yawDeg: yaw * (180.0 / math.pi), pitchDeg: pitch * (180.0 / math.pi));
}

/// Converts yaw/pitch degrees to a normalized quaternion.
({double x, double y, double z, double w}) yawPitchDegreesToQuaternion({
  required final double yawDeg,
  required final double pitchDeg,
}) {
  final yaw = yawDeg * (math.pi / 180.0);
  final pitch = pitchDeg * (math.pi / 180.0);

  final cy = math.cos(yaw * 0.5);
  final sy = math.sin(yaw * 0.5);
  final cp = math.cos(pitch * 0.5);
  final sp = math.sin(pitch * 0.5);

  // q = yaw(Y) * pitch(X)
  final qx = cy * sp;
  final qy = sy * cp;
  final qz = -sy * sp;
  final qw = cy * cp;
  return normalizeQuaternion(x: qx, y: qy, z: qz, w: qw);
}

/// Returns a safe normalized quaternion, or identity when input is invalid.
({double x, double y, double z, double w}) normalizeQuaternion({
  required final double x,
  required final double y,
  required final double z,
  required final double w,
}) {
  if (!x.isFinite || !y.isFinite || !z.isFinite || !w.isFinite) {
    return (x: 0.0, y: 0.0, z: 0.0, w: 1.0);
  }
  final lengthSq = (x * x) + (y * y) + (z * z) + (w * w);
  if (!lengthSq.isFinite || lengthSq <= 1e-12) {
    return (x: 0.0, y: 0.0, z: 0.0, w: 1.0);
  }
  final invLength = 1.0 / math.sqrt(lengthSq);
  if (!invLength.isFinite) {
    return (x: 0.0, y: 0.0, z: 0.0, w: 1.0);
  }
  return (
    x: x * invLength,
    y: y * invLength,
    z: z * invLength,
    w: w * invLength,
  );
}

({double x, double y, double z}) _rotateVectorByQuaternion({
  required final double x,
  required final double y,
  required final double z,
  required final double qx,
  required final double qy,
  required final double qz,
  required final double qw,
}) {
  final tx = 2.0 * ((qy * z) - (qz * y));
  final ty = 2.0 * ((qz * x) - (qx * z));
  final tz = 2.0 * ((qx * y) - (qy * x));
  return (
    x: x + (qw * tx) + ((qy * tz) - (qz * ty)),
    y: y + (qw * ty) + ((qz * tx) - (qx * tz)),
    z: z + (qw * tz) + ((qx * ty) - (qy * tx)),
  );
}
