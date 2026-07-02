import 'dart:developer';

import '../../entities/entities.dart';
import '../archetype.dart';
import '../archetype_signature.dart';
import '../archetypes_registry.dart';

/// Utilities for resolving archetypes from entities and signatures.
///
/// Eliminates duplicated lookup patterns across the codebase.
class ArchetypeResolver {
  ArchetypeResolver._();

  /// Resolves the current archetype for an entity.
  ///
  /// Performs the common pattern: getLocation → findArchetypeIndex → get archetype.
  /// Returns null if the entity's archetype cannot be found.
  static Archetype? resolveArchetype(
    final Entities entities,
    final ArchetypeRegistry registry,
    final Entity entity,
  ) {
    final location = entities.getLocation(entity);
    try {
      final archetypeIndex = registry.findArchetypeIndex(location.archetypeId);
      return registry[archetypeIndex];
      // ignore: avoid_catching_errors
    } on StateError {
      log('resolveArchetype: StateError', stackTrace: StackTrace.current);
      // ArchetypeId not found in registry
      return null;
      // ignore: avoid_catching_errors
    } on RangeError {
      log('resolveArchetype: RangeError', stackTrace: StackTrace.current);
      // ArchetypeIndex out of range
      return null;
    }
  }

  /// Resolves or creates a destination archetype for a given signature.
  ///
  /// Performs the common pattern: getOrCreateArchetype → findArchetypeIndex → get archetype.
  /// Always returns a valid archetype (creates if needed).
  static Archetype resolveDestinationArchetype(
    final ArchetypeRegistry registry,
    final ArchetypeSignature signature,
  ) {
    final archetypeId = registry.getOrCreateArchetype(signature);
    final archetypeIndex = registry.findArchetypeIndex(archetypeId);
    return registry[archetypeIndex];
  }
}
