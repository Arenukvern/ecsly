// ignore_for_file: sort_constructors_first

import 'dart:typed_data';

import '../component.dart';
import 'component_mask_base.dart';

/// Bitmask representing a set of component types.
/// Web implementation using Uint32List for compatibility.
///
/// Uses Uint32List for 256+ component support. Each Uint32 holds 32 bits,
/// so for 256 components we need 8 Uint32s (32 bytes total).
///
/// Provides O(1) component presence checks via bit operations.
class ComponentMaskImpl extends ComponentMaskBase {
  /// Create an empty mask with default capacity for 256 components
  ComponentMaskImpl({super.maxComponents})
    : super(
        /// Internal storage: each Uint32 holds 32 bits
        /// For 256 components, we need 8 Uint32s
        bits: Uint32List((maxComponents + 31) ~/ 32),
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
  int get wordSize => 32;
}
