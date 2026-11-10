/// Applies [curve] at [t] (0..1). Returns 0..1.
double applyCameraBlendCurve(CameraBlendCurve curve, double t) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return switch (curve) {
    CameraBlendCurve.linear => t,
    CameraBlendCurve.easeInOut => _easeInOutCubic(t),
    CameraBlendCurve.easeIn => t * t * t,
    CameraBlendCurve.easeOut => 1 - (1 - t) * (1 - t) * (1 - t),
  };
}

double _easeInOutCubic(double t) {
  return t < 0.5
      ? 4 * t * t * t
      : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;
}

/// Blend curve for camera transitions (pure enum, no Flutter Curve).
enum CameraBlendCurve { linear, easeInOut, easeIn, easeOut }
