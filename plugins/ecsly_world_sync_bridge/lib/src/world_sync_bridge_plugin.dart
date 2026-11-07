import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:ecsly_world_sync/ecsly_world_sync.dart' show WorldSync;

import 'world_sync_bridge.dart';
import 'world_sync_session.dart';

/// World-bound sync state installed by [WorldSyncBridgePlugin].
class WorldSyncBridgeResource extends Resource {
  /// Creates the bundle; [session] is null when the host did not supply one.
  WorldSyncBridgeResource({
    required this.bridge,
    this.session,
  });

  /// The flush-boundary capture diff driving the replica.
  final WorldSyncBridge bridge;

  /// The anti-entropy session driver, when the host supplied one.
  final WorldSyncSession? session;
}

/// Plugin that binds a live [World] to a `WorldSync` replica (ADR 0002,
/// re-set on the session core by ADR 0004).
///
/// The host keeps ownership of both ends of the seam: it constructs the
/// replica (kernel identity, doc id, and merge strategy are the host's
/// choices) and, optionally, the session driver (transport and peers come
/// from the pairing layer). The plugin only wires them into the world:
///
/// ```dart
/// final sync = WorldSync(actorId: 'peer-a');
/// world.addPlugin(WorldSyncBridgePlugin(sync: sync));
///
/// // Every world.flush() now emits deltas into the replica.
/// // The projection is reachable through the resource:
/// final bridge = world
///     .getResource<WorldSyncBridgeResource>()
///     .bridge;
/// ```
///
/// With `attachFlushObserver: false` the bridge is installed inert and the
/// host calls [WorldSyncBridge.emitDeltas] on its own cadence.
class WorldSyncBridgePlugin extends Plugin {
  /// Creates the plugin around a host-built [sync] replica.
  WorldSyncBridgePlugin({
    required this.sync,
    this.session,
    this.codecs,
    this.clock,
    this.attachFlushObserver = true,
  });

  /// The replica this world feeds deltas and tombstones into.
  final WorldSync sync;

  /// Optional host-built anti-entropy session over the mesh radio.
  final WorldSyncSession? session;

  /// Object-component codecs forwarded to the capture.
  final ObjectComponentCodecRegistry? codecs;

  /// Clock override for deterministic HLCs in tests.
  final DateTime Function()? clock;

  /// Whether [install] attaches the flush observer immediately.
  final bool attachFlushObserver;

  @override
  String get name => 'ecsly_world_sync_bridge';

  @override
  void install(final World world) {
    final bridge = WorldSyncBridge(
      world: world,
      sync: sync,
      codecs: codecs,
      clock: clock,
    );
    if (attachFlushObserver) {
      bridge.attach();
    }
    world.upsertResource(
      WorldSyncBridgeResource(bridge: bridge, session: session),
    );
  }

  @override
  void uninstall(final World world) {
    final state = world.maybeGetResource<WorldSyncBridgeResource>();
    state?.session?.stop();
    state?.bridge.detach();
    world.resources.remove<WorldSyncBridgeResource>();
  }
}
