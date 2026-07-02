// ignore_for_file: sort_constructors_first

/// Conditional export for ComponentMask based on platform.
/// Uses Uint64List for native platforms and Uint32List for web.
library;

export 'component_mask_base.dart';
export 'component_mask_native.dart'
    if (dart.library.html) 'component_mask_web.dart';
