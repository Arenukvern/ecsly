/// A complete save/load cycle for an ecsly world, demonstrating
/// `ecsly_serialization` end to end.
///
/// Run with: `dart run example/main.dart`
///
/// The story: you have a small game world with three persisted enemies and a
/// game-config resource. You play a bit (mutate positions), save to JSON,
/// then "relaunch the game" — a brand-new, completely empty world — and
/// restore. Runtime entity handles are never serialized; stable identity
/// travels in the [PersistentId] component.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

/// SoA component: position lives in a packed `FloatColumn` (x, y).
class PositionComponent extends Component {
  const PositionComponent();
}

extension type Position._(int index) {
  static late FloatColumn _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap
  static void _setTypedColumn(final FloatColumn column) {
    _column = column;
  }

  double get x => _column.getValueUnsafe(index, 0);
  double get y => _column.getValueUnsafe(index, 1);
  set x(final double value) => _column.setValue(index, 0, value);
  set y(final double value) => _column.setValue(index, 1, value);
}

final class _PositionColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => FloatColumn(stride: 2, initialCapacity: initialCapacity);
}

final class _PositionFacadeFactory extends ComponentFacadeFactory<Position> {
  @override
  Position create(final int index) => Position._(index);

  @override
  void initialize(final DataColumn column) {
    Position._setTypedColumn(column as FloatColumn);
  }
}

/// SoA component: health lives in a compact `Uint8Column`.
class HealthComponent extends Component {
  const HealthComponent();
}

extension type Health._(int index) {
  static late Uint8Column _column;

  // ignore: use_setters_to_change_properties - internal column bootstrap
  static void _setTypedColumn(final Uint8Column column) {
    _column = column;
  }

  int get value => _column.getValue(index);
  set value(final int v) => _column.setValue(index, v);
}

final class _HealthColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => Uint8Column(initialCapacity: initialCapacity);
}

final class _HealthFacadeFactory extends ComponentFacadeFactory<Health> {
  @override
  Health create(final int index) => Health._(index);

  @override
  void initialize(final DataColumn column) {
    Health._setTypedColumn(column as Uint8Column);
  }
}

/// Object-tier component: cold data that benefits from heap storage.
///
/// Restore needs a [sample] instance because Dart has no runtime reflection —
/// the sample is the component-side mirror of the event-side `sampleEvent`
/// pattern. Serializing its *values* additionally requires a codec (below).
class InventoryComponent extends Component {
  const InventoryComponent(this.items);

  const InventoryComponent.empty() : items = const [];

  final List<String> items;
}

/// Codec that teaches the snapshot how to serialize [InventoryComponent]
/// values. Keys are component type names, matching how snapshots identify
/// components.
class InventoryCodec extends ObjectComponentCodec<InventoryComponent> {
  const InventoryCodec();

  @override
  Object? toJson(final InventoryComponent component) => component.items;

  @override
  InventoryComponent fromJson(final Object? value) => InventoryComponent(
    ((value as List<Object?>?) ?? const []).whereType<String>().toList(
      growable: false,
    ),
  );
}

/// Resource: game-level configuration, captured via [SnapshotableResource].
class GameConfig extends Resource with SnapshotableResource {
  GameConfig({this.difficulty = 1.0});

  final double difficulty;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'difficulty': difficulty};

  // ignore: prefer_constructors_over_static_methods
  static GameConfig fromJson(final Map<String, Object?> json) =>
      GameConfig(difficulty: (json['difficulty'] as num?)?.toDouble() ?? 1.0);
}

// ---------------------------------------------------------------------------
// World setup
// ---------------------------------------------------------------------------

World buildGameWorld() {
  final world = World();
  registerPersistentId(world);
  world.components.registerExtension<PositionComponent, Position>(
    columnFactory: _PositionColumnFactory(),
    facadeFactory: _PositionFacadeFactory(),
  );
  world.components.registerExtension<HealthComponent, Health>(
    columnFactory: _HealthColumnFactory(),
    facadeFactory: _HealthFacadeFactory(),
  );
  world.components.registerObjectComponent<InventoryComponent>(
    sample: const InventoryComponent.empty(),
  );
  return world;
}

/// Spawns the game's persistent entities. Each carries a [PersistentId] —
/// the stable cross-session identity. Entities without one (particles, VFX)
/// would simply not be captured.
void spawnEnemies(final World world) {
  for (var i = 1; i <= 3; i++) {
    world.spawnComponents([
      PersistentId(i),
      const PositionComponent(),
      const HealthComponent(),
      InventoryComponent(['potion_$i']),
    ]);
  }
  world.upsertResource(GameConfig(difficulty: 1.5));
  world.flush();
}

/// Simulates gameplay: move each enemy and damage the odd-numbered ones.
void play(final World world) {
  final random = math.Random(7);
  for (final archetype in world.archetypes.all) {
    for (final entity in archetype.entities) {
      final pid = persistentIdOf(world, entity)?.value;
      if (pid == null) continue; // not persisted — skip
      final (ext, ok) = world.getEntityExtension(entity);
      if (!ok) continue;
      ext.getOrCreate<PositionComponent, Position>()
        ..x = random.nextDouble() * 100
        ..y = random.nextDouble() * 100;
      if (pid.isOdd) {
        ext.getOrCreate<HealthComponent, Health>().value = 40 + pid;
      }
    }
  }
}

void main() {
  // Codecs are passed via capture/restore options so both sides agree on how
  // object-tier component values are serialized.
  final codecs = ObjectComponentCodecRegistry()
    ..register(const InventoryCodec());
  final options = WorldSnapshotOptions(codecs: codecs);

  // --- Session 1: build, play, save. -------------------------------------
  final session1 = buildGameWorld();
  spawnEnemies(session1);
  play(session1);

  final saveFile = File('save.json');
  saveFile.writeAsStringSync(
    encodeWorldSnapshot(captureWorldSnapshot(session1, options: options)),
  );
  stdout.writeln(
    'Saved ${saveFile.path} '
    '(${saveFile.lengthSync()} bytes, 3 entities)',
  );

  // --- Session 2: relaunch into a completely empty world. ----------------
  final session2 = buildGameWorld(); // zero live entities
  final snapshot = decodeWorldSnapshot(saveFile.readAsStringSync());
  final mapping = restoreWorldSnapshot(
    session2,
    snapshot,
    options: options,
    resourceFactories: <String, SnapshotResourceFactory>{
      'GameConfig': GameConfig.fromJson,
    },
  );

  stdout.writeln('Restored ${mapping.length} entities into an empty world:');
  for (final MapEntry(key: pid, value: entity) in mapping.entries) {
    final (ext, ok) = session2.getEntityExtension(entity);
    if (!ok) continue;
    final position = ext.getOrCreate<PositionComponent, Position>();
    final health = ext.getOrCreate<HealthComponent, Health>();
    final inventory = session2.getEntity(entity).$1.get<InventoryComponent>();
    stdout.writeln(
      '  enemy $pid: pos=(${position.x.toStringAsFixed(1)}, '
      '${position.y.toStringAsFixed(1)}) health=${health.value} '
      'items=${inventory?.items}',
    );
  }

  final config = session2.resources.getByType(GameConfig)! as GameConfig;
  stdout.writeln('difficulty=${config.difficulty}');

  // --- Idempotency: re-applying the same save changes nothing. -----------
  restoreWorldSnapshot(session2, snapshot);
  stdout.writeln('Re-applied save: still ${session2.entities.count} entities.');

  saveFile.deleteSync();
}
