import 'dart:convert';

import 'world_snapshot.dart';

/// A forward-only migration step applied to a snapshot's raw JSON.
///
/// Migrations run *before* decoding, operating on the JSON map directly. This
/// keeps them format-agnostic and lets them rename keys, transform values, or
/// restructure entities without touching Dart snapshot classes.
///
/// DB analogy: this is a Flyway/Rails-style ordered migration chain. Each
/// step upgrades saves from `fromVersion` to `fromVersion + 1`. Automatic
/// inference of renames or transforms is deliberately not attempted — only
/// the app knows what its data means.
abstract class SnapshotMigration {
  /// Creates a migration step.
  const SnapshotMigration();

  /// The schema version this migration upgrades *from*.
  int get fromVersion;

  /// Apply the migration to the raw snapshot [json] in place (or return a
  /// new map).
  Map<String, Object?> migrate(final Map<String, Object?> json);
}

/// Convenience migration that renames a component key across all entities.
///
/// Covers the common "I renamed my Position class" case where the type name
/// in the snapshot's component table no longer matches the target world.
class RenameComponentMigration extends SnapshotMigration {
  /// Creates a rename migration upgrading from [fromVersion].
  const RenameComponentMigration({
    required this.fromVersion,
    required this.oldName,
    required this.newName,
  });

  @override
  final int fromVersion;

  /// Component type name as stored in old snapshots.
  final String oldName;

  /// Component type name as registered in the current world.
  final String newName;

  @override
  Map<String, Object?> migrate(final Map<String, Object?> json) {
    final componentIds = (json['componentIds'] as Map?)
        ?.cast<String, Object?>();
    if (componentIds == null || !componentIds.containsKey(oldName)) {
      return json;
    }
    final idValue = componentIds.remove(oldName);
    componentIds[newName] = idValue;
    return json;
  }
}

/// Applies an ordered [migrations] chain to bring a decoded snapshot's
/// `schemaVersion` up to [targetVersion].
///
/// Throws [StateError] when a required step is missing — loud failure beats
/// silent drift.
WorldSnapshot decodeAndMigrateWorldSnapshot(
  final String json,
  final List<SnapshotMigration> migrations, {
  final int targetVersion = 1,
}) {
  var raw = jsonDecode(json) as Map<String, Object?>;
  var current = (raw['schemaVersion'] as num?)?.toInt() ?? 1;

  while (current < targetVersion) {
    final step = _findStep(migrations, current);
    if (step == null) {
      throw StateError(
        'No snapshot migration for schemaVersion $current '
        '(target $targetVersion). Add a migration step or raise '
        '`schemaVersion` handling in your loader.',
      );
    }
    raw = step.migrate(raw);
    current++;
  }

  return WorldSnapshot.fromJson(raw);
}

SnapshotMigration? _findStep(
  final List<SnapshotMigration> migrations,
  final int fromVersion,
) {
  for (final migration in migrations) {
    if (migration.fromVersion == fromVersion) return migration;
  }
  return null;
}
