/// Record and seek deterministic replay positions for [ecsly] worlds.
///
/// Uses [ecsly_serialization] snapshots keyed by [PersistentId]; harness
/// semantics (event ids, actors, parents) belong in opaque [ReplayEntry.eventKey]
/// values, not in this package.
library;

export 'src/checkpoint_store.dart';
export 'src/determinism.dart';
export 'src/fingerprint.dart';
export 'src/replay_codec.dart';
export 'src/replay_entry.dart';
export 'src/replay_log.dart';
export 'src/replay_player.dart';
export 'src/replay_recorder.dart';
