import '../../components/component.dart';
import '../../components/component_mask/component_mask.dart';
import '../archetype.dart';
import '../archetype_signature.dart';

/// Utilities for computing new archetype signatures.
///
/// Centralizes signature mutation logic for adding/removing components.
class SignatureComputer {
  SignatureComputer._();

  static final _bufferPool = _SignatureMaskBufferPool();

  /// Computes a new signature by adding a component to an archetype's signature.
  ///
  /// Returns a new signature with the component added.
  static ArchetypeSignature computeAddSignature(
    final Archetype archetype,
    final ComponentId componentId,
  ) => archetype.signature.add(componentId);

  /// Computes a new signature by adding multiple components to an archetype's signature.
  ///
  /// Returns a new signature with all components added.
  static ArchetypeSignature computeAddSignatureMultiple(
    final Archetype archetype,
    final List<ComponentId> componentIds,
  ) {
    if (componentIds.isEmpty) {
      return archetype.signature;
    }
    final baseMask = archetype.signature.mask;
    final additionsMask = _bufferPool.acquireLike(baseMask);
    try {
      componentIds.forEach(additionsMask.set);
      return ArchetypeSignature(baseMask.union(additionsMask));
    } finally {
      _bufferPool.release(additionsMask);
    }
  }

  /// Computes a new signature by removing multiple components.
  ///
  /// Uses pooled temporary masks to avoid allocating a remove-mask each call.
  static ArchetypeSignature computeRemoveSignatureMultiple(
    final Archetype archetype,
    final List<ComponentId> componentIds,
  ) {
    if (componentIds.isEmpty) {
      return archetype.signature;
    }
    final baseMask = archetype.signature.mask;
    final removalsMask = _bufferPool.acquireLike(baseMask);
    try {
      componentIds.forEach(removalsMask.set);
      final result = baseMask.copy();
      for (var i = 0; i < result.length; i++) {
        result.setWord(i, result.getWord(i) & ~removalsMask.getWord(i));
      }
      return ArchetypeSignature(result);
    } finally {
      _bufferPool.release(removalsMask);
    }
  }

  /// Computes a new signature by removing a component from an archetype's signature.
  ///
  /// Returns a new signature with the component removed.
  static ArchetypeSignature computeRemoveSignature(
    final Archetype archetype,
    final ComponentId componentId,
  ) => archetype.signature.remove(componentId);
}

final class _SignatureMaskBufferPool {
  final Map<int, List<ComponentMask>> _freeByLength = {};

  ComponentMask acquireLike(final ComponentMask source) {
    final length = source.length;
    final bucket = _freeByLength[length];
    if (bucket != null && bucket.isNotEmpty) {
      return bucket.removeLast();
    }
    final fresh = source.copy();
    _clearWords(fresh);
    return fresh;
  }

  void release(final ComponentMask mask) {
    _clearWords(mask);
    _freeByLength.putIfAbsent(mask.length, () => []).add(mask);
  }

  void _clearWords(final ComponentMask mask) {
    for (var i = 0; i < mask.length; i++) {
      mask.setWord(i, 0);
    }
  }
}
