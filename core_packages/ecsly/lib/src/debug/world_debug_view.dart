import '../archetypes/archetypes.dart';
import '../components/components.dart';
import '../resources/resources.dart';
import '../systems/systems.dart';
import '../world/world.dart';

class ArchetypeDebugInfo {
  const ArchetypeDebugInfo({
    required this.archetypeId,
    required this.entityCount,
    required this.componentIds,
    required this.columns,
  });

  final ArchetypeId archetypeId;
  final int entityCount;
  final List<ComponentId> componentIds;
  final List<ColumnDebugInfo> columns;
}

class ColumnDebugInfo {
  const ColumnDebugInfo({
    required this.componentId,
    required this.kind,
    required this.stride,
    required this.length,
    required this.capacity,
  });

  final ComponentId componentId;
  final ColumnKind kind;
  final int stride;
  final int length;
  final int capacity;
}

enum ColumnKind { float32, int32, uint8, object, unknown }

class QueryCacheStats {
  const QueryCacheStats({
    required this.archetypeCacheSize,
    required this.resultCacheSize,
    required this.resultCacheHits,
    required this.resultCacheMisses,
    required this.resultCacheInvalidations,
    required this.resultCacheHitRate,
    required this.structurallyTouchedComponents,
  });

  final int archetypeCacheSize;
  final int resultCacheSize;
  final int resultCacheHits;
  final int resultCacheMisses;
  final int resultCacheInvalidations;
  final double resultCacheHitRate;
  final List<ComponentId> structurallyTouchedComponents;
}

class ResourceDebugInfo {
  const ResourceDebugInfo({
    required this.type,
    required this.id,
    required this.exists,
    required this.isPendingPush,
  });

  final Type type;
  final ResourceId? id;
  final bool exists;
  final bool isPendingPush;
}

class ScheduleDebugInfo {
  const ScheduleDebugInfo({
    required this.name,
    required this.systemCount,
    required this.systems,
  });

  final String name;
  final int systemCount;
  final List<SystemDebugInfo> systems;
}

class SystemDebugInfo {
  const SystemDebugInfo({
    required this.name,
    required this.mode,
    required this.canRunInParallel,
    required this.runAfter,
    required this.runBefore,
  });

  final String? name;
  final ExecutionMode mode;
  final bool canRunInParallel;
  final List<String> runAfter;
  final List<String> runBefore;
}

class WorldDebugSnapshot {
  const WorldDebugSnapshot({
    required this.entityCount,
    required this.archetypeCount,
    required this.schedules,
    required this.archetypes,
    required this.resources,
    required this.commandQueuePending,
    required this.queryCacheStats,
  });

  final int entityCount;
  final int archetypeCount;

  final List<ScheduleDebugInfo> schedules;
  final List<ArchetypeDebugInfo> archetypes;
  final List<ResourceDebugInfo> resources;

  final int commandQueuePending;
  final QueryCacheStats queryCacheStats;
}

/// A stable, read-only "debug view" over a [World].
///
/// Designed for throttled polling by inspector UIs (overlay/DevTools) without
/// forcing callers to reach into internals ad-hoc.
class WorldDebugView {
  WorldDebugView(this.world);

  final World world;

  WorldDebugSnapshot snapshot() {
    // Intentionally does NOT call world.flush(). Debug UIs can decide if/when
    // to force a flush depending on their use-case.
    final scheduleNames = world.systems.scheduleNames;

    final schedules = <ScheduleDebugInfo>[];
    for (final name in scheduleNames) {
      final schedule = world.systems.tryGetSchedule(name);
      if (schedule == null) continue;
      schedules.add(_scheduleInfo(schedule));
    }

    final archetypes = <ArchetypeDebugInfo>[];
    for (final archetype in world.archetypes.all) {
      archetypes.add(_archetypeInfo(archetype));
    }

    final resources = <ResourceDebugInfo>[];
    final pendingTypes = <Type>{};
    for (final (type, _) in world.resources.pendingPush) {
      pendingTypes.add(type);
    }

    for (final entry in world.resources.debugTypeToId.entries) {
      final type = entry.key;
      final id = entry.value;
      final exists = world.resources.getById<Resource>(id) != null;
      resources.add(
        ResourceDebugInfo(
          type: type,
          id: id,
          exists: exists,
          isPendingPush: pendingTypes.contains(type),
        ),
      );
    }

    // Include resources that are pending push but not yet registered/flushed.
    for (final type in pendingTypes) {
      if (world.resources.debugTypeToId.containsKey(type)) continue;
      resources.add(
        ResourceDebugInfo(
          type: type,
          id: null,
          exists: false,
          isPendingPush: true,
        ),
      );
    }

    final queryStats = world.queryCache.stats;

    return WorldDebugSnapshot(
      entityCount: world.entities.count,
      archetypeCount: world.archetypes.count,
      schedules: schedules,
      archetypes: archetypes,
      resources: resources,
      commandQueuePending: world.commandQueue.commandCount,
      queryCacheStats: QueryCacheStats(
        archetypeCacheSize: queryStats.archetypeCacheSize,
        resultCacheSize: queryStats.resultCacheSize,
        resultCacheHits: queryStats.resultCacheHits,
        resultCacheMisses: queryStats.resultCacheMisses,
        resultCacheInvalidations: queryStats.resultCacheInvalidations,
        resultCacheHitRate: queryStats.resultCacheHitRate,
        structurallyTouchedComponents:
            world.queryCache.debugStructurallyTouchedComponents.toList()
              ..sort((final a, final b) => a.value.compareTo(b.value)),
      ),
    );
  }

  ArchetypeDebugInfo _archetypeInfo(final Archetype archetype) {
    final columns = <ColumnDebugInfo>[];
    for (final componentId in archetype.componentIds) {
      final column = archetype.getColumn(componentId);
      if (column == null) continue;

      columns.add(
        ColumnDebugInfo(
          componentId: componentId,
          kind: _columnKind(column),
          stride: _columnStride(column),
          length: column.length,
          capacity: column.capacity,
        ),
      );
    }

    return ArchetypeDebugInfo(
      archetypeId: archetype.archetypeId,
      entityCount: archetype.entityCount,
      componentIds: List.unmodifiable(archetype.componentIds),
      columns: columns,
    );
  }

  ScheduleDebugInfo _scheduleInfo(final Schedule schedule) {
    final systems = <SystemDebugInfo>[];
    for (final desc in schedule.systems) {
      systems.add(
        SystemDebugInfo(
          name: desc.name,
          mode: desc.mode,
          canRunInParallel: desc.canRunInParallel,
          runAfter: List.unmodifiable(desc.runAfter),
          runBefore: List.unmodifiable(desc.runBefore),
        ),
      );
    }

    return ScheduleDebugInfo(
      name: schedule.name,
      systemCount: schedule.systems.length,
      systems: systems,
    );
  }

  static ColumnKind _columnKind(final DataColumn column) => switch (column) {
    FloatColumn() => ColumnKind.float32,
    IntColumn() => ColumnKind.int32,
    Uint8Column() => ColumnKind.uint8,
    ObjectColumn() => ColumnKind.object,
  };

  static int _columnStride(final DataColumn column) => switch (column) {
    FloatColumn(:final stride) => stride,
    IntColumn(:final stride) => stride,
    Uint8Column() => 1,
    ObjectColumn() => 1,
  };
}
