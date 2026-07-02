// ignore_for_file: sort_constructors_first

import 'dart:typed_data';

import '../component.dart';
import 'component_mask_base.dart';

/// Bitmask representing a set of component types.
/// Native implementation using Uint64List for optimal performance.
///
/// Uses Uint64List for 256+ component support. Each Uint64 holds 64 bits,
/// so for 256 components we need 4 Uint64s (32 bytes total).
///
/// Provides O(1) component presence checks via bit operations.
class ComponentMaskImpl extends ComponentMaskBase {
  /// Create an empty mask with default capacity for 256 components
  ComponentMaskImpl({super.maxComponents})
    : super(
        /// Internal storage: each Uint64 holds 64 bits
        /// For 256 components, we need 4 Uint64s
        bits: Uint64List((maxComponents + 63) ~/ 64),
        factory: ({required final maxComponents}) =>
            ComponentMaskImpl(maxComponents: maxComponents),
      );

  /// Create mask with specific components set
  factory ComponentMaskImpl.fromIds(final Iterable<ComponentId> ids) {
    final mask = ComponentMaskImpl();
    ids.forEach(mask.set);
    return mask;
  }

  /// Empty mask constant
  static ComponentMask get empty => ComponentMaskImpl();

  @override
  int get wordSize => 64;
}
