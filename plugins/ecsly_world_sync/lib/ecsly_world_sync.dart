/// World-sync plugin for ecsly worlds: converts world event-channel events
/// and component deltas into convergence-kernel ops, and folds remote ops
/// back into a world-state projection.
///
/// Parents (this plugin and its consumers) choose merge strategies and
/// compaction policies from what the kernel exposes; the kernel never
/// learns about worlds. Real networking, presence, and rollback are later
/// phases and are deliberately absent here.
library;

export 'src/fake_transport.dart';
export 'src/world_projection.dart';
export 'src/world_sync.dart';
