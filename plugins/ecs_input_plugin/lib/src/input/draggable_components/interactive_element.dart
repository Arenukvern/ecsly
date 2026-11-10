/// Component that marks an ECS entity as interactive and defines its input behavior.
///
/// Interactive elements define hit test areas, priority ordering, and which
/// gesture types they can handle. The unified input system uses this component
/// to determine which entities should receive gesture events.
///
/// Priority determines handling order - higher priority elements are checked
/// first and can block lower priority elements if they consume the gesture.
library;

import 'package:ecsly/ecsly.dart';

import '../utils/gesture_types.dart';
import 'hit_shape.dart';

class InteractiveElement extends Component {
  /// Creates an interactive element with the specified properties.
  InteractiveElement({
    required this.priority,
    this.blocksPropagation = true,
    required this.hitShape,
    this.supportedGestures = const {
      GestureType.tap,
      GestureType.drag,
      GestureType.longPress,
    },
  });

  /// Hit shape configuration.
  ///
  /// Defines the area around the entity's position that responds to input.
  final HitShape hitShape;

  /// Priority for input handling order.
  ///
  /// Higher values are handled first. Use constants like kPriorityUI, kPriorityCamera.
  final int priority;

  /// Whether this element blocks gesture propagation to lower priority elements.
  ///
  /// If true, consuming a gesture prevents lower priority elements from handling it.
  final bool blocksPropagation;

  /// Set of gesture types this element can handle.
  ///
  /// Only gestures in this set will be dispatched to this element.
  /// Use GestureType.none to handle all gestures.
  final Set<GestureType> supportedGestures;
}
