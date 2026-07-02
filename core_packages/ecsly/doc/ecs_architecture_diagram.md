# ECS Architecture Flow Diagram

```mermaid
graph TB
    subgraph "World Layer"
        World["World<br/>(Central Coordinator)"]
        World -->|manages| ArchetypeRegistry["ArchetypeRegistry<br/>(Archetype Graph)"]
        World -->|manages| ComponentRegistry["ComponentRegistry<br/>(Type → ComponentId)"]
        World -->|manages| QueryCache["QueryCache<br/>(Structural Query Cache)"]
        World -->|manages| ResourceRegistry["ResourceRegistry<br/>(Global Resources)"]
        World -->|manages| SystemsRegistry["SystemsRegistry<br/>(Schedules & Plugins)"]
        World -->|tracks| Entities["Entities<br/>(Entity → Location Map)"]
        World -->|defers| CommandQueue["CommandQueue<br/>(Deferred Changes)"]
        World -->|extends| EventRegistryExtension["EventRegistryExtension<br/>(world.events)"]
        World -->|initializes| InitOrder["Initialization Order:<br/>Entities → Components →<br/>CommandQueue → Resources →<br/>QueryCache → Archetypes"]
        World -->|has| IsFlushing["isFlushing Flag<br/>(Prevent Recursion)"]
    end

    subgraph "Entity Management"
        Entity["Entity<br/>(64-bit: Index + Generation)"]
        Entities["Entities<br/>(Entity → Location Map)"]
        Entities -->|stores parallel arrays| EntityArrays["Parallel Arrays<br/>(_generations, _archetypeIds, _archetypeRows)"]
        Entities -->|maps to| EntityLocation["EntityLocation<br/>(ArchetypeId + RowIndex)"]
        Entities -->|getLocation() returns| EntityLocation
        Entities -->|setLocation() updates| EntityArrays
        Entities -->|setLocationBatch() batch updates| EntityArrays
        Entities -->|create() allocates| Entity
        Entities -->|destroy() recycles| Entity
        Entities -->|isAlive() validates| Entity
        World -->|creates| WorldEntity["WorldEntity<br/>(Structural Changes)"]
        World -->|creates| WorldEntityMut["WorldEntityMut<br/>(Data Mutation)"]
        World -->|creates| WorldEntityExtension["WorldEntityExtension<br/>(Extension Type Access)"]
        World -->|has| WorldCommandsProp["commands<br/>(WorldCommands)"]
        WorldCommandsProp -->|returns| WorldCommands["WorldCommands<br/>(World-level Commands)"]
        WorldEntity -->|has| EntityLocation
        WorldEntityMut -->|wraps| WorldEntity
        WorldEntityExtension -->|wraps| WorldEntity
        WorldEntity -->|toMut()| WorldEntityMut
        WorldEntity -->|toExtension()| WorldEntityExtension
        WorldEntityMut -->|toEntity()| WorldEntity
        WorldEntityMut -->|toExtension()| WorldEntityExtension
        WorldEntityExtension -->|toEntity()| WorldEntity
        WorldEntityExtension -->|toMut()| WorldEntityMut
        WorldEntityMut -->|has| EntityLocation
        WorldEntityExtension -->|has| EntityLocation
        WorldEntity -->|accesses| Archetype["Archetype<br/>(SoA Storage)"]
        WorldEntityMut -->|accesses| Archetype
        WorldEntityExtension -->|accesses| Archetype
        WorldEntity -->|creates| EntityCommands["EntityCommands<br/>(Entity-specific Commands)"]
        WorldEntityMut -->|getMut/getMut2/getMut3| ComponentFacade
        WorldEntityExtension -->|getExtension/create/getOrCreate| ComponentFacade
        WorldEntityExtension -->|create() calls| BatchAddExtensionComponents["batchAddExtensionComponents()<br/>(Zero-Initialized Components)"]
    end

    subgraph "Archetype System"
        ArchetypeSignature["ArchetypeSignature<br/>(ComponentMask)"]
        ArchetypeRegistry -->|creates/finds| Archetype
        ArchetypeRegistry -->|preRegisterArchetypes| PreRegisterArchetypes["Pre-register Archetypes<br/>(Batch Optimization)"]
        ArchetypeSignature -->|identifies| Archetype
        Archetype -->|contains| Entity
        Archetype -->|stores| Columns["Columns Map<br/>(ComponentId → Column)"]
        ArchetypeRegistry -->|uses| ComponentRegistry
        ArchetypeRegistry -->|invalidates| QueryCache
        ArchetypeRegistry -->|findMatchingArchetypes| FindMatchingArchetypes["findMatchingArchetypes()<br/>(Query Mask Matching)"]
        Archetype -->|provides| GetColumn["getColumn(ComponentId)"]
        Archetype -->|getComponentByEntity| ComponentAccess["getComponentByEntity<T>()<br/>(Entity-Based Access)"]
        Archetype -->|getComponentByIndex| ComponentIndexAccess["getComponentByIndex<T>()<br/>(Row-Based Access)"]
        Archetype -->|addEntity() single| Entity
        Archetype -->|addEntities() batch| Entity
        Archetype -->|removeEntity() swap-and-pop| Entity
        Archetype -->|moveEntity() migrates| Entity
        Archetype -->|maintains| EntityToRowMap["_entityToRowIndex<br/>(Entity → Row Mapping)"]
    end

    subgraph "Component Registry"
        ComponentRegistry["ComponentRegistry<br/>(Type → ComponentId)"]
        SparseTypeList["SparseTypeList<br/>(Type → ComponentId)"]
        ComponentRegistry -->|maps| SparseTypeList
        ComponentRegistry -->|maps| IdToType["ComponentId → Type"]
    end

    subgraph "Component Storage (SoA)"
        Column["Column<br/>(Abstract Base)"]
        FloatColumn["FloatColumn<br/>(Float32List)"]
        IntColumn["IntColumn<br/>(Int32List)"]
        Uint8Column["Uint8Column<br/>(Uint8List)"]
        ObjectColumn["ObjectColumn<br/>(List<Object>)"]

        Column -.->|implements| FloatColumn
        Column -.->|implements| IntColumn
        Column -.->|implements| Uint8Column
        Column -.->|implements| ObjectColumn

        Columns -->|stores| Column
        Column -->|TypedData| TypedData["dart:typed_data<br/>(Float32List, Int32List, etc.)"]

        ComponentRegistry -->|has reference| ColumnFactoryRegistry["ColumnFactoryRegistry<br/>(Column Creation)"]
        ComponentRegistry -->|createColumnFor() calls| ColumnFactoryRegistry
        ColumnFactoryRegistry -->|manages| ColumnFactory["ColumnFactory<br/>(Creates Columns)"]
        ColumnFactoryRegistry -->|createColumn() calls| ColumnFactory
        ColumnFactory -->|creates| FloatColumn
        ColumnFactory -->|creates| IntColumn
        ColumnFactory -->|creates| Uint8Column
        ColumnFactory -->|creates| ObjectColumn
        ArchetypeRegistry -->|creates columns via| ComponentRegistry
    end

    subgraph "SIMD System"
        SIMDUtils["SIMD Utils<br/>(simd_utils.dart)"]
        SIMDPatterns["SIMD Patterns<br/>(simd_patterns.dart)"]

        Float32x4["Float32x4<br/>(SIMD Vector)"]
        FloatColumn -->|simdView property| Float32x4List["Float32x4List<br/>(SIMD View)"]
        Float32x4List -->|contains| Float32x4

        SIMDUtils -->|provides| Float32x4Operations["Float32x4 Operations<br/>(add, multiply, etc.)"]
        SIMDPatterns -->|provides| UpdatePositionSimd["updatePositionSimd()<br/>(Position + Velocity)"]
        SIMDPatterns -->|provides| CalculateDistancesSimd["calculateDistancesSimd()<br/>(Distance Calculations)"]
        SIMDPatterns -->|provides| NormalizeVectorsSimd["normalizeVectorsSimd()<br/>(Vector Normalization)"]
        SIMDPatterns -->|provides| ScalePositionsSimd["scalePositionsSimd()<br/>(Position Scaling)"]

        System -->|can use| MovementSystemSimd["movementSystemSimd<br/>(SIMD-Optimized Movement)"]
        MovementSystemSimd -->|uses| SIMDPatterns
        MovementSystemSimd -->|accesses| Archetype
        MovementSystemSimd -->|calls| WorldEnsureFlushed["World.ensureFlushed()"]
        MovementSystemSimd -->|bypasses| ComponentQuery
        MovementSystemSimd -->|uses| ComponentMask
        MovementSystemSimd -->|uses| ArchetypeRegistry
    end

    subgraph "Persistent Entity System"
        PersistentEntity["PersistentEntity<br/>(extension type String)"]
        PersistentEntityMap["PersistentEntityMap<br/>(Component)"]

        PersistentEntityPlugin -->|registers| PersistentEntityMap
        PersistentEntity -->|maps to| Entity["Entity<br/>(Runtime Entity)"]
        PersistentEntityMap -->|stores| EntityToPersistentMap["Entity → PersistentEntity<br/>(Lookup Table)"]
        PersistentEntityMap -->|stored in| ComponentRegistry

        PersistentEntity -->|create() generates| IdCreator["IdCreator.create()<br/>(Unique String ID)"]
        PersistentEntity -->|used for| SaveLoadSystem["Save/Load System<br/>(Serialize/Deserialize)"]
    end

    subgraph "World Extensions"
        WorldComponentX["WorldComponentX<br/>(Component Access)"]
        WorldEntityX["WorldEntityX<br/>(Entity Management)"]
        WorldFlushX["WorldFlushX<br/>(Flush Operations)"]
        WorldPluginX["WorldPluginX<br/>(Plugin Management)"]
        WorldResourceX["WorldResourceX<br/>(Resource Access)"]
        WorldScheduleX["WorldScheduleX<br/>(Schedule Management)"]
        WorldQueryX["WorldQueryX<br/>(Query Extensions)"]
        WorldBatchSpawnX["WorldBatchSpawnX<br/>(Batch Operations)"]
        EventRegistryExtension["EventRegistryExtension<br/>(Event System Access)"]

        World -->|extends| WorldComponentX
        World -->|extends| WorldEntityX
        World -->|extends| WorldFlushX
        World -->|extends| WorldPluginX
        World -->|extends| WorldResourceX
        World -->|extends| WorldScheduleX
        World -->|extends| WorldQueryX
        World -->|extends| WorldBatchSpawnX
        World -->|extends| EventRegistryExtension

        WorldComponentX -->|provides| GetComponent["getComponent<T>()<br/>(Direct Component Access)"]
        WorldComponentX -->|provides| RemoveComponent["removeComponent<T>()<br/>(Deferred Removal)"]
        WorldComponentX -->|provides| UpsertComponent["upsertComponent<T>()<br/>(Insert/Update)"]
        WorldComponentX -->|provides| SpawnBundle["spawnBundle()<br/>(Atomic Component Bundle)"]

        WorldBatchSpawnX -->|provides| BatchSpawn["batchSpawn()<br/>(Spawn Multiple Entities)"]
        WorldBatchSpawnX -->|provides| PreRegisterArchetypes["preRegisterArchetypesForBundles()<br/>(Pre-register Archetypes)"]

        WorldEntityX -->|provides| DespawnEntity["despawnEntity()<br/>(Deferred Despawn)"]
        WorldEntityX -->|provides| GetEntity["getEntity()<br/>(WorldEntity Wrapper)"]
        WorldEntityX -->|provides| GetEntityMut["getEntityMut()<br/>(WorldEntityMut Wrapper)"]
        WorldEntityX -->|provides| GetEntityExtension["getEntityExtension()<br/>(WorldEntityExtension Wrapper)"]
        WorldEntityX -->|provides| ReserveEmptyEntity["reserveEmptyEntity()<br/>(Create Empty Entity)"]

        WorldFlushX -->|provides| Flush["flush()<br/>(Force Flush All)"]
        WorldFlushX -->|provides| FlushEntities["flushEntitiesOnly()<br/>(No-op)"]
        WorldFlushX -->|provides| FlushComponents["flushComponentsOnly()<br/>(No-op)"]
        WorldFlushX -->|provides| FlushResources["flushResourcesOnly()<br/>(Process Resources)"]
        WorldFlushX -->|provides| FlushCommands["flushCommandsOnly()<br/>(Process Commands)"]
        WorldFlushX -->|provides| EnsureFlushedMethod["ensureFlushed()<br/>(Conditional Auto-Flush)"]
        EnsureFlushedMethod -->|checks| IsFlushing
        EnsureFlushedMethod -->|checks| FlushChecks
        EnsureFlushedMethod -->|calls if needed| WorldFlush

        WorldPluginX -->|provides| AddPlugin["addPlugin()<br/>(Install Plugin)"]
        WorldPluginX -->|provides| GetPlugin["getPlugin()<br/>(Get Plugin)"]
        WorldPluginX -->|provides| HasPlugin["hasPlugin()<br/>(Check Plugin)"]
        WorldPluginX -->|provides| RemovePlugin["removePlugin()<br/>(Uninstall Plugin)"]

        WorldResourceX -->|provides| GetResource["getResource<T>()<br/>(Access Resource)"]
        WorldResourceX -->|provides| RemoveResource["removeResource<T>()<br/>(Deferred Removal)"]
        WorldResourceX -->|provides| UpsertResource["upsertResource<T>()<br/>(Insert/Update)"]

        WorldScheduleX -->|provides| CreateSchedule["createSchedule()<br/>(New Schedule)"]
        WorldScheduleX -->|provides| GetOrCreateSchedule["getOrCreateSchedule()<br/>(Get/Create)"]
        WorldScheduleX -->|provides| Schedule["schedule()<br/>(Access Schedule)"]
        WorldScheduleX -->|provides| HasSchedule["hasSchedule()<br/>(Check Schedule)"]
        WorldScheduleX -->|provides| RunSchedule["runSchedule()<br/>(Execute Schedule)"]
        WorldScheduleX -->|provides| RunScheduleAsync["runScheduleAsync()<br/>(Async Execution)"]
        WorldScheduleX -->|provides| RunSystem["runSystem()<br/>(Direct System Execution)"]
        WorldScheduleX -->|provides| RunSystemAsync["runSystemAsync()<br/>(Async System Execution)"]

        EventRegistryExtension -->|provides| RegisterEvent["register<T>()<br/>(Register Channel)"]
        EventRegistryExtension -->|provides| UnregisterEvent["unregister<T>()<br/>(Remove Channel)"]
        EventRegistryExtension -->|provides| HasRegisteredEvent["hasRegistered<T>()<br/>(Check Registration)"]
        EventRegistryExtension -->|provides| EventReader["reader<T>()<br/>(Get Reader)"]
        EventRegistryExtension -->|provides| EventWriter["writer<T>()<br/>(Get Writer)"]
        EventRegistryExtension -->|provides| EventChannelAccess["channel<T>()<br/>(Get Channel)"]
        EventRegistryExtension -->|provides| ClearAllEvents["clearAll()<br/>(Frame End Clear)"]

        WorldQueryX -->|provides| QueryMethods["query() / query2-6()<br/>(1-6 Component Queries)"]
        WorldQueryX -->|provides| QueryExtMethods["queryExt() / queryExt2-4()<br/>(Extension Type Queries)"]
        WorldQueryX -->|provides| QueryExtWhereMethods["queryExtWhere() /<br/>queryExt2Where()<br/>(Conditional Extension Queries)"]
        WorldQueryX -->|provides| QueryMutMethods["queryMut() / queryMut2-4()<br/>(Mutable Queries)"]
        WorldQueryX -->|provides| QueryBuilderMethod["queryBuilder()<br/>(Advanced Query Builder)"]
        WorldQueryX -->|uses| ComponentQuery
        QueryMethods -->|calls| ComponentQuery
        QueryExtMethods -->|calls| ComponentQuery
        QueryExtWhereMethods -->|calls| ComponentQuery
        QueryMutMethods -->|calls| ComponentQuery
        QueryBuilderMethod -->|returns| ComponentQueryBuilder
    end

    subgraph "Component Facades"
        ComponentFacade["Component Facade<br/>(Extension Type)"]
        Position["Position<br/>(extension type)"]
        ComponentFacadeFactory["ComponentFacadeFactory<br/>(create + initialize)"]
        ComponentFacadeRegistry["ComponentFacadeRegistry<br/>(Singleton: .instance)"]
        ColumnFactoryRegistry["ColumnFactoryRegistry<br/>(Singleton: .instance)"]

        World --> ComponentRegistry
        ComponentRegistry -.->|owns per-world| ComponentFacadeRegistry
        ComponentRegistry -.->|owns per-world| ColumnFactoryRegistry

        ComponentFacadeRegistry -->|manages| ComponentFacadeFactory
        ComponentFacadeRegistry -->|createFacade() uses| ComponentFacadeFactory
        ComponentFacadeRegistry -->|initializeColumn() calls| ComponentFacadeFactory
        ComponentFacadeRegistry -->|registerFactory() stores| ComponentFacadeFactory
        ComponentFacadeRegistry -->|unregisterFactory() removes| ComponentFacadeFactory
        ComponentFacadeFactory -->|initialize() stores| InstanceColumnRef["Instance Column Reference<br/>(per factory instance)"]
        ComponentFacadeFactory -->|create() passes| TupleData["Tuple (index, column)<br/>(per extension type)"]
        ComponentFacadeFactory -->|create() returns| ComponentFacade
        ComponentFacade -.->|example| Position
        Position -->|wraps| Column

        ColumnFactoryRegistry -->|manages| ColumnFactory["ColumnFactory<br/>(Creates Columns)"]
        ColumnFactoryRegistry -->|registerFactory() stores| ColumnFactory
        ColumnFactoryRegistry -->|unregisterFactory() removes| ColumnFactory
        ColumnFactoryRegistry -->|createColumn() calls| ColumnFactory
    end

    subgraph "Query System"
        ComponentQuery["ComponentQuery<br/>(Query Builder)"]
        QueryMask["ComponentMask<br/>(Bitmask)"]
        ComponentQuery -->|uses| QueryMask
        ComponentQuery -->|has| RequiredMask["requiredMask<br/>(Required Components)"]
        ComponentQuery -->|has| ExcludedMask["excludedMask<br/>(Excluded Components)"]
        ComponentQuery -->|calls| EnsureFlushed["World.ensureFlushed()"]
        ComponentQuery -->|uses| QueryCache
        ComponentQuery -->|getCachedResult() uses| QueryResultCache
        ComponentQuery -->|iter1/2/3/4/5/6() uses| ComponentRegistry
        ComponentQuery -->|iterMut1/2/3/4() uses| ComponentRegistry
        ComponentQuery -->|iterExt1/2/3/4() uses| ComponentRegistry
        ComponentQuery -->|iterExt1Where/2Where() uses| ComponentRegistry
        ComponentQuery -->|iter1Where() uses| ComponentRegistry
        ComponentQuery -->|getComponentId() calls| ComponentRegistry
        ComponentQuery -->|withType() adds| RequiredMask
        ComponentQuery -->|withoutType() adds| ExcludedMask
        ComponentQuery -->|matches() checks| ArchetypeSignature
        QueryCache["QueryCache<br/>(Archetype-match + entity-list cache)"]
        QueryCache -->|manages| ArchetypeCache["_archetypeCache<br/>(ComponentMask → ArchetypeMatchResult)"]
        QueryCache -->|manages| QueryResultCache["QueryResultCache<br/>(QueryCacheKey → QueryCacheEntry)"]
        QueryCache -->|getOrCompute() returns| ArchetypeMatchResult["ArchetypeMatchResult<br/>(matchingArchetypes only)"]
        QueryCache -->|getCachedResult() returns| QueryCacheEntry["QueryCacheEntry<br/>(entities + versions)"]
        QueryCache -->|getOrCompute() calls| ArchetypeRegistry
        QueryCache -->|_computeMatching() creates| ArchetypeMatchResult
        QueryResultCache -->|uses| StructuralTouchTrackerNode["QueryStructuralTouchTracker<br/>(Structurally touched component IDs)"]
        QueryResultCache -->|stores| QueryCacheKey["QueryCacheKey<br/>(mask + predicate)"]
        QueryResultCache -->|stores| QueryCacheEntry
        QueryResultCache -->|tracks versions| FlushVersion["_flushVersion<br/>(World Flush Counter)"]
        QueryResultCache -->|tracks versions| ArchetypeVersion["_archetypeVersion<br/>(Archetype Change Counter)"]
        QueryResultCache -->|validates| EntryValidation["entry.isValid()<br/>(Version Check)"]
        QueryResultCache -->|checks structural touches| StructuralTouchCheck["_structuralTouches.maskWasTouched()<br/>(Internal cache eviction by query mask)"]
        QueryCache -->|evicts| QueryCacheInvalidate["invalidate()<br/>(Full cache eviction)"]
        QueryCache -->|evicts| QueryCacheEvictForStructuralComponent["evictForStructuralComponent()<br/>(Structural component-touch eviction)"]
        QueryCache -->|markStructurallyTouched() delegates| QueryResultCache
        QueryCache -->|onArchetypeChange() delegates| QueryResultCache
        QueryCache -->|onWorldFlush() delegates| QueryResultCache
        QueryCache -->|uses| LRUEviction["LRU Eviction<br/>(maxCacheSize)"]
        QueryCache -->|tracks| CacheStats["CacheStats<br/>(hitRate, evictions, memory)"]
        ArchetypeRegistry -->|invalidates| QueryCache
        CommandQueue -->|invalidates| QueryCacheEvictForStructuralComponent
        World -->|evictQueriesForStructuralComponent() calls| QueryCache
        WorldEntityExtension -->|create() calls| BatchAddExtensionComponents
        BatchAddExtensionComponents -->|calls| CommandQueue
        BatchAddExtensionComponents -->|uses| ZeroInitComponent
        ComponentQuery -->|iterates| Archetype
        ComponentQuery -->|creates| Facades["Facades<br/>(via world.components.componentFacadeRegistry)"]

        QueryIterator1["_QueryIterator1Column<br/>(Single Component)"]
        QueryIterator2["_QueryIterator2<br/>(Two Components)"]
        QueryIterator3["_QueryIterator3<br/>(Three Components)"]
        QueryIterator4["_QueryIterator4<br/>(Four Components)"]
        QueryIterator5["_QueryIterator5<br/>(Five Components)"]
        QueryIterator6["_QueryIterator6<br/>(Six Components)"]
        QueryIteratorMut1["_QueryIteratorMut1<br/>(Mutable Single)"]
        QueryIteratorMut2["_QueryIteratorMut2<br/>(Mutable Two)"]
        QueryIteratorMut3["_QueryIteratorMut3<br/>(Mutable Three)"]
        QueryIteratorMut4["_QueryIteratorMut4<br/>(Mutable Four)"]
        QueryIteratorExt1["_QueryIteratorExt1<br/>(Extension Type Single)"]
        QueryIteratorExt2["_QueryIteratorExt2<br/>(Extension Type Two)"]
        QueryIteratorExt3["_QueryIteratorExt3<br/>(Extension Type Three)"]
        QueryIteratorExt4["_QueryIteratorExt4<br/>(Extension Type Four)"]
        QueryIteratorExt1Where["_QueryIteratorExt1Where<br/>(Conditional Extension Single)"]
        QueryIteratorExt2Where["_QueryIteratorExt2Where<br/>(Conditional Extension Two)"]
        QueryIterator1Where["_QueryIterator1Where<br/>(Conditional Single)"]
        ComponentQueryBuilder["ComponentQueryBuilder<br/>(Advanced Query Builder)"]

        ComponentQuery -->|iter1() returns| QueryIterator1
        ComponentQuery -->|iter1Where() returns| QueryIterator1Where
        ComponentQuery -->|iter2() returns| QueryIterator2
        ComponentQuery -->|iter3() returns| QueryIterator3
        ComponentQuery -->|iter4() returns| QueryIterator4
        ComponentQuery -->|iter5() returns| QueryIterator5
        ComponentQuery -->|iter6() returns| QueryIterator6
        ComponentQuery -->|iterMut1() returns| QueryIteratorMut1
        ComponentQuery -->|iterMut2() returns| QueryIteratorMut2
        ComponentQuery -->|iterMut3() returns| QueryIteratorMut3
        ComponentQuery -->|iterMut4() returns| QueryIteratorMut4
        ComponentQuery -->|iterExt1() returns| QueryIteratorExt1
        ComponentQuery -->|iterExt1Where() returns| QueryIteratorExt1Where
        ComponentQuery -->|iterExt2() returns| QueryIteratorExt2
        ComponentQuery -->|iterExt2Where() returns| QueryIteratorExt2Where
        ComponentQuery -->|iterExt3() returns| QueryIteratorExt3
        ComponentQuery -->|iterExt4() returns| QueryIteratorExt4
        ComponentQuery -->|withType() / withoutType()| ComponentQueryBuilder
        ComponentQueryBuilder -->|build() returns| ComponentQuery

        QueryIterator1 -->|uses| ComponentFacadeRegistry
        QueryIterator1 -->|initializeColumn() calls| ComponentFacadeRegistry
        QueryIterator1 -->|createFacadeWithoutInit() calls| ComponentFacadeRegistry
        QueryIterator1 -->|createFacadeForQuery() calls| ComponentFacadeRegistry
        QueryIterator1 -->|accesses| GetColumn
        QueryIterator1Where -->|uses| ComponentFacadeRegistry
        QueryIterator1Where -->|applies predicate| ComponentPredicate["ComponentPredicate<br/>(Filter Function)"]
        QueryIterator2 -->|uses| ComponentFacadeRegistry
        QueryIterator3 -->|uses| ComponentFacadeRegistry
        QueryIterator4 -->|uses| ComponentFacadeRegistry
        QueryIterator5 -->|uses| ComponentFacadeRegistry
        QueryIterator6 -->|uses| ComponentFacadeRegistry
        QueryIteratorExt1 -->|uses| ComponentFacadeRegistry
        QueryIteratorExt1 -->|validates extension type| ExtensionTypeValidation["Extension Type<br/>Validation"]
        QueryIteratorExt1Where -->|uses| ComponentFacadeRegistry
        QueryIteratorExt1Where -->|applies predicate| ExtensionPredicate["ExtensionPredicate<br/>(Filter Function)"]
        QueryIteratorExt2 -->|uses| ComponentFacadeRegistry
        QueryIteratorExt2 -->|validates extension types| ExtensionTypeValidation
        QueryIteratorExt2Where -->|uses| ComponentFacadeRegistry
        QueryIteratorExt2Where -->|applies predicate| ExtensionPredicate
        QueryIteratorExt3 -->|uses| ComponentFacadeRegistry
        QueryIteratorExt3 -->|validates extension types| ExtensionTypeValidation
        QueryIteratorExt4 -->|uses| ComponentFacadeRegistry
        QueryIteratorExt4 -->|validates extension types| ExtensionTypeValidation
        QueryIteratorMut1 -->|returns| WorldEntityMut
        QueryIteratorMut2 -->|returns| WorldEntityMut
        QueryIteratorMut3 -->|returns| WorldEntityMut
        QueryIteratorMut4 -->|returns| WorldEntityMut
        QueryIteratorExt1 -->|returns| WorldEntityExtension
        QueryIteratorExt2 -->|returns| WorldEntityExtension
        QueryIteratorExt3 -->|returns| WorldEntityExtension
        QueryIteratorExt4 -->|returns| WorldEntityExtension
        QueryIteratorExt1Where -->|returns| WorldEntityExtension
        QueryIteratorExt2Where -->|returns| WorldEntityExtension

        WorldQueryX -->|delegates to| ComponentQuery
        ComponentQuery -->|withType() / withoutType()| ComponentQueryBuilder
        ComponentQueryBuilder -->|withComponent() / withoutComponent()| ComponentQueryBuilder
    end

    subgraph "Command System"
        CommandQueue -->|has reference| World
        CommandQueue -->|processes| Command["EcsCommand<br/>(Sealed Class)"]
        Command -->|types| SpawnCommand["SpawnEntityComponentsCommand"]
        Command -->|types| UpsertCommand["UpsertComponentCommand"]
        Command -->|types| RemoveCommand["RemoveComponentCommand"]
        Command -->|types| DestroyCommand["DestroyEntityCommand"]
        Command -->|types| ResourceCommand["Resource Commands"]
        Command -->|types| BatchSpawnCommand["BatchSpawnCommand"]
        Command -->|types| BatchAddExtensionCommand["BatchAddExtensionComponentsCommand"]
        Command -->|types| BatchAddClassCommand["BatchAddClassComponentsCommand"]
        Command -->|types| BatchRemoveCommand["BatchRemoveComponentsCommand"]

        WorldCommands["WorldCommands<br/>(World-level Commands)"]
        WorldCommands -->|has| CommandQueueRef["queue<br/>(CommandQueue reference)"]
        WorldCommands -->|uses| CommandQueue
        WorldCommands -->|spawnBundle| ComponentBundle["ComponentBundle<br/>(Atomic Components)"]
        WorldCommands -->|batchSpawn| BatchSpawnCommand
        WorldCommands -->|batchAddExtensionComponents| BatchAddExtensionCommand
        WorldCommands -->|batchAddClassComponents| BatchAddClassCommand
        WorldCommands -->|batchRemoveComponents| BatchRemoveCommand
        ComponentBundle -->|contains| ComponentsBatchList["ComponentsBatchList<br/>(Type + Component)"]
        ComponentBundle -->|contains| ExtensionComponents["ExtensionComponents<br/>(Extension Type Components)"]

        EntityCommands["EntityCommands<br/>(Entity-specific Commands)"]
        EntityCommands -->|has| CommandQueueRef
        EntityCommands -->|has| EntityRef["entity<br/>(Entity reference)"]
        EntityCommands -->|uses| CommandQueue
        EntityCommands -->|despawn| DestroyCommand
        EntityCommands -->|remove| RemoveCommand
        EntityCommands -->|upsert| UpsertCommand

        CommandQueue -->|executes| CommandExecution["execute()<br/>(Process All Commands)"]
        CommandExecution -->|calls| SpawnEntityMethod["_spawnEntityWithComponents()<br/>(Entity Creation)"]
        CommandExecution -->|calls| UpsertComponentMethod["_upsertComponent()<br/>(Add/Update Component)"]
        CommandExecution -->|calls| RemoveComponentMethod["_removeComponent()<br/>(Remove Component)"]
        CommandExecution -->|calls| BatchSpawnMethod["_batchSpawnEntities()<br/>(Batch Creation)"]
        CommandExecution -->|calls| BatchAddExtensionMethod["_batchAddExtensionComponents()<br/>(Batch Extension Components)"]
        CommandExecution -->|calls| BatchAddClassMethod["_batchAddClassComponents()<br/>(Batch Class Components)"]
        CommandExecution -->|calls| BatchRemoveMethod["_batchRemoveComponents()<br/>(Batch Remove Components)"]
        CommandExecution -->|calls| DestroyEntityMethod["_destroyEntity()<br/>(Entity Removal)"]

        CommandQueue -->|provides| UnifiedAddMethod["addComponentsToEntitiesUnified()<br/>(Unified Bundle-First Addition)"]
        UnifiedAddMethod -->|calls| AddComponentsMethod["_addComponentsToEntities()<br/>(Core Batch Implementation)"]
        AddComponentsMethod -->|handles| FreshEntities["Fresh Entities<br/>(Direct Addition Path)"]
        AddComponentsMethod -->|handles| ExistingEntities["Existing Entities<br/>(Migration Path)"]
        AddComponentsMethod -->|creates archetype| CreateArchetypeForComponents["_createArchetypeForComponents()<br/>(Single Archetype Resolution)"]
        AddComponentsMethod -->|batch adds| ArchetypeAddEntities["archetype.addEntity()<br/>(Single Entity Addition)"]
        AddComponentsMethod -->|batch adds| ArchetypeAddEntitiesBatch["archetype.addEntities()<br/>(Batch Entity Addition)"]
        AddComponentsMethod -->|batch location updates| EntitiesSetLocationBatch["Entities.setLocationBatch()<br/>(Batch Location Setting)"]
        AddComponentsMethod -->|batch writes| BatchWriteClassComponents["_batchWriteClassComponents()<br/>(Class Component Data)"]
        AddComponentsMethod -->|batch initializes| InitializeExtensionComponentsBatch["_initializeExtensionComponentsBatch()<br/>(Extension Component Init)"]
        AddComponentsMethod -->|evicts cache| QueryCacheEvictForStructuralComponent

        BatchAddExtensionMethod -->|uses| UnifiedAddMethod
        BatchAddClassMethod -->|uses| UnifiedAddMethod
        BatchSpawnMethod -->|uses| UnifiedAddMethod

        UpsertComponentMethod -->|migrates via| EntityMigrationSystem["EntityMigrationSystem<br/>(Archetype Migration)"]
        RemoveComponentMethod -->|migrates via| EntityMigrationSystem
        BatchRemoveMethod -->|migrates via| EntityMigrationSystem
        UpsertComponentMethod -->|evicts cache| QueryCacheEvictForStructuralComponent
        RemoveComponentMethod -->|evicts cache| QueryCacheEvictForStructuralComponent
        BatchRemoveMethod -->|evicts cache| QueryCacheEvictForStructuralComponent
        CommandQueue -->|executes resource commands| ResourceRegistry

        BatchSpawnMethod -->|resolves| UnifiedArchetype["Unified Archetype Resolution<br/>(Class + Extension Components)"]
        BatchSpawnMethod -->|pre-allocates| EntityIds["Entity ID Pre-allocation<br/>(Entities.create() batch)"]
        BatchSpawnMethod -->|batch adds| ArchetypeAddEntitiesBatch
        BatchSpawnMethod -->|batch location updates| EntitiesSetLocationBatch
        BatchSpawnMethod -->|batch writes| ClassComponentWrite["_batchWriteClassComponents()<br/>(Data Copying)"]
        BatchSpawnMethod -->|batch initializes| ExtensionComponentInit["_batchInitializeExtensionComponents()<br/>(Zero-Initialized)"]
        BatchSpawnMethod -->|selective invalidation| QueryCacheEvictForStructuralComponent
    end

    subgraph "Entity Migration"
        EntityMigrationSystem -->|uses| ArchetypeResolver["ArchetypeResolver<br/>(Resolve Current/Dest)"]
        EntityMigrationSystem -->|uses| SignatureComputer["SignatureComputer<br/>(Compute New Signature)"]
        EntityMigrationSystem -->|uses| EntityMigrator["EntityMigrator<br/>(Move Entity Data)"]
        EntityMigrationSystem -->|uses| ComponentDataWriter["ComponentDataWriter<br/>(Write Component Data)"]
        ComponentDataWriter -->|uses| ExtractorRegistry["ExtractorRegistry<br/>(Type-Safe Data Extraction)"]
        ExtractorRegistry -->|provides| ComponentDataExtractor["ComponentDataExtractor<br/>(Extract Floats/Ints/Objects)"]
        ComponentDataExtractor -->|types| XYFieldExtractor["XYFieldExtractor<br/>(x, y fields)"]
        ComponentDataExtractor -->|types| ValueFieldExtractor["ValueFieldExtractor<br/>(value field)"]
        ComponentDataExtractor -->|types| PrimitiveExtractor["PrimitiveExtractor<br/>(num, int, double)"]
        ComponentDataExtractor -->|types| ListExtractor["ListExtractor<br/>(List types)"]

        EntityMigrationSystem -->|provides| MigrateAddComponent["migrateAddComponent()<br/>(Add Component)"]
        EntityMigrationSystem -->|provides| MigrateRemoveComponent["migrateRemoveComponent()<br/>(Remove Component)"]

        MigrateAddComponent -->|resolves| ArchetypeResolver
        MigrateAddComponent -->|computes| SignatureComputer
        MigrateAddComponent -->|migrates| EntityMigrator
        MigrateAddComponent -->|writes data| ComponentDataWriter

        MigrateRemoveComponent -->|resolves| ArchetypeResolver
        MigrateRemoveComponent -->|computes| SignatureComputer
        MigrateRemoveComponent -->|migrates| EntityMigrator

        EntityMigrator -->|updates| Entities
        EntityMigrator -->|setLocation() updates| EntityLocation
        EntityMigrator -->|moves between| Archetype
        EntityMigrator -->|swap-and-pop| SwapPop["Swap-and-Pop<br/>(Maintains Dense Arrays)"]
        EntityMigrator -->|copies component data| ComponentDataCopy["Component Data Copy<br/>(Preserves Existing Data)"]
    end

    subgraph "Resource System"
        ResourceRegistry -->|has reference| World
        ResourceRegistry -->|stores| Resource["Resource<br/>(Global State)"]
        ResourceRegistry -->|maintains| PendingPush["pendingPush<br/>(Queue)"]
        ResourceRegistry -->|maintains| PendingRemove["pendingRemove<br/>(Queue)"]
        ResourceRegistry -->|doesNeedFlush checks| PendingPush
        ResourceRegistry -->|doesNeedFlush checks| PendingRemove
        ResourceRegistry -->|get() calls| EnsureFlushed
        ResourceRegistry -->|flush() processes| PendingPush
        ResourceRegistry -->|flush() processes| PendingRemove
        ResourceRegistry -->|flushToUpsert() processes| PendingPush
        ResourceRegistry -->|flushToRemove() processes| PendingRemove
        WorldCommands -->|upsertResource| ResourceCommand
        WorldCommands -->|removeResource| ResourceCommand
        ResourceCommand -->|pushes to| PendingPush
        ResourceCommand -->|pushes to| PendingRemove
    end

    subgraph "System Execution"
        System["System<br/>(Game Logic)"]
        SystemsRegistry -->|manages| PluginRegistry["PluginRegistry<br/>(Installed Plugins)"]
        SystemsRegistry -->|manages| SystemExecutor["SystemExecutor<br/>(Executes Systems)"]
        SystemsRegistry -->|stores| ScheduleMap["ScheduleMap<br/>(Map<String, Schedule>)"]
        SystemsRegistry -->|creates| Schedule["Schedule<br/>(System Execution Order)"]
        SystemsRegistry -->|creates Schedule with| SystemExecutor
        ScheduleMap -->|contains| NamedSchedule["NamedSchedule<br/>(HighFrequency, Update, etc.)"]

        Schedule -->|uses| SystemExecutor
        Schedule -->|has| ScheduleTrigger["ScheduleTrigger<br/>(When to Run)"]
        Schedule -->|contains| SystemDescriptor["SystemDescriptor<br/>(System + Metadata)"]
        Schedule -->|uses| DirectedGraph["DirectedGraph<br/>(Dependency Resolution)"]
        Schedule -->|_resolveOrder() uses| DirectedGraph
        Schedule -->|_groupByDependencyLevel() groups| DependencyLevels["Dependency Levels<br/>(Topological Sort)"]
        DirectedGraph -->|topologicalOrdering() returns| DependencyLevels
        DirectedGraph -->|isAcyclic() detects| CircularDependencyError
        SystemDescriptor -->|wraps| System
        SystemDescriptor -->|has optional| CertifiedScheduleJobSystem["CertifiedScheduleJobSystem<br/>(Extract → Partition → Execute → Merge)"]
        SystemDescriptor -->|has| ExecutionMode["ExecutionMode<br/>(sync/async/isolate)"]
        SystemDescriptor -->|has optional| IsolateConfig["IsolateConfig<br/>(Isolate Execution)"]
        SystemExecutor -->|executeSchedule() calls| SystemDescriptor
        SystemExecutor -->|executes| System
        SystemExecutor -->|runAsync() / runSerial() uses| CertifiedScheduleJobSystem
        SystemExecutor -->|executes grouped by| DependencyLevels
        SystemExecutor -->|_executeGroupAsync() supports| ParallelExecution["Parallel Execution<br/>(Future.wait)"]
        SystemExecutor -->|_executeInIsolate() uses| IsolateConfig
        SystemExecutor -->|supports| SequentialExecution["Sequential Execution<br/>(sync/async)"]
        SystemExecutor -->|supports| ParallelExecution
        SystemExecutor -->|supports| IsolateExecution["Isolate Execution<br/>(compute())"]
        World -->|installs by default| ScheduleExecutionPolicyResource["ScheduleExecutionPolicyResource<br/>(serial/deterministic/bestEffort)"]
        World -->|installs by default| ScheduleJobResultQueueResource["ScheduleJobResultQueueResource<br/>(Frame-Stamped Job Results)"]

        System -->|queries| ComponentQuery
        System -->|queries via| WorldQueryX
        System -->|reads/writes| ComponentFacade
        World -->|executes| Schedule
        World -->|manages multiple| NamedSchedule
        WorldScheduleX -->|runSchedule() executes| Schedule
    end

    subgraph "Schedule Triggers"
        ScheduleTrigger -->|types| EveryFrame["EveryFrame<br/>(Every Frame)"]
        ScheduleTrigger -->|types| EveryNFrames["EveryNFrames<br/>(Every N Frames)"]
        ScheduleTrigger -->|types| EveryNSeconds["EveryNSeconds<br/>(Every N Seconds)"]
        ScheduleTrigger -->|types| ConditionTrigger["ConditionTrigger<br/>(Custom Condition)"]
        ScheduleTrigger -->|types| ManualTrigger["ManualTrigger<br/>(Manual Only)"]
        ScheduleTrigger -->|types| ThrottledTrigger["ThrottledTrigger<br/>(Rate Limited)"]
        ScheduleTrigger -->|types| EventTrigger["EventTrigger<br/>(Event-Driven)"]

        EveryNSeconds -->|reads| DeltaTimeResource["DeltaTimeResource<br/>(Frame Time)"]
        ThrottledTrigger -->|wraps| ScheduleTrigger
        ConditionTrigger -->|evaluates| CustomCondition["Custom Condition<br/>Function(World) → bool"]
        EventTrigger -->|checks| EventChannel["EventChannel.length > 0<br/>(Event Presence)"]
        EventTrigger -->|uses| EventRegistryExtension

        ScheduleTrigger -->|shouldRun() checks| World
        EveryNSeconds -->|requires| ScheduleTimeResource["ScheduleTimeResource<br/>(deterministic delta/elapsed)"]
        EveryNSeconds -->|optional compatibility| DeltaTimeResource
        EveryNSeconds -->|optional explicit adapter| WallClockScheduleTimeResource
    end

    subgraph "Auto-Flush System"
        ComponentQuery -->|iter*() calls| EnsureFlushed["World.ensureFlushed()"]
        ResourceRegistry -->|get<T>() calls| EnsureFlushed
        WorldQueryX -->|query*() calls| EnsureFlushed
        WorldEntityX -->|getEntity*() calls| EnsureFlushed
        WorldComponentX -->|getComponent() calls| EnsureFlushed
        EnsureFlushed -->|checks| IsFlushing
        EnsureFlushed -->|checks| FlushChecks["resources.doesNeedFlush<br/>commandQueue.needsFlush"]
        EnsureFlushed -->|calls if needed| WorldFlush["World.flush()"]
        WorldFlush -->|sets| IsFlushing
        WorldFlush -->|executes in order| FlushOrder["flushEntitiesOnly() (no-op)<br/>flushComponentsOnly() (no-op)<br/>flushResourcesOnly() →<br/>flushCommandsOnly() →<br/>conditional second flush"]
        FlushOrder -->|calls| ResourcesFlush["Resources.flush()"]
        FlushOrder -->|calls| CommandsExecute["CommandQueue.execute()"]
        FlushOrder -->|conditional second flush if| FlushChecks
        WorldFlush -->|clears| IsFlushing
        WorldFlushX -->|provides| EnsureFlushedMethod
    end

    subgraph "Phase Systems"
        FlushAllSystem["flushAllSystem<br/>(All phases)"]
        FlushEntitiesSystem["flushEntitiesSystem"]
        FlushComponentsSystem["flushComponentsSystem"]
        FlushResourcesSystem["flushResourcesSystem"]
        FlushCommandsSystem["flushCommandsSystem"]

        FlushAllSystem -->|calls| WorldFlush
        FlushEntitiesSystem -->|calls| EntitiesFlush["flushEntitiesOnly() (no-op)"]
        FlushComponentsSystem -->|calls| ComponentsFlush["flushComponentsOnly() (no-op)"]
        FlushResourcesSystem -->|calls| ResourcesFlush
        FlushCommandsSystem -->|calls| CommandsExecute

        Schedule -->|can contain| FlushAllSystem
        Schedule -->|can contain| FlushEntitiesSystem
        Schedule -->|can contain| FlushComponentsSystem
        Schedule -->|can contain| FlushResourcesSystem
        Schedule -->|can contain| FlushCommandsSystem
    end

    subgraph "Event System"
        EventRegistry["EventRegistry<br/>(Event Channel Manager)"]
        EventRegistryExtension -->|provides| EventRegistry
        EventRegistry -->|has| TypedDataEventRegistry["TypedDataEventRegistry<br/>(Per-World Instance)"]
        EventRegistry -->|registers| EventChannel["EventChannel<T><br/>(Ring Buffer)"]
        EventRegistry -->|stores channels in| ResourceRegistry
        EventRegistry -->|clearAll() iterates| ResourceRegistry
        EventChannel -->|implements| Resource["Resource<br/>(Stored as Resource)"]
        EventChannel -->|uses| DataColumn["DataColumn<br/>(FloatColumn/IntColumn/ObjectColumn)"]
        EventChannel -->|has| EventColumnConfig["EventColumnConfig<br/>(Mapping Config)"]
        EventChannel -->|ring buffer| RingBufferIndices["Ring Buffer<br/>(_head, _tail, _length)"]
        EventChannel -->|creates| EventReader["EventReader<T><br/>(Snapshot Iterator)"]
        EventChannel -->|creates| EventWriter["EventWriter<T><br/>(Send Events)"]
        EventReader -->|iter() provides| EventIterator["Event Iterator<br/>(Snapshot Semantics)"]
        EventReader -->|iterSimd() provides| FloatColumnEventIterator["FloatColumnEventIterator<br/>(SIMD Access)"]
        EventWriter -->|send() writes| EventChannel
        EventWriter -->|sendBatch() writes| EventChannel
        EventColumnMapper["EventColumnMapper<br/>(Event ↔ Column Mapping)"]
        EventColumnMapper -->|loadFromFloatColumn| FloatColumn
        EventColumnMapper -->|loadFromIntColumn| IntColumn
        EventColumnMapper -->|loadFromObjectColumn| ObjectColumn
        EventColumnMapper -->|storeToFloatColumn| FloatColumn
        EventColumnMapper -->|storeToIntColumn| IntColumn
        EventColumnMapper -->|storeToObjectColumn| ObjectColumn
        EventColumnMapper -->|uses| TypedDataEventMixin["TypedDataEventMixin<br/>(numericFields)"]
        EventColumnMapper -->|uses| FromNumericFieldsFactory["fromNumericFieldsFactory<br/>(T Function(List<num>))"]
        EventPlugin["EventPlugin<br/>(Core Event System)"]
        EventPlugin -->|installs| EventRegistryExtension
        EventPlugin -->|adds| EventClearSystem["eventClearSystem<br/>(Frame End Clear)"]
        EventClearSystem -->|calls| EventRegistryClearAll["EventRegistry.clearAll()"]
        EventRegistryClearAll -->|iterates| ResourceRegistry
        EventRegistryClearAll -->|calls| EventChannelClear["EventChannel.clear()"]
        EventChannelClear -->|O(1) for TypedData| RingBufferIndices
        EventChannelClear -->|O(length) for ObjectColumn| ObjectColumnNullOut["ObjectColumn.fillRange(null)"]
        TypedDataEventRegistry -->|registers| TypedDataEventTypes["TypedDataEvent Types<br/>(Type → Stride)"]
        TypedDataEventRegistry -->|validates| EventRegistrationValidation["Event Registration<br/>(Factory + Sample Validation)"]
        EventRegistrationValidation -->|validates| TypedDataEventMixin
        EventRegistrationValidation -->|validates| FromNumericFieldsFactory
        EventRegistrationValidation -->|validates| StrideMatch["Stride Matching<br/>(Sample vs Factory)"]
    end

    subgraph "Plugin System"
        PluginRegistry -->|manages| Plugin["Plugin<br/>(Reusable Features)"]
        Plugin -->|installs into| World
        Plugin -->|registerSoAComponent/registerObjectComponent/registerTagComponent/registerExtension calls| ComponentRegistry
        Plugin -->|registerFactory() calls| ComponentFacadeRegistry
        Plugin -->|registerFactory() calls| ColumnFactoryRegistry
        Plugin -->|adds| Schedule
        Plugin -->|modifies| World

        Plugin -->|types| Game2DPlugin["Game2DPlugin<br/>(2D Game Components)"]
        Plugin -->|types| DebugPlugin["DebugPlugin<br/>(Performance Monitoring)"]
        Plugin -->|types| PersistentEntityPlugin["PersistentEntityPlugin<br/>(Save/Load Support)"]
        Plugin -->|types| EventPlugin

        Game2DPlugin -->|registers| PositionComponent["PositionComponent<br/>(x, y)"]
        Game2DPlugin -->|registers| VelocityComponent["VelocityComponent<br/>(dx, dy)"]
        Game2DPlugin -->|registers| SizeComponent["SizeComponent<br/>(width, height)"]
        Game2DPlugin -->|registers| HealthComponent["HealthComponent<br/>(value)"]
        Game2DPlugin -->|registers| PathfindingComponent["PathfindingComponent<br/>(waypoints)"]
        Game2DPlugin -->|creates| PositionFacadeFactory["PositionFacadeFactory"]
        Game2DPlugin -->|creates| VelocityFacadeFactory["VelocityFacadeFactory"]
        Game2DPlugin -->|creates| SizeFacadeFactory["SizeFacadeFactory"]
        Game2DPlugin -->|creates| HealthFacadeFactory["HealthFacadeFactory"]
        Game2DPlugin -->|creates| PathfindingFacadeFactory["PathfindingFacadeFactory"]
        Game2DPlugin -->|creates| PositionColumnFactory["PositionColumnFactory<br/>(Float32List stride 2)"]
        Game2DPlugin -->|creates| VelocityColumnFactory["VelocityColumnFactory<br/>(Float32List stride 2)"]
        Game2DPlugin -->|creates| SizeColumnFactory["SizeColumnFactory<br/>(Float32List stride 2)"]
        Game2DPlugin -->|creates| HealthColumnFactory["HealthColumnFactory<br/>(Int32List stride 1)"]
        Game2DPlugin -->|creates| PathfindingColumnFactory["PathfindingColumnFactory<br/>(ObjectColumn)"]

        DebugPlugin -->|adds| PerformanceResource["PerformanceResource<br/>(fps, frameTime, entityCount)"]
        DebugPlugin -->|adds| SpawnPerformanceResource["SpawnPerformanceResource<br/>(spawn/despawn timing)"]
        DebugPlugin -->|adds| PerformanceSystem["performanceSystem<br/>(Metrics Collection)"]

        PersistentEntityPlugin -->|registers| PersistentEntityMap["PersistentEntityMap<br/>(Entity → PersistentEntity)"]
    end

    subgraph "Error Handling"
        EcsException["EcsException<br/>(Recoverable Conditions)"]
        EcsStateError["EcsStateError<br/>(Programming Mistakes)"]

        EntityNotFoundError["EntityNotFoundError<br/>(Entity not alive)"]
        ComponentNotFoundError["ComponentNotFoundError<br/>(Component missing)"]
        ComponentNotRegisteredError["ComponentNotRegisteredError<br/>(Type not registered)"]
        ArchetypeNotFoundError["ArchetypeNotFoundError<br/>(Archetype missing)"]
        CircularDependencyError["CircularDependencyError<br/>(System cycle)"]
        IteratorNotReadyError["IteratorNotReadyError<br/>(Iterator invalid)"]
        SystemConfigurationError["SystemConfigurationError<br/>(Invalid config)"]
        ComponentRegistrationException["ComponentRegistrationException<br/>(Registration failed)"]
        PluginInstallationException["PluginInstallationException<br/>(Install failed)"]

        EcsException -.->|extends| ComponentRegistrationException
        EcsException -.->|extends| PluginInstallationException
        EcsStateError -.->|extends| EntityNotFoundError
        EcsStateError -.->|extends| ComponentNotFoundError
        EcsStateError -.->|extends| ComponentNotRegisteredError
        EcsStateError -.->|extends| ArchetypeNotFoundError
        EcsStateError -.->|extends| CircularDependencyError
        EcsStateError -.->|extends| IteratorNotReadyError
        EcsStateError -.->|extends| SystemConfigurationError

        World -->|throws| EntityNotFoundError
        World -->|throws| ComponentNotFoundError
        WorldEntityMut -->|throws| ComponentNotFoundError
        ComponentRegistry -->|throws| ComponentNotRegisteredError
        ComponentRegistry -->|throws| EcsStateError
        ComponentQuery -->|throws| IteratorNotReadyError
        Schedule -->|throws| CircularDependencyError
        SystemExecutor -->|throws| SystemConfigurationError
        PluginRegistry -->|throws| PluginInstallationException
        ArchetypeRegistry -->|throws| ArchetypeNotFoundError
        CommandQueue -->|throws| EntityNotFoundError
        CommandQueue -->|throws| ComponentNotRegisteredError
    end

    style World fill:#e1f5ff
    style Archetype fill:#fff4e1
    style Column fill:#e8f5e9
    style ComponentFacade fill:#f3e5f5
    style ComponentQuery fill:#ffe0e0
    style ResourceRegistry fill:#fff9e6
    style SystemsRegistry fill:#f0e6ff
    style CommandQueue fill:#ffe6e6
    style EntityMigrationSystem fill:#e6f7ff
    style ComponentFacadeRegistry fill:#fce4ec
    style EnsureFlushed fill:#e8f5e9
    style WorldFlush fill:#e8f5e9
    style EcsException fill:#ffebee
    style EcsStateError fill:#ffcdd2
    style EventRegistry fill:#e3f2fd
    style EventChannel fill:#bbdefb
    style EventReader fill:#90caf9
    style EventWriter fill:#90caf9
    style EventTrigger fill:#64b5f6
    style TypedDataEventRegistry fill:#42a5f5
```

## Key Data Flow

### Entity Lifecycle

**Operations:**

- **Creation**: `WorldCommands.spawn()` → `CommandQueue` → `Archetype.addEntity()`
- **Bundle Creation**: `WorldCommands.spawnBundle()` → `ComponentBundle` → `SpawnEntityComponentsCommand` → `CommandQueue` → `Archetype.addEntity()`
- **Batch Creation**: `World.batchSpawn(bundle, count)` → `BatchSpawnCommand` → `CommandQueue.execute()` → `_batchSpawnEntities()` → unified archetype resolution → batch entity allocation → `archetype.addEntities()` → batch location setting → `_batchWriteClassComponents()` (data copying) → `_batchInitializeExtensionComponents()` (zero-initialized) → structural cache eviction
- **Zero-Initialized Component**: `WorldEntityExtension.create<TComponent, TExtension>()` → validates extension type → checks if component exists → if missing: `world.commandQueue.batchAddExtensionComponents([entity], [(TComponent, TExtension)])` → `CommandQueue.batchAddExtensionComponents()` → `BatchAddExtensionComponentsCommand` → `CommandQueue.execute()` → `_batchAddExtensionComponents()` → converts to component IDs → creates `ComponentBundle` → `addComponentsToEntitiesUnified()` → `_addComponentsToEntities()` → unified archetype resolution → batch entity addition → `_initializeExtensionComponentsBatch()` → `ComponentFacadeRegistry.initializeColumn()` → returns facade via `getExtension()`
- **Component Addition**: `EntityCommands.upsert<T>(component)` → `UpsertComponentCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_upsertComponent()` → validates entity → resolves current archetype → if component exists: updates in-place → if missing: `EntityMigrationSystem.migrateAddComponent()` → `Archetype.moveEntity()`
- **Component Removal**: `EntityCommands.remove<T>()` → `RemoveComponentCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_removeComponent()` → validates entity → `EntityMigrationSystem.migrateRemoveComponent()` → `Archetype.moveEntity()`
- **Batch Component Addition**: `WorldCommands.batchAddExtensionComponents(entities, specs)` → `BatchAddExtensionComponentsCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_batchAddExtensionComponents()` → `addComponentsToEntitiesUnified()` → `_addComponentsToEntities()` → unified archetype resolution → batch entity addition → batch extension component initialization
- **Batch Component Removal**: `WorldCommands.batchRemoveComponents(entities, componentIds)` → `BatchRemoveComponentsCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_batchRemoveComponents()` → groups entities by archetype → batch removal per archetype group → `EntityMigrationSystem.migrateRemoveComponent()` for each
- **Despawn**: `WorldCommands.despawn(entity)` / `EntityCommands.despawn()` → `DestroyEntityCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_destroyEntity()` → `Archetype.removeEntity()`

### Query Execution

**Flow**: `ComponentQuery.iter1<T>()` → `world.ensureFlushed()` → `ComponentRegistry.getComponentId<T>()` → `ComponentMask.fromIds([componentId])` → `QueryCache.getOrCompute(queryMask, archetypes)` → `QueryCache._computeMatching(queryMask, registry)` → iterates `registry.all` → checks `archetype.matches(queryMask)` → `_QueryIterator1Column` → for each archetype: `archetype.getColumn(componentId)` → `world.components.componentFacadeRegistry.initializeColumn(componentId, column)` (when switching) → `ComponentFacade` creation

**Query Extension Methods**: `WorldQueryX` provides convenient query methods:

- `world.query<T>()` → `ComponentQuery.fromWorld(world).withType<T>().iter1<T>()` → returns `(WorldEntity, T)` tuples
- `world.query2-6<T1...T6>()` → `ComponentQuery.fromWorld(world).withType<T1>()...withType<T6>().iter2-6<T1...T6>()` → returns `(WorldEntity, T1...T6)` tuples
- `world.queryExt<TComp, TExt>()` → `ComponentQuery.fromWorld(world).withType<TComp>().iterExt1<TComp, TExt>()` → returns `(WorldEntityExtension, TExt)` with explicit extension types
- `world.queryExt2-4<TComp, TExt...>()` → `ComponentQuery.fromWorld(world).withType<TComp>()...iterExt2-4<TComp, TExt...>()` → returns `(WorldEntityExtension, TExt...)` tuples
- `world.queryExtWhere<TComp, TExt>(predicate)` → `ComponentQuery.fromWorld(world).withType<TComp>().iterExt1Where<TComp, TExt>(predicate)` → returns filtered `(WorldEntityExtension, TExt)` tuples
- `world.queryExt2Where<TComp, TExt, T2Comp, T2Ext>(predicate)` → `ComponentQuery.fromWorld(world).withType<TComp>().withType<T2Comp>().iterExt2Where<TComp, TExt, T2Comp, T2Ext>(predicate)` → returns filtered `(WorldEntityExtension, TExt, T2Ext)` tuples
- `world.queryMut<T>()` → `ComponentQuery.fromWorld(world).withType<T>().iterMut1<T>()` → returns `(WorldEntityMut, T)` for mutable access
- `world.queryMut2-4<T1...T4>()` → `ComponentQuery.fromWorld(world).withType<T1>()...iterMut2-4<T1...T4>()` → returns `(WorldEntityMut, T1...T4)` tuples
- `world.queryBuilder()` → `ComponentQueryBuilder` → advanced query construction with `withComponent()` / `withoutComponent()` → `build()` returns `ComponentQuery`
- All query methods automatically call `world.ensureFlushed()` before querying

**Query Variants**:

- **Standard Queries**: `ComponentQuery.iter1/2/3/4/5/6()` for 1-6 component queries returning `(WorldEntity, Component...)` tuples
- **Conditional Queries**: `ComponentQuery.iter1Where<T>(predicate)` for filtered single component queries
- **Mutable Queries**: `ComponentQuery.iterMut1/2/3/4()` for mutable queries returning `(WorldEntityMut, Component...)` tuples
- **Extension Type Queries**: `ComponentQuery.iterExt1/2/3/4()` for explicit extension type queries returning `(WorldEntityExtension, ExtensionType...)` tuples
- **Conditional Extension Queries**: `ComponentQuery.iterExt1Where/2Where<TComp, TExt>(predicate)` for filtered extension type queries
- **Query Builder**: `ComponentQueryBuilder` with `withComponent()` / `withoutComponent()` for advanced query construction

**Archetype Matching Cache**: `QueryCache.getOrCompute(requiredMask, archetypes)` → checks `_archetypeCache[ComponentMask]` → if miss: `ArchetypeMatchResult._compute(mask, archetypes)` → iterates `registry.all` → checks `archetype.matches(queryMask)` → creates `ArchetypeMatchResult(matchingArchetypes)` → caches `ComponentMask → ArchetypeMatchResult` → evicted by `ArchetypeRegistry.onArchetypeChange()` on new archetype creation

**Query Result Cache**: `QueryCache.getCachedResult(key, archetypes, computeResult)` → creates `QueryCacheKey(mask, predicate)` → checks `QueryResultCache.get(key)` → validates `QueryCacheEntry.isValid(flushVersion, archetypeVersion)` → checks `QueryStructuralTouchTracker.maskWasTouched(mask)` → if miss or stale: computes result → `QueryResultCache.put(key, entities)` → creates `QueryCacheEntry(entities, flushVersion, archetypeVersion)` → LRU eviction if cache exceeds `maxCacheSize` → evicted by `World.evictQueriesForStructuralComponent()` or `QueryCache.onArchetypeChange()` or `QueryCache.onWorldFlush()`

**Structural Query Eviction**: `QueryCache.evictForStructuralComponent(componentId)` → `QueryCache.markStructurallyTouched(componentId)` → `QueryResultCache.markStructurallyTouched(componentId)` → `QueryStructuralTouchTracker.markTouched(componentId)` → on next query: `QueryResultCache.get(key)` checks `_structuralTouches.maskWasTouched(key.mask)` → removes cache entries where mask contains the structurally touched component → used by `CommandQueue` after component add/remove operations → more efficient than full eviction

**Version-Based Invalidation**: `QueryResultCache.onArchetypeChange()` → increments `_archetypeVersion` → evicts all cached entries → `QueryResultCache.onWorldFlush()` → increments `_flushVersion` → clears `QueryStructuralTouchTracker` → entries validated via `QueryCacheEntry.isValid(flushVersion, archetypeVersion)` → ensures cache consistency

**Hot Path**: `_QueryIterator1Column.moveNext()` → factory from `world.components.componentFacadeRegistry` (zero allocation facade creation) → increments `_entityIndex` → Column initialized only when switching archetypes via `initializeColumn()` → `createFacadeForQuery()` handles both extension types and ObjectColumn components

**Mutable Queries**: `ComponentQuery.iterMut1<T>()` → returns `(WorldEntityMut, T)` tuples → `WorldEntityMut` provides direct mutation API → `_QueryIteratorMut1` uses `world.getEntityMut()` → returns facades for in-place mutation → `iterMut2-4()` supports 2-4 component mutable queries

**Extension Type Queries**: `ComponentQuery.iterExt1<TComp, TExt>()` → validates extension type matches registered type → returns explicit extension type facades → eliminates runtime casting overhead → `iterExt2-4()` supports 2-4 component extension type queries → `iterExt1Where/2Where()` adds predicate filtering for zero-allocation conditional queries

**Query Builder Pattern**: `ComponentQueryBuilder` → `withComponent(componentId)` / `withoutComponent(componentId)` → `build()` returns `ComponentQuery` → enables advanced query construction with explicit component inclusion/exclusion → supports complex query patterns beyond simple type-based queries

### System Execution

**Update**: `Schedule.run()` → `Schedule._resolveOrder()` → `DirectedGraph.topologicalOrdering()` → `Schedule._groupByDependencyLevel()` → `SystemExecutor.executeSchedule()` → executes systems grouped by dependency level → `SystemDescriptor.system(world)` → `System.execute()` → `ComponentQuery` → iterate facades

**Dependency Resolution**: `Schedule._resolveOrder()` → builds `DirectedGraph` from `runAfter`/`runBefore` dependencies → `DirectedGraph.isAcyclic()` checks for cycles → throws `CircularDependencyError` with cycle path if detected → `DirectedGraph.topologicalOrdering()` returns ordered system indices → `Schedule._groupByDependencyLevel()` groups systems for parallel execution → `_executionGroups` cached until schedule changes

**Execution Modes**: `SystemExecutor` supports three execution modes:

- **Sequential**: `ExecutionMode.sync` or `ExecutionMode.async` → systems execute one at a time in dependency order
- **Parallel**: `ExecutionMode.asyncParallel` with `canRunInParallel=true` → systems in same dependency level execute concurrently via `Future.wait()`
- **Isolate Placeholder**: `ExecutionMode.isolate` → `SystemExecutor._executeInIsolate()` → validates `isolateConfig` → currently executes on the main owner synchronously until deterministic isolate boundaries are implemented
- **Certified Jobs**: `Schedule.addJobSystem()` → `SystemDescriptor.jobSystem` → sync schedules call `runSerial()`; async schedules call `runAsync()` → `ScheduleExecutionPolicyResource` selects `serial`, `deterministic`, or `bestEffort` → `ScheduleJobResultQueueResource` carries frame-stamped best-effort results across frame boundaries

**Parallel Execution**: `Schedule.parallel([systems])` → `SystemDescriptor.mode = ExecutionMode.asyncParallel` → `SystemDescriptor.canRunInParallel = true` → systems grouped by dependency level → `Future.wait(parallel.map((desc) => desc.system(world)))`

### Resource Management

**Upsert Flow**: `WorldCommands.upsertResource<T>(resource)` → `UpsertResourceCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `ResourceRegistry.push(resource)` → adds to `pendingPush` queue → `ResourceRegistry.flush()` → `ResourceRegistry.flushToUpsert()` → processes `pendingPush` queue → stores resource in `_resources` map

**Removal Flow**: `WorldCommands.removeResource<T>()` → `DeleteResourceCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `ResourceRegistry.removeByType(Type)` → adds to `pendingRemove` queue → `ResourceRegistry.flush()` → `ResourceRegistry.flushToRemove()` → processes `pendingRemove` queue → removes resource from `_resources` map

**Access Flow**: `World.getResource<T>()` → `WorldResourceX.getResource<T>()` → `ResourceRegistry.get<T>()` → `world.ensureFlushed()` → checks `ResourceRegistry.doesNeedFlush` (checks `pendingPush.isNotEmpty || pendingRemove.isNotEmpty`) → conditional flush if needed → returns resource from `_resources` map

**Flush Check**: `ResourceRegistry.doesNeedFlush` → checks if `pendingPush.isNotEmpty || pendingRemove.isNotEmpty` → used by `World.ensureFlushed()` to determine if flush is needed → enables efficient auto-flushing at access points

**Direct Access**: `WorldResourceX.upsertResource<T>(resource)` → `ResourceRegistry.push(resource)` → adds to `pendingPush` → requires manual `world.flushResourcesOnly()` or auto-flush on next access

**Direct Removal**: `WorldResourceX.removeResource<T>()` → `ResourceRegistry.remove<T>()` → adds to `pendingRemove` → requires manual `world.flushResourcesOnly()` or auto-flush on next access

### Plugin System

**Installation**: `PluginRegistry.add(plugin)` → `Plugin.install(world)` → explicit registration (`registerObjectComponent`/`registerSoAComponent`/`registerTagComponent`/`registerExtension`) → assigns `ComponentId` → register facade/column factories → `world.schedule(name).add(system)`

**Component Registration**: `world.components.registerObjectComponent<Position>()` (or `registerSoAComponent` / `registerTagComponent` / `registerExtension`) → `ComponentRegistry` assigns `ComponentId(_nextId++)` → stores `Type → ComponentId` → register `ComponentFacadeFactory` (extension path) → register `ColumnFactory` → component ready

### Entity Migration

**Add Component Flow**: `CommandQueue._upsertComponent()` → validates entity → resolves current archetype via `ArchetypeResolver.resolveArchetype()` → if component exists: updates in-place via `ComponentDataWriter.writeToColumn()` → if component missing: computes new signature via `SignatureComputer.computeAddSignature()` → resolves destination archetype via `ArchetypeResolver.resolveDestinationArchetype()` → `EntityMigrator.migrateEntity()` → copies existing component data → `ComponentDataWriter.writeToColumn()` → `ExtractorRegistry.getExtractorFor()` → `ComponentDataExtractor.extractFloats/Int/Object()` → writes new component data → updates `Entities` location tracking → evicts query cache entries shaped by the component

**Unified Component Addition Flow**: `CommandQueue.addComponentsToEntitiesUnified()` → `_addComponentsToEntities()` → single archetype resolution for all entities via `_createArchetypeForComponents()` → for fresh entities: batch entity addition via `archetype.addEntities()` → batch location setting via `Entities.setLocationBatch()` → for existing entities: migration path via `EntityMigrationSystem.migrateAddComponent()` → if bundle provided: `_batchWriteClassComponents()` (writes class component data) → `_initializeExtensionComponentsBatch()` (initializes extension components) → batch structural cache eviction per component → handles both fresh entities (direct addition) and existing entities (migration path) → foundation for all component addition operations

**Remove Component Flow**: `CommandQueue._removeComponent()` → validates entity → resolves current archetype → computes new signature via `SignatureComputer.computeRemoveSignature()` → resolves destination archetype → `EntityMigrator.migrateEntity()` → copies existing component data (excluding removed) → uses swap-and-pop for efficient removal → updates `Entities` location tracking → evicts query cache entries shaped by the component

**Zero-Initialized Component Flow**: `CommandQueue.upsertComponentZeroInitialized()` → resolves archetype → computes new signature → gets/creates destination archetype → `EntityMigrator.migrateEntity()` with null data → column already zero-initialized → `ComponentFacadeRegistry.initializeColumn()` → returns facade → no data copying needed

**Swap-and-Pop**: `Archetype.removeEntity()` → moves last entity to removed slot → updates location tracking for moved entity → maintains dense arrays → preserves cache locality → O(1) removal cost

### Column Creation

**Flow**: `ArchetypeRegistry.getOrCreateArchetype(signature)` → for each `ComponentId` in signature: `ComponentRegistry.createColumnFor(Type)` → `ComponentRegistry.getComponentIdByType(Type)` → `ComponentRegistry._columnFactoryRegistry.createColumn(componentId)` → `ColumnFactoryRegistry` looks up `ColumnFactory` for `componentId` → `ColumnFactory.createColumn(componentId)` → returns `FloatColumn` / `IntColumn` / `Uint8Column` / `ObjectColumn` → `Archetype.addColumn(componentId, column)` → `QueryCache.invalidate()` → register archetype

**Factory Chain**: `ComponentRegistry` has reference to `ColumnFactoryRegistry` → `ColumnFactoryRegistry` manages `Map<ComponentId, ColumnFactory>` → `ColumnFactory` creates appropriate column type based on component characteristics → columns stored in `Archetype._columns` map

### Entity Wrappers

- **WorldEntity**: `World.getEntity()` → validates entity → provides structural change API (`despawn`, `toMut()`, `toExtension()`) → can convert to `WorldEntityMut` or `WorldEntityExtension`
- **WorldEntityMut**: `World.getEntityMut()` → validates entity → provides direct mutation API (`getMut<T>()`, `getMut2<T1, T2>()`, `getMut3<T1, T2, T3>()`, `hasFast<T>()`) → returns actual component objects for in-place mutation → can convert to `WorldEntity` or `WorldEntityExtension`
- **WorldEntityExtension**: `World.getEntityExtension()` → validates entity → provides extension type facade access (`getExtension<TComponent, TExtension>()`, `create<TComponent, TExtension>()`) → `create()` creates zero-initialized component if missing → returns extension type facades (zero-cost) → can convert to `WorldEntity` or `WorldEntityMut`

### Auto-Flush System

**Trigger**: `ComponentQuery.iter1/2/3/4/5/6()` or `ComponentQuery.iterMut1/2/3/4()` or `ResourceRegistry.get<T>()` → `world.ensureFlushed()` → checks `world.isFlushing` (return early if true, prevents recursion) → checks `resources.doesNeedFlush || commandQueue.needsFlush` → if true: `World.flush()`

**Execution**: `World.flush()` → sets `isFlushing = true` → `flushEntitiesOnly()` (no-op, API consistency) → `flushComponentsOnly()` (no-op, API consistency) → `flushResourcesOnly()` → `ResourceRegistry.flush()` → processes `pendingPush` and `pendingRemove` queues → `flushCommandsOnly()` → `CommandQueue.execute()` → processes all pending commands → conditional second flush if `resources.doesNeedFlush` (commands may have pushed new resources) → sets `isFlushing = false`

**Rationale**: Resources flushed before commands (commands may access resources) → Commands execute last → conditional second flush ensures deferred operations are visible → `isFlushing` flag prevents recursive flush-during-flush cycles

### Phase Systems

**Execution**: `Schedule.run()` → `SystemExecutor.executeSchedule()` → phase systems (`flushAllSystem`, `flushEntitiesSystem`, `flushComponentsSystem`, `flushResourcesSystem`, `flushCommandsSystem`) → `World.flush*()` methods

**Conditional**: Each phase system checks `doesNeedFlush` / `needsFlush` before executing → only flushes if pending changes exist

### Schedule Triggers

**EveryFrame**: `EveryFrame.shouldRun()` → returns `true` (runs every frame)

**EveryNFrames**: `EveryNFrames.shouldRun()` → increments counter → returns `true` every N frames

**EveryNSeconds**: `EveryNSeconds.shouldRun()` → uses `world.getResource<ScheduleTimeResource>().deltaSeconds` (preferred), `DeltaTimeResource` (compatibility adapter), or explicit `WallClockScheduleTimeResource` → accumulates time → returns `true` when interval reached → throws `ScheduleTimeSourceMissingError` if no time source exists

**ConditionTrigger**: `ConditionTrigger.shouldRun(world)` → evaluates custom condition function `(World) → bool`

**EventTrigger**: `EventTrigger<T>.shouldRun(world)` → calls `hasEvents(world)` function → typically `world.events.reader<T>().isNotEmpty` → checks `EventChannel.length > 0` → returns `true` if events present → schedule executes only when events exist → efficient O(1) check → throws `EventTriggerValidationError` if channel not registered → can combine with `ThrottledTrigger` for rate limiting

**ThrottledTrigger**: `ThrottledTrigger.shouldRun()` → checks if `minIntervalSeconds` elapsed since last execution → if base trigger fires, updates timestamp → prevents CPU overload from tight loops

**ManualTrigger**: `ManualTrigger.shouldRun()` → returns `true` (default for schedules without explicit triggers)

### Multiple Schedules

**Creation**: `world.createSchedule(name, trigger: trigger)` → `SystemsRegistry.createSchedule()` → stores in `ScheduleMap<String, Schedule>`

**Access**: `world.schedule(name)` → retrieves named schedule → `world.getOrCreateSchedule(name)` → creates if missing

**Execution**: `world.schedule('HighFrequency').run()` → `Schedule.run()` → checks trigger → executes systems if `trigger.shouldRun(world)`

**Common Patterns**: `HighFrequency` (EveryFrame), `MediumFrequency` (EveryNSeconds(0.3)), `LowFrequency` (EveryNSeconds(2.5)), `AIFrequency` (EveryNSeconds(0.5)), `Particles` (EveryFrame), `Monitoring` (EveryFrame)

### Event System

**Registration Flow**: `world.events.register<T>(capacity, capacityPolicy, fromNumericFieldsFactory, sampleEvent, stride)` → `EventRegistry.register()` → validates TypedDataEvent (if factory provided) → `TypedDataEventRegistry.register<T>(stride)` → `EventChannelFactory.create<T>()` → creates `EventChannel<T>` with `DataColumn` (FloatColumn/IntColumn/ObjectColumn) → `world.resources.push(EventChannel<T>)` → channel stored as resource

**TypedDataEvent Registration**: For events implementing `TypedDataEventMixin` → validates `sampleEvent` implements mixin → calculates stride from `sampleEvent.numericFields.length` → validates factory function by creating test event → ensures factory-produced event has matching stride and numericFields → registers type in `TypedDataEventRegistry` → enables FloatColumn/IntColumn storage for performance

**Event Send Flow**: `world.events.writer<T>().send(event)` → `EventWriter.send()` → `EventChannel.send()` → checks capacity → handles overflow policy (dropNew/dropOld/throwOnOverflow) → `EventColumnMapper.storeEvent()` → extracts numericFields (if TypedDataEvent) → stores to FloatColumn/IntColumn/ObjectColumn → updates ring buffer indices (\_tail, \_length)

**Event Read Flow**: `world.events.reader<T>().iter()` → `EventReader.iter()` → `EventChannel.readEvent(index)` → `EventColumnMapper.loadEvent()` → loads from FloatColumn/IntColumn/ObjectColumn → reconstructs event via `fromNumericFieldsFactory` (if TypedDataEvent) → returns event → snapshot semantics (events sent after iterator creation not visible)

**SIMD Event Iteration**: `EventReader.iterSimd()` → returns `FloatColumnEventIterator` (if FloatColumn) → provides direct `Float32List` access to numeric fields → enables SIMD processing without object allocation → only available for FloatColumn events

**Event Clear Flow**: `world.events.clearAll()` → `EventRegistry.clearAll()` → iterates `world.resources.iter<EventChannel>()` → `EventChannel.clear()` → for TypedData columns: O(1) reset indices → for ObjectColumn: O(length) null out references → maintains frame-bound lifecycle

**Event-Driven Schedules**: `world.createSchedule('Name', trigger: EventTrigger<T>((world) => world.events.reader<T>().isNotEmpty))` → `EventTrigger.shouldRun()` → checks `EventChannel.length > 0` → schedule executes only when events present → efficient O(1) check → can combine with `ThrottledTrigger` for rate limiting

**Event Lifecycle**: Events sent during frame → read during frame → cleared at end of frame via `eventClearSystem` → frame-bound semantics ensure events don't persist between frames → `EventPlugin` provides core infrastructure → `eventClearSystem` should be last system in schedule

### Plugin System

**Installation**: `world.addPlugin(plugin)` → `plugin.install(world)` → registers components/facades/factories → adds systems to schedules → flushes world

**Game2DPlugin**: Registers `PositionComponent`, `VelocityComponent`, `SizeComponent`, `HealthComponent`, `PathfindingComponent` → creates facade/column factories → enables SIMD operations

**DebugPlugin**: Registers `PerformanceResource`, `SpawnPerformanceResource` → adds `performanceSystem` to schedule → collects fps/frameTime/entityCount metrics

**EventPlugin**: Provides `world.events` extension → enables event system → no default resources/systems (users register what they need) → `eventClearSystem` should be added manually to schedules

**Uninstallation**: `world.removePlugin(name)` → `plugin.uninstall(world)` → unregisters factories → removes systems → flushes world

### SIMD Operations

**Column SIMD Views**: `FloatColumn.simdView` → `Float32x4List` view of `Float32List` data → enables vectorized operations

**Movement System**: `movementSystemSimd(world)` → `world.ensureFlushed()` → get component IDs → create mask → find archetypes → for each archetype: cast columns to `FloatColumn` → `updatePositionSimd(positionColumn, velocityColumn, dt)`

**SIMD Patterns**: `updatePositionSimd()` (pos += vel _ dt), `calculateDistancesSimd()` (sqrt(dx² + dy²)), `normalizeVectorsSimd()` (vec / magnitude), `scalePositionsSimd()` (pos _= scale)

**Performance**: Processes 2 positions per SIMD vector (Float32x4 = 4 floats = 2 positions with stride 2) → significant speedup for math-heavy systems

### World Extensions

**Component Access**: `world.getComponent<T>(entity)` → `WorldComponentX.getComponent<T>()` → `ensureFlushed()` → validate entity → get location → get archetype → `archetype.getComponentByEntity<T>()`

**Entity Management**: `world.getEntity(entity)` → `WorldEntityX.getEntity()` → `(WorldEntity, isValid)` → provides structural API → `world.getEntityMut(entity)` → provides mutation API → `world.getEntityExtension(entity)` → provides extension wrapper

**Query Extensions**:

- `world.query<T>()` → `WorldQueryX.query<T>()` → `ComponentQuery.fromWorld(world).withType<T>().iter1<T>()` → returns `(WorldEntity, T)` tuples → automatically calls `ensureFlushed()`
- `world.query2-6<T1...T6>()` → `WorldQueryX.query2-6<T1...T6>()` → `ComponentQuery.fromWorld(world).withType<T1>()...withType<T6>().iter2-6<T1...T6>()` → returns `(WorldEntity, T1...T6)` tuples
- `world.queryExt<TComp, TExt>()` → `WorldQueryX.queryExt<TComp, TExt>()` → `ComponentQuery.fromWorld(world).withType<TComp>().iterExt1<TComp, TExt>()` → returns `(WorldEntityExtension, TExt)` with explicit extension types → eliminates runtime casting
- `world.queryExt2-4<TComp, TExt...>()` → `WorldQueryX.queryExt2-4<TComp, TExt...>()` → `ComponentQuery.fromWorld(world).withType<TComp>()...iterExt2-4<TComp, TExt...>()` → returns `(WorldEntityExtension, TExt...)` tuples
- `world.queryExtWhere<TComp, TExt>(predicate)` → `WorldQueryX.queryExtWhere<TComp, TExt>(predicate)` → `ComponentQuery.fromWorld(world).withType<TComp>().iterExt1Where<TComp, TExt>(predicate)` → returns filtered `(WorldEntityExtension, TExt)` tuples
- `world.queryExt2Where<TComp, TExt, T2Comp, T2Ext>(predicate)` → `WorldQueryX.queryExt2Where<TComp, TExt, T2Comp, T2Ext>(predicate)` → `ComponentQuery.fromWorld(world).withType<TComp>().withType<T2Comp>().iterExt2Where<TComp, TExt, T2Comp, T2Ext>(predicate)` → returns filtered `(WorldEntityExtension, TExt, T2Ext)` tuples
- `world.queryMut<T>()` → `WorldQueryX.queryMut<T>()` → `ComponentQuery.fromWorld(world).withType<T>().iterMut1<T>()` → returns `(WorldEntityMut, T)` for mutable access → allows structural changes during iteration
- `world.queryMut2-4<T1...T4>()` → `WorldQueryX.queryMut2-4<T1...T4>()` → `ComponentQuery.fromWorld(world).withType<T1>()...iterMut2-4<T1...T4>()` → returns `(WorldEntityMut, T1...T4)` tuples
- `world.queryBuilder()` → `WorldQueryX.queryBuilder()` → `ComponentQueryBuilder(world)` → `withComponent()` / `withoutComponent()` → `build()` returns `ComponentQuery` → advanced query construction

**Resource Management**: `world.getResource<T>()` → `WorldResourceX.getResource<T>()` → `resources.get<T>()` → `world.removeResource<T>()` → deferred removal → `world.upsertResource<T>(resource)` → deferred upsert

**Plugin Management**: `world.addPlugin(plugin)` → `WorldPluginX.addPlugin()` → flush + install → `world.getPlugin(name)` → access → `world.hasPlugin(name)` → check → `world.removePlugin(name)` → flush + uninstall

**Schedule Management**: `world.createSchedule(name, trigger)` → `WorldScheduleX.createSchedule()` → new schedule → `world.getOrCreateSchedule(name)` → get/create → `world.schedule(name)` → access → `world.hasSchedule(name)` → check → `world.runSchedule(name)` → execute → `world.runScheduleAsync(name)` → async execution → `world.runSystem(system)` → direct system execution → `world.runSystemAsync(system)` → async system execution

**Flush Operations**: `world.flush()` → `WorldFlushX.flush()` → full flush → `world.flushResourcesOnly()` → resources only → `world.flushCommandsOnly()` → commands only → `world.ensureFlushed()` → conditional auto-flush

### World Initialization

**Order**: `World()` → `Entities()` → `ComponentRegistry()` → `CommandQueue(world: this)` → `ResourceRegistry(world: this)` → `QueryCache()` → `ArchetypeRegistry(componentRegistry, queryCache)`

**Dependency Chain**: `ArchetypeRegistry` depends on `ComponentRegistry` (column creation) and `QueryCache` (invalidation) → initialized last

### Batch Operations

**Batch Spawn**: `World.batchSpawn(bundle, count)` → `World.commands.batchSpawn()` → `WorldCommands.batchSpawn()` → `BatchSpawnCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `CommandQueue._batchSpawnEntities()` → separates class components from extension components → builds unified component signature (class + extension components) → `ArchetypeRegistry.getOrCreateArchetype(signature)` → pre-allocates `count` entity IDs via `Entities.create()` (batch allocation) → `archetype.addEntities(List<Entity>)` (batch entity addition) → `Entities.setLocationBatch(List<Entity>, List<EntityLocation>)` (batch location setting) → `CommandQueue._batchWriteClassComponents()` (writes same component data to all entities) → `CommandQueue._batchInitializeExtensionComponents()` (zero-initialized, column initialization only via `ComponentFacadeRegistry.initializeColumn()`) → structural cache eviction per component via `QueryCache.evictForStructuralComponent()` → optimized for large-scale spawning (100-10000 entities)

**Batch Add Extension Components**: `World.commands.batchAddExtensionComponents(entities, componentSpecs)` → `WorldCommands.batchAddExtensionComponents()` → `BatchAddExtensionComponentsCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_batchAddExtensionComponents()` → converts component specs `(Type, Type)` to component IDs → creates `ComponentBundle` (empty class components, extension components) → `addComponentsToEntitiesUnified()` → uses unified bundle-first component addition → optimized for adding zero-initialized extension components to multiple entities

**Batch Add Class Components**: `World.commands.batchAddClassComponents(entities, components)` → `WorldCommands.batchAddClassComponents()` → `BatchAddClassComponentsCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_batchAddClassComponents()` → groups entities by component type → creates bundles per component type → `addComponentsToEntitiesUnified()` → optimized for adding class components with data to multiple entities

**Batch Remove Components**: `World.commands.batchRemoveComponents(entities, componentIds)` → `WorldCommands.batchRemoveComponents()` → `BatchRemoveComponentsCommand` → `CommandQueue.push()` → `CommandQueue.execute()` → `_batchRemoveComponents()` → groups entities by current archetype → processes removals in batch within each archetype group → `EntityMigrationSystem.migrateRemoveComponent()` for each entity → batch structural cache eviction → optimized for removing components from multiple entities

**Pre-register Archetypes**: `World.preRegisterArchetypesForBundles(bundles)` → builds signatures from bundles → `ArchetypeRegistry.preRegisterArchetypes(signatures)` → creates all archetypes upfront → only evicts cache once if any new archetypes created → avoids cache evictions during batch spawn → optimizes large-scale spawning → call before batch spawning entities with known component combinations

**Zero-Initialized Component Creation**: `WorldEntityExtension.create<TComponent, TExtension>()` → validates extension type matches registered type → checks if component exists (read-only check) → if exists: returns facade via `getExtension()` → if missing: ensures flush → `world.commandQueue.batchAddExtensionComponents([entity], [(TComponent, TExtension)])` → `CommandQueue.batchAddExtensionComponents()` → `BatchAddExtensionComponentsCommand` → `CommandQueue.execute()` → `_batchAddExtensionComponents()` → converts component specs to component IDs → creates `ComponentBundle` (empty class components, extension components) → `addComponentsToEntitiesUnified()` → `_addComponentsToEntities()` → unified archetype resolution → batch entity addition → `_initializeExtensionComponentsBatch()` → `ComponentFacadeRegistry.initializeColumn()` → flush → returns facade via `getExtension()`

### Query Cache Structural Eviction

**Full Cache Eviction**: `ArchetypeRegistry.getOrCreateArchetype()` → `QueryCache.invalidate()` → increments version → all cached queries become stale

**Structural Component-Touch Eviction**: `CommandQueue._upsertComponent()` / `CommandQueue._removeComponent()` → `QueryCache.evictForStructuralComponent(componentId)` → removes cache entries where `mask.has(componentId)` → only queries containing that component are evicted

**Pattern-Based Eviction**: `QueryCache.invalidateMatching(pattern)` → removes cache entries where `mask.intersects(pattern)` → evicts queries matching component pattern

**Cache Validation**: `QueryCache.getOrCompute()` → checks `CachedQueryResult.isValid(version)` → if valid: checks staleness via `_isStale()` (verifies archetypes still exist) → if stale: removes entry and recomputes → LRU eviction when cache exceeds `maxCacheSize`

## Error Handling

### Error Types

| Type                             | Category  | Description                                 |
| -------------------------------- | --------- | ------------------------------------------- |
| `EntityNotFoundError`            | Error     | Entity doesn't exist or not alive           |
| `ComponentNotFoundError`         | Error     | Component not found for entity              |
| `ComponentNotRegisteredError`    | Error     | Component type not registered               |
| `ArchetypeNotFoundError`         | Error     | Archetype not found                         |
| `CircularDependencyError`        | Error     | System schedule has circular dependencies   |
| `IteratorNotReadyError`          | Error     | Iterator used incorrectly                   |
| `SystemConfigurationError`       | Error     | Invalid system configuration                |
| `ComponentRegistrationException` | Exception | Component registration failed (recoverable) |
| `PluginInstallationException`    | Exception | Plugin installation failed (recoverable)    |

**Errors (EcsStateError)**: Programming mistakes, typically not caught.  
**Exceptions (EcsException)**: Recoverable conditions, can be caught and handled.

### Error Propagation

- **Entity Operations**: `World.getComponent()` → validates entity → throws `EntityNotFoundError` → validates component → throws `ComponentNotFoundError`
- **Component Access**: `ComponentRegistry.getComponentId()` → throws `ComponentNotRegisteredError` if type not registered
- **Query Operations**: Query iterators validate state → throw `IteratorNotReadyError` if used incorrectly
- **System Scheduling**: `Schedule._resolveOrder()` → detects cycles → throws `CircularDependencyError` with cycle path
- **Command Execution**: `CommandQueue.execute()` → validates entities/components → throws appropriate errors before processing
- **Plugin Operations**: `PluginRegistry.add()` → validates plugin → throws `PluginInstallationException` if installation fails
- **Migration**: Inherits error handling from `CommandQueue.execute()` → validates entities and component registration
- **Column Creation**: `ComponentRegistry.createColumnFor()` → throws `ComponentNotRegisteredError` if type not registered
- **Initialization**: Throws `EcsStateError` for configuration issues, `ComponentRegistrationException` for recoverable registration failures

### Best Practices

- **Pre-validation**: Use `World.entities.isAlive()` and `WorldEntity.hasFast()` before accessing components
- **Component Registration**: Register all components before use to avoid `ComponentNotRegisteredError`
- **Query Iterators**: Always check iterator state before accessing `current` property
- **System Dependencies**: Ensure system dependencies form a DAG to avoid `CircularDependencyError`
- **Exception Handling**: Catch `EcsException` types for recoverable errors (plugin installation, component registration)

## Performance Critical Paths

- **Hot Loop**: `System` → `ComponentQuery.iter1/2/3/4/5/6()` → `world.ensureFlushed()` (<5% overhead) → `QueryCache.getOrCompute()` → `_QueryIterator1Column` → `ComponentFacadeRegistry.createFacadeWithoutInit()` (zero allocation) → direct TypedData access
- **Cache Locality**: Archetype groups entities → SoA layout → `Float32List`/`Int32List` → SIMD-friendly stride alignment
- **Zero Allocation**: Facades are extension types → `createFacadeWithoutInit()` avoids redundant static writes → no heap allocation
- **Query Caching**: `QueryCache` maintains dual cache system:
  - **Archetype Matching Cache**: `_archetypeCache` stores `ComponentMask → ArchetypeMatchResult` → `ArchetypeMatchResult` contains only `matchingArchetypes` (no eager entity list) → `getOrCompute()` checks cache → if miss: computes via `ArchetypeMatchResult._compute()` (iterates `registry.all`, checks `archetype.matches()`) → caches result → evicted by `ArchetypeRegistry.onArchetypeChange()` on new archetype creation
  - **Query Result Cache**: `QueryResultCache` stores `QueryCacheKey → QueryCacheEntry` → `QueryCacheEntry` contains `entities`, `flushVersion`, and `archetypeVersion` → `getCachedResult()` validates versions and structural touch state → if miss or stale: computes result → caches entry → evicted by `World.evictQueriesForStructuralComponent()`, `onArchetypeChange()`, or `onWorldFlush()` → LRU eviction when cache exceeds `maxCacheSize` → `QueryStructuralTouchTracker` enables structural query eviction per component
- **Deferred Commands**: Structural changes deferred to `CommandQueue.execute()` → batch processing → single migration pass → prevents changes during iteration
- **Entity Migration**: Swap-and-pop maintains dense arrays → `Archetype.removeEntity()` moves last entity → updates location tracking → preserves cache locality
- **Query Iterator**: Column initialized only when switching archetypes → `initializeColumn()` called once per archetype → `createFacadeWithoutInit()` minimizes static writes
