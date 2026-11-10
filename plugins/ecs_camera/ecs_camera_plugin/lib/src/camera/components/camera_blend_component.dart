import 'package:ecsly/ecsly.dart';
import 'package:flutter/animation.dart';

import 'camera_target_components.dart';

/// Blends between two camera targets over time.
///
/// Provides smooth transitions when switching camera modes.
/// Automatically removes itself when the transition completes.
class CameraBlend extends Component {
  /// Creates a transition between two camera targets.
  CameraBlend({
    required this.fromTarget,
    required this.toTarget,
    required this.duration,
    this.curve = Curves.easeInOut,
  });

  /// Source target (where transition starts)
  final CameraTarget fromTarget;

  /// Destination target (where transition ends)
  final CameraTarget toTarget;

  /// Duration of the transition
  final Duration duration;

  /// Animation curve for the transition
  final Curve curve;

  /// Current progress (0 to 1.0)
  double progress = 0;

  /// Whether the blend transition is complete
  bool get isComplete => progress >= 1.0;
}
