import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:ecsly_world_sync/ecsly_world_sync.dart';
import 'package:meta/meta.dart';

/// Binds one live [World] to one [WorldSync] (ecsly ADR 0002).
///
/// The bridge closes the gap ADR 0001 deferred: core ecsly has change
/// detection only for structure ([World.structuralRevision]), never for
/// component data, so the bridge derives deltas by **capture diffing** —
/// each [emitDeltas] run captures a `ecsly_serialization`
/// [WorldSnapshot] and diffs it against the previous capture.
///
/// Key/value mapping (derived from the capture format in
/// `ecsly_serialization`'s `column_entity_snapshot.dart`):
///
/// - `entityKey` = `PersistentId.value` in string form. Runtime `Entity`
///   handles never appear in keys — the same identity model as snapshots.
/// - `component` = component **type name** (the snapshot's stable identity
///   layer), resolved by reverse-mapping the world-local column id prefix
///   through `WorldSnapshot.componentIds`. The same component type maps to
///   the same sync key on every replica even though `ComponentId`s differ
///   per world.
/// - `field` = the column offset (`'0'`, `'1'`, …) for SoA columns, or
///   `'obj'` for codec-captured object components.
/// - `value` = the raw captured column value (num), or, for object
///   components, the lossless `{'type', 'value'}` codec map. Values are
///   JSON-encodable; [WorldSync] JSON-encodes them into kernel ops.
///
/// Spawn and despawn are *not* special-cased: structure syncs as keyed
/// state. A spawn shows up as new keys (deltas), a despawn or component
/// removal as vanished keys ([WorldSync.removeDelta] tombstones). A
/// [PersistentId]-tagged entity with zero captured columns (no SoA fields,
/// no codec'd objects) is invisible to the bridge — capture skips it.
///
/// Cost, stated honestly: every [emitDeltas] runs a full world capture plus
/// a full key diff. `World.structuralRevision` cannot gate this — it bumps
/// only on structural changes, so skipping the diff on an unchanged
/// revision would silently drop data-only writes. There is no per-component
/// mutation hook in core ecsly to subscribe to instead. If this becomes hot,
/// the fix is change detection in core ecsly, not a heuristic here.
///
/// Liveness: attach [flushObserver] (or call [attach]) so every
/// [World.flush] boundary emits deltas. `World` exposes a single observer
/// slot, so the bridge chains any previously registered observer and
/// restores it on [detach]. Re-entrant emission (capture calls
/// `world.flush()` internally) is guarded and returns 0.
final class WorldSyncBridge {
  /// Creates a bridge from live [world] to replica [sync].
  ///
  /// [codecs], when given, is forwarded to the capture so object-tier
  /// components are included as `'obj'` fields. [clock] defaults to
  /// [DateTime.now] and exists so tests can drive deterministic HLCs.
  WorldSyncBridge({
    required this.world,
    required this.sync,
    final ObjectComponentCodecRegistry? codecs,
    final DateTime Function()? clock,
  }) : _captureOptions = WorldSnapshotOptions(codecs: codecs),
       _now = clock ?? DateTime.now;

  /// The live world this bridge captures.
  final World world;

  /// The replica this bridge feeds deltas (and tombstones) into.
  final WorldSync sync;

  final WorldSnapshotOptions _captureOptions;
  final DateTime Function() _now;

  /// Sync key → last emitted key parts and value (previous capture).
  final Map<String, _EmittedKey> _lastEmitted = {};

  bool _emitting = false;
  bool _attached = false;
  WorldFlushObserver? _previousObserver;
  _BridgeFlushObserver? _observer;

  /// Whether [attach] currently owns [World.flushObserver].
  bool get isAttached => _attached;

  /// Emits one op per changed key into [sync]; returns the op count.
  ///
  /// New/changed values become [WorldSync.applyDelta] ops; keys present in
  /// the previous capture but absent now become [WorldSync.removeDelta]
  /// tombstones (entity despawn and component removal included). Returns 0
  /// when nothing changed — repeated calls with an unchanged world are
  /// free of ops (idempotent), though not free of capture cost.
  int emitDeltas() => _emit();

  /// Flush-boundary liveness: an observer whose [WorldFlushObserver.onFlushEnd]
  /// calls [emitDeltas]. Register via [attach] (which chains and restores
  /// any observer already in [World.flushObserver]) or assign it yourself.
  WorldFlushObserver get flushObserver =>
      _observer ??= _BridgeFlushObserver(this);

  /// Sets [flushObserver] as the world's flush observer, chaining (and
  /// later restoring, on [detach]) whatever observer was there before.
  void attach() {
    if (_attached) return;
    _previousObserver = world.flushObserver;
    world.flushObserver = flushObserver;
    _attached = true;
  }

  /// Restores the observer [attach] displaced. No-op when not attached or
  /// when the world's observer slot has been reassigned since.
  void detach() {
    if (!_attached) return;
    if (identical(world.flushObserver, _observer)) {
      world.flushObserver = _previousObserver;
    }
    _previousObserver = null;
    _attached = false;
  }

  int _emit() {
    // Re-entrancy guard: captureWorldSnapshot flushes the world, which (when
    // attached) re-enters through onFlushEnd. The inner run must be a no-op.
    if (_emitting) return 0;
    _emitting = true;
    try {
      final snapshot = captureWorldSnapshot(world, options: _captureOptions);
      return _diffAndEmit(snapshot);
    } finally {
      _emitting = false;
    }
  }

  int _diffAndEmit(final WorldSnapshot snapshot) {
    final now = _now();
    final persistentIdId = world.components
        .getComponentIdByType(PersistentId)
        ?.value;
    // componentIds: type name → source-world id value. Invert it so column
    // keys (`{id}_{offset}` / `obj_{id}`) resolve back to stable type names.
    final typeNameById = <int, String>{
      for (final entry in snapshot.componentIds.entries)
        entry.value: entry.key,
    };

    var emitted = 0;
    final current = <String, _EmittedKey>{};
    for (final entity in snapshot.entities) {
      final entityKey = '${entity.persistentId}';
      for (final entry in entity.columns.entries) {
        final parsed = _parseColumnKey(entry.key, typeNameById);
        if (parsed == null) continue;
        final (component, field, columnId) = parsed;
        if (columnId == persistentIdId) {
          continue; // identity rides the key; never synced as data
        }
        final value = entry.value;
        final syncKey = '$entityKey/$component/$field';
        current[syncKey] = _EmittedKey(entityKey, component, field, value);
        final previous = _lastEmitted[syncKey];
        if (previous != null && _deepEquals(previous.value, value)) {
          continue;
        }
        sync.applyDelta(
          ComponentDelta(
            entityKey: entityKey,
            component: component,
            field: field,
            value: value,
          ),
          now,
        );
        emitted++;
      }
    }

    // Vanished keys → tombstones: despawned entities and removed components
    // both surface here, uniformly.
    for (final entry in _lastEmitted.entries) {
      if (current.containsKey(entry.key)) continue;
      final key = entry.value;
      sync.removeDelta(
        ComponentDelta(
          entityKey: key.entityKey,
          component: key.component,
          field: key.field,
          value: null,
        ),
        now,
      );
      emitted++;
    }

    _lastEmitted
      ..clear()
      ..addAll(current);
    return emitted;
  }
}

/// One synced key as last emitted: its stable parts (for tombstones) and
/// raw value (for diffing).
@immutable
final class _EmittedKey {
  const _EmittedKey(this.entityKey, this.component, this.field, this.value);

  final String entityKey;
  final String component;
  final String field;
  final Object? value;
}

/// Resolves a capture column key to `(component type name, field, column id)`.
///
/// Mirrors the key grammar of `ecsly_serialization`'s capture: SoA columns
/// are `{componentId}_{offset}` and object columns are `obj_{componentId}`.
/// Anything unparsable, or without a known type name, is skipped — it cannot
/// be named stably, so it must not travel.
(String, String, int)? _parseColumnKey(
  final String key,
  final Map<int, String> typeNameById,
) {
  if (key.startsWith('obj_')) {
    final id = int.tryParse(key.substring(4));
    if (id == null) return null;
    final typeName = typeNameById[id];
    if (typeName == null) return null;
    return (typeName, 'obj', id);
  }
  final underscore = key.indexOf('_');
  if (underscore <= 0) return null;
  final id = int.tryParse(key.substring(0, underscore));
  if (id == null) return null;
  final field = key.substring(underscore + 1);
  if (int.tryParse(field) == null) return null;
  final typeName = typeNameById[id];
  if (typeName == null) return null;
  return (typeName, field, id);
}

/// Structural equality for JSON-shaped captured values (num/bool/String and
/// nested Map/List from object codecs).
bool _deepEquals(final Object? a, final Object? b) {
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

final class _BridgeFlushObserver implements WorldFlushObserver {
  const _BridgeFlushObserver(this._bridge);

  final WorldSyncBridge _bridge;

  @override
  void onFlushEnd(
    final World world, {
    required final int elapsedMicroseconds,
    required final int commandsExecuted,
    required final int resourcesPushed,
    required final int resourcesRemoved,
  }) {
    // Delegate to whoever was displaced by attach() (null when absent).
    final previous = _bridge._previousObserver;
    previous?.onFlushEnd(
      world,
      elapsedMicroseconds: elapsedMicroseconds,
      commandsExecuted: commandsExecuted,
      resourcesPushed: resourcesPushed,
      resourcesRemoved: resourcesRemoved,
    );
    _bridge._emit();
  }

  @override
  void onFlushStart(final World world) {
    _bridge._previousObserver?.onFlushStart(world);
  }
}
