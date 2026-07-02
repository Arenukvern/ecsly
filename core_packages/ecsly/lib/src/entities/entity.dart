import 'package:from_json_to_json/from_json_to_json.dart';

/// Constants for bit manipulation
const int _indexBase = 4294967296; // 2^32, avoids web-unsafe bitwise shifts.

/// {@template entity}
/// Represents an entity (temporary runtime pointer) in the game world.
/// Do not confuse with [PersistentEntity]
///
/// Unsafe to save, since it will be regenerated at the game start.
///
/// Contains generation and location information.
///
/// Entity is packed as a single 64-bit integer:
/// - Lower 32 bits: index
/// - Upper 32 bits: generation
///
/// To understand ECS better, refer to Bevy docs.
/// {@endtemplate}
extension type const Entity._(int value) {
  /// {@macro entity}
  /// Create Entity from index and generation parts
  factory Entity({
    final EntityIndex index = EntityIndex.zero,
    final EntityGeneration generation = EntityGeneration.zero,
  }) => Entity._(generation.value * _indexBase + index.value);

  factory Entity.create([final int index = 0, final int generation = 0]) =>
      Entity._(generation * _indexBase + (index % _indexBase));

  static const nullEntity = Entity._(0);

  /// Extract generation (upper 32 bits)
  EntityGeneration get generation => EntityGeneration._(value ~/ _indexBase);

  /// Get EntityIndex wrapper
  EntityIndex get index => EntityIndex(indexValue);

  /// Extract index (lower 32 bits)
  int get indexValue => value % _indexBase;

  bool get isNotNull => indexValue != 0 && generation != 0;

  bool get isNull => indexValue == 0 && generation == 0;
  bool get isZero => indexValue == 0;
  String entityToString() =>
      'Entity(index: $indexValue, generation: $generation)';

  String toJson() => '$indexValue-$generation';

  Entity whenNullUse(final Entity other) => isNull ? other : this;
}

/// {@template entity_generation}
/// Represents the generation of an entity (version counter for invalidation)
/// Incremented when entity is despawned to invalidate stale references
/// {@endtemplate}
extension type const EntityGeneration._(int value) implements int {
  static const zero = EntityGeneration._(0);

  /// The starting generation for all entities.
  static const initial = EntityGeneration._(0);

  bool get isNotZero => value > 0;
  bool get isZero => value == 0;

  EntityGeneration next() => EntityGeneration._(value + 1);
}

/// Index of entity for faster access in lists.
///
/// for example:
/// components[T][entityIndex]
extension type const EntityIndex(int value) implements int {
  factory EntityIndex.fromJson(final int json) =>
      EntityIndex(jsonDecodeInt(json));
  static const zero = EntityIndex(0);
  bool get isNotZero => value > 0;
}
