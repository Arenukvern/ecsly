import 'dart:async';

/// One coordinator per storage namespace. Serializes operations within this
/// process only; storage adapters own durability and cross-process concurrency.
class CheckpointCoordinator {
  final _lanes = <String, _CheckpointLane>{};

  /// Startup reads join the same lane as saves, then refresh through the adapter.
  /// This does not acquire a viewer's mutation ownership.
  Future<String?> readSettled(String key, Future<String?> Function() read) =>
      _enqueue(key, _lanes.putIfAbsent(key, _CheckpointLane.new), read);

  Future<T> _enqueue<T>(
    String key,
    _CheckpointLane lane,
    Future<T> Function() action,
  ) {
    lane.pending++;
    final result = lane.tail.then((_) => action());
    lane.tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result.whenComplete(() {
      lane.pending--;
      _prune(key, lane);
    });
  }

  CheckpointHandle attach({
    required String key,
    required Future<bool> Function(String value) write,
    required Future<String?> Function() read,
  }) {
    final lane = _lanes.putIfAbsent(key, _CheckpointLane.new);
    if (lane.owner != null) throw StateError('Checkpoint already owned: $key');
    final handle = CheckpointHandle._(this, key, lane, write, read);
    lane.owner = handle;
    return handle;
  }

  void _prune(String key, _CheckpointLane lane) {
    if (lane.owner == null &&
        lane.pending == 0 &&
        identical(_lanes[key], lane)) {
      _lanes.remove(key);
    }
  }
}

class _CheckpointLane {
  CheckpointHandle? owner;
  int pending = 0;
  Future<void> tail = Future.value();
}

class CheckpointHandle {
  CheckpointHandle._(
    this._coordinator,
    this.key,
    this._lane,
    this._write,
    this._read,
  );
  final CheckpointCoordinator _coordinator;
  final String key;
  final _CheckpointLane _lane;
  final Future<bool> Function(String) _write;
  final Future<String?> Function() _read;
  bool get active => identical(_lane.owner, this);

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (!active) return Future.error(StateError('Checkpoint owner detached'));
    return _coordinator._enqueue(key, _lane, () async {
      if (!active) {
        throw StateError('Checkpoint owner replaced before dispatch');
      }
      final value = await action();
      if (!active) {
        throw StateError('Checkpoint owner replaced during operation');
      }
      return value;
    });
  }

  Future<bool> save(String value) => _enqueue(() => _write(value));
  Future<String?> load() => _enqueue(_read);

  void detach() {
    if (active) _lane.owner = null;
    _coordinator._prune(key, _lane);
  }
}

final previewCheckpoints = CheckpointCoordinator();
