// ignore_for_file: sort_constructors_first, cascade_invocations

import 'package:meta/meta.dart';

import '../components/component.dart';
import '../components/component_mask/component_mask.dart';

/// Archetype signature represented as a bitmask.
///
/// Provides O(1) component presence checks via bitmask operations.
/// This replaces Type-based ComponentSignature for better performance.
@immutable
class ArchetypeSignature {
  /// Create signature from a ComponentMask
  const ArchetypeSignature(this.mask);

  /// Create signature from component IDs
  factory ArchetypeSignature.fromIds(final Iterable<ComponentId> ids) =>
      ArchetypeSignature(createComponentMask(ids));

  /// Empty signature (no components)
  static final empty = ArchetypeSignature(emptyComponentMask);

  /// The component mask representing this signature
  final ComponentMask mask;

  @override
  int get hashCode => mask.hashCode;

  @override
  bool operator ==(final Object other) =>
      other is ArchetypeSignature && mask == other.mask;

  /// Add component to signature (creates new signature)
  ArchetypeSignature add(final ComponentId id) {
    final newMask = mask.copy();
    newMask.set(id);
    return ArchetypeSignature(newMask);
  }

  /// Add multiple components to signature (creates new signature)
  ArchetypeSignature addMultiple(final Iterable<ComponentId> ids) {
    final newMask = mask.copy();
    ids.forEach(newMask.set);
    return ArchetypeSignature(newMask);
  }

  /// Check if signature contains component
  bool has(final ComponentId id) => mask.has(id);

  /// Check if signature contains all components in query mask
  bool matches(final ComponentMask queryMask) => mask.contains(queryMask);

  /// Remove component from signature (creates new signature)
  ArchetypeSignature remove(final ComponentId id) {
    final newMask = mask.copy();
    newMask.clear(id);
    return ArchetypeSignature(newMask);
  }

  @override
  String toString() => 'ArchetypeSignature($mask)';
}
