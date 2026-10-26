// The spies hold stream-wrapped sessions for the life of the fixture; the
// underlying controllers are dropped with it.
// ignore_for_file: close_sinks

import 'dart:typed_data';

import 'package:ecsly_world_sync_bridge/ecsly_world_sync_bridge.dart';
import 'package:test/test.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

MeshPeerRecord _recordOf(final String id) =>
    MeshPeerRecord(peerId: id, displayName: id);

/// One Position-column delta; the component tier is fixed so tests only
/// name the piece of state they exercise.
ComponentDelta _delta(
  final String entity,
  final String field,
  final Object? value,
) => ComponentDelta(
  entityKey: entity,
  component: 'Position',
  field: field,
  value: value,
);

/// Deterministic clock: each [next] call advances 1 ms from a fixed start.
final class _StepClock {
  DateTime _next = DateTime.utc(2026, 9, 26, 12);

  DateTime next() => _next = _next.add(const Duration(milliseconds: 1));
}

/// Clock the test moves by hand; the driver reads it through [now].
final class _ManualClock {
  DateTime _now = DateTime.utc(2026, 9, 26, 12);

  DateTime now() => _now;

  void advanceBy(final Duration duration) {
    _now = _now.add(duration);
  }
}

/// Transport spy: decodes every outbound frame, delegating to the wrapped
/// radio so the wire still flows. Sessions the peer dialed in are wrapped
/// too (tagged `accepted`), so both halves of a crossing exchange are
/// observable.
class _SpyTransport implements MeshTransport {
  _SpyTransport(this.inner);

  final MeshTransport inner;
  final sessions = <_SpySession>[];

  /// Broadcast-backed like the foundation's LAN radio, so the driver's
  /// stop/restart cycle can re-listen (a raw fake's single-subscription
  /// controller allows one listener ever).
  late final Stream<MeshSession> _incoming = inner.incoming.map((
    final session,
  ) {
    final spy = _SpySession(session, true);
    sessions.add(spy);
    return spy;
  }).asBroadcastStream();

  @override
  Stream<MeshSession> get incoming => _incoming;

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final spy = _SpySession(await inner.connect(peer), false);
    sessions.add(spy);
    return spy;
  }

  /// Every frame this side sent, across all its sessions, in order.
  List<Map<String, Object?>> get sentFrames => [
    for (final session in sessions) ...session.sentFrames,
  ];
}

class _SpySession implements MeshSession {
  /// [accepted] marks a session the peer dialed in (as opposed to this
  /// side dialing out).
  // ignore: avoid_positional_boolean_parameters - test-local constructor
  _SpySession(this._inner, this._accepted);

  final MeshSession _inner;
  final bool _accepted;
  final sentFrames = <Map<String, Object?>>[];

  /// Whether the peer dialed this session in (as opposed to this side
  /// dialing out).
  bool get accepted => _accepted;

  @override
  String get remotePeerId => _inner.remotePeerId;

  @override
  Stream<Uint8List> get inbound => _inner.inbound;

  @override
  Future<void> send(final Uint8List payload) {
    sentFrames.add(MeshSyncProtocol.decode(payload));
    return _inner.send(payload);
  }

  @override
  Future<void> close() => _inner.close();
}

/// One paired replica set under test: two replicas, two spying radios, two
/// session drivers listening for inbound sessions. Compaction triggers are
/// disabled unless a test opts in, so no test depends on the real clock.
final class _Fixture {
  _Fixture({
    this.maxLogOps,
    this.minInterval,
    final DateTime Function()? clock,
  }) : _clock = clock {
    final pair = FakeMeshPair.paired(a: 'a', b: 'b');
    spyA = _SpyTransport(pair.a);
    spyB = _SpyTransport(pair.b);
    syncA = WorldSync(actorId: 'a');
    syncB = WorldSync(actorId: 'b');
    driverA = WorldSyncSession(
      sync: syncA,
      transport: spyA,
      peerId: 'a',
      peers: {_recordOf('b')},
      maxLogOps: maxLogOps,
      minInterval: minInterval,
      clock: clock,
    );
    driverB = WorldSyncSession(
      sync: syncB,
      transport: spyB,
      peerId: 'b',
      peers: {_recordOf('a')},
      maxLogOps: maxLogOps,
      minInterval: minInterval,
      clock: clock,
    );
    driverA.listen();
    driverB.listen();
  }

  late final WorldSync syncA;
  late final WorldSync syncB;
  late final WorldSyncSession driverA;
  late final WorldSyncSession driverB;
  late final _SpyTransport spyA;
  late final _SpyTransport spyB;
  final int? maxLogOps;
  final Duration? minInterval;
  final DateTime Function()? _clock;

  /// Deterministic write time for [WorldSync] local ops.
  DateTime writeTime([final int step = 0]) {
    final next = _clock ?? _StepClock().next;
    var t = next();
    for (var i = 0; i < step; i++) {
      t = next();
    }
    return t;
  }

  /// Full round: both sides dial each other, then the event loop settles
  /// (responder halves finish in microtasks after sending their deltas).
  Future<void> drive() async {
    await driverA.tick();
    await driverB.tick();
    await _settle();
  }

  /// The most recent delta frame [spy] sent (any of its sessions).
  Map<String, Object?>? lastDeltaFrameOf(final _SpyTransport spy) {
    for (final frame in spy.sentFrames.reversed) {
      if (frame['type'] == MeshSyncProtocol.deltaType) {
        return frame;
      }
    }
    return null;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void _expectConverged(final WorldSync a, final WorldSync b) {
  expect(b.projection.values, a.projection.values);
  expect(b.vv.toJson(), a.vv.toJson());
}

void main() {
  test('an exchange speaks the session-core protocol: hello, vv, delta',
      () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), f.writeTime());
    f.syncA.applyDelta(_delta('ship:1', 'y', 2.5), f.writeTime());

    // One dial from A is enough for both halves to run: B accepts and
    // answers through the same symmetric script.
    await f.driverA.tick();
    await _settle();

    final initiator = f.spyA.sessions.singleWhere((final s) => !s.accepted);
    final responder = f.spyB.sessions.singleWhere((final s) => s.accepted);

    final initiatorTypes = [
      for (final frame in initiator.sentFrames) frame['type'],
    ];
    expect(initiatorTypes, [
      MeshSyncProtocol.helloType,
      MeshSyncProtocol.vvType,
      MeshSyncProtocol.deltaType,
    ]);
    final hello = initiator.sentFrames.first;
    expect(hello['v'], 2);
    expect(hello['peer_id'], 'a');
    final vv = initiator.sentFrames[1];
    expect((vv['docs']! as Map<dynamic, dynamic>).keys, ['world']);

    // The responder runs the same script, same frame order.
    final responderTypes = [
      for (final frame in responder.sentFrames) frame['type'],
    ];
    expect(responderTypes, initiatorTypes);

    // Convergence happened inside that single round.
    _expectConverged(f.syncA, f.syncB);
    expect(
      f.syncB.projection.componentValue(
        entityKey: 'ship:1',
        component: 'Position',
        field: 'y',
      ),
      2.5,
    );
    expect(f.driverA.failedExchanges, 0);
    expect(f.driverB.failedExchanges, 0);
  });

  test('mutual concurrent dials converge (crossing sessions are safe)',
      () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), f.writeTime());
    f.syncB.applyDelta(_delta('ship:2', 'x', 9.5), f.writeTime());

    // Both dial at once: two crossing sessions, each running the full
    // script. Convergence must not depend on who dials whom.
    await Future.wait([f.driverA.tick(), f.driverB.tick()]);
    await _settle();

    _expectConverged(f.syncA, f.syncB);
    expect(
      f.syncA.projection.componentValue(
        entityKey: 'ship:1',
        component: 'Position',
        field: 'x',
      ),
      1.5,
    );
    expect(
      f.syncA.projection.componentValue(
        entityKey: 'ship:2',
        component: 'Position',
        field: 'x',
      ),
      9.5,
    );
    expect(f.driverA.failedExchanges, 0);
    expect(f.driverB.failedExchanges, 0);
  });

  test('repeated rounds are idempotent: redelivery changes nothing',
      () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), f.writeTime());
    f.syncB.applyDelta(_delta('ship:2', 'x', 9.5), f.writeTime());
    await f.drive();
    final valuesA = f.syncA.projection.values;
    final vvA = f.syncA.vv.toJson();

    for (var round = 0; round < 3; round++) {
      await f.drive();
    }
    expect(f.syncA.projection.values, valuesA);
    expect(f.syncA.vv.toJson(), vvA);
    _expectConverged(f.syncA, f.syncB);
    expect(f.driverA.failedExchanges, 0);
  });

  test('zero-ops rounds between empty replicas ship empty deltas', () async {
    final f = _Fixture();
    await f.drive();
    await f.drive();

    expect(f.syncA.projection.values, isEmpty);
    expect(f.syncB.projection.values, isEmpty);
    // Every completed round still spoke the protocol (hello/vv/delta both
    // ways) but carried nothing — the no-op round is a protocol round.
    final frames = [...f.spyA.sentFrames, ...f.spyB.sentFrames];
    expect(frames, isNotEmpty);
    for (final frame in frames.where(
      (final candidate) => candidate['type'] == MeshSyncProtocol.deltaType,
    )) {
      expect(frame['ops'], isEmpty);
      expect(frame['states'], isEmpty);
    }
    expect(f.driverA.failedExchanges, 0);
    expect(f.driverB.failedExchanges, 0);
  });

  test('removals propagate as tombstones through rounds', () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'shield', true), f.writeTime());
    await f.drive();
    expect(
      f.syncB.projection.componentValue(
        entityKey: 'ship:1',
        component: 'Position',
        field: 'shield',
      ),
      true,
    );

    f.syncA.removeDelta(_delta('ship:1', 'shield', null), f.writeTime(1));
    await f.drive();

    for (final sync in [f.syncA, f.syncB]) {
      expect(
        sync.projection.contains('ship:1/Position/shield'),
        isFalse,
        reason: 'tombstoned keys are absent from the projection',
      );
    }
    _expectConverged(f.syncA, f.syncB);
  });

  test('a compacted log serves a lagging peer a snapshot, not ops', () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), f.writeTime());
    // Compact everything away, then write more and compact again: the log
    // is empty, so no delta can serve a fresh peer.
    f.syncA.compact();
    f.syncA.applyDelta(_delta('ship:1', 'y', 2.5), f.writeTime());
    f.syncA.compact();
    expect(f.syncA.pendingOps, isEmpty);

    // B dials: A's answer must be a snapshot frame.
    await f.driverB.tick();
    await _settle();

    final reply = f.lastDeltaFrameOf(f.spyA);
    expect(reply, isNotNull);
    expect(reply!['ops'], isEmpty, reason: 'the log is compacted away');
    expect(reply['states']! as List<dynamic>, hasLength(1));

    _expectConverged(f.syncA, f.syncB);
    expect(
      f.syncB.projection.componentValue(
        entityKey: 'ship:1',
        component: 'Position',
        field: 'y',
      ),
      2.5,
    );
    expect(f.driverB.failedExchanges, 0);
  });

  test('a fully covered peer receives an empty delta, never ops or a '
      'snapshot', () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), f.writeTime());
    await f.drive();
    f.syncA.compact();
    final valuesB = f.syncB.projection.values;

    // B is fully covered by A's compacted state: A's answer is silence in
    // payload form — an empty delta frame, no ops, no snapshot.
    await f.drive();

    final reply = f.lastDeltaFrameOf(f.spyA);
    expect(reply, isNotNull);
    expect(reply!['ops'], isEmpty);
    expect(reply['states'], isEmpty);
    expect(f.syncB.projection.values, valuesB);
    expect(f.driverA.failedExchanges, 0);
  });

  test('periodic mode exchanges, compacts, and stops', () async {
    final clock = _StepClock();
    final f = _Fixture(maxLogOps: 2, clock: clock.next);
    f.driverA.start(interval: const Duration(milliseconds: 5));
    f.driverB.start(interval: const Duration(milliseconds: 5));
    expect(f.driverA.isRunning, isTrue);

    // Three local ops exceed maxLogOps 2; periodic rounds deliver them to
    // B and the size trigger compacts A's log.
    for (var i = 0; i < 3; i++) {
      f.syncA.applyDelta(_delta('ship:$i', 'x', i.toDouble()), clock.next());
    }
    expect(f.syncA.pendingOps.length, 3);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      f.syncB.projection.values.length,
      3,
      reason: 'periodic rounds delivered the ops',
    );
    expect(f.syncA.pendingOps, isEmpty, reason: 'size trigger compacted');
    expect(f.driverA.compactions, greaterThanOrEqualTo(1));

    // Stop ends the rounds: no new sessions or frames afterwards.
    f.driverA.stop();
    f.driverB.stop();
    expect(f.driverA.isRunning, isFalse);
    await _settle();
    final exchanges = f.driverA.exchanges;
    final frames = f.spyA.sentFrames.length;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(f.driverA.exchanges, exchanges, reason: 'no rounds after stop');
    expect(f.spyA.sentFrames.length, frames, reason: 'no frames after stop');

    // Restart re-subscribes (the radio's inbound stream is
    // single-subscription; the driver waits out the release) and rounds
    // resume on both sides.
    f.driverA.start(interval: const Duration(milliseconds: 5));
    f.driverB.start(interval: const Duration(milliseconds: 5));
    expect(f.driverA.isRunning, isTrue);
    final exchangesAfterRestart = f.driverA.exchanges;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      f.driverA.exchanges,
      greaterThan(exchangesAfterRestart),
      reason: 'rounds resume after restart',
    );
    f.driverA.stop();
    f.driverB.stop();
  });

  test('the interval trigger compacts a non-empty log, an empty one never',
      () async {
    final clock = _ManualClock();
    final f = _Fixture(
      minInterval: const Duration(minutes: 5),
      clock: clock.now,
    );
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), clock.now());
    await f.drive();
    expect(f.syncA.pendingOps, hasLength(1));
    expect(f.driverA.compactions, 0, reason: 'interval not elapsed yet');

    clock.advanceBy(const Duration(minutes: 6));
    await f.drive();
    expect(f.syncA.pendingOps, isEmpty, reason: 'interval trigger fired');
    expect(f.driverA.compactions, 1);

    // An empty log never compacts, no matter how much time passes.
    clock.advanceBy(const Duration(hours: 1));
    await f.drive();
    expect(f.syncA.pendingOps, isEmpty);
    expect(f.driverA.compactions, 1);
  });

  test('an unreachable peer fails soft and the next round recovers',
      () async {
    final f = _Fixture();
    f.syncA.applyDelta(_delta('ship:1', 'x', 1.5), f.writeTime());

    // Simulate a partition: A cannot reach B. The tick must complete
    // without throwing — sync is opportunistic.
    (f.spyA.inner as FakeMeshTransport).failNextConnect = true;
    await f.driverA.tick();
    expect(f.driverA.failedExchanges, 1);
    expect(f.syncB.projection.values, isEmpty);

    // Partition heals; the next round converges.
    (f.spyA.inner as FakeMeshTransport).failNextConnect = false;
    await f.drive();
    _expectConverged(f.syncA, f.syncB);
    expect(f.driverA.failedExchanges, 1, reason: 'only the partition failed');
  });

  test('each replica ships its own state on its own dial', () async {
    final f = _Fixture();
    // B writes but never dials; A dials alone and still receives B's ops —
    // the script delivers both directions over one round.
    f.syncB.applyDelta(_delta('ship:2', 'x', 9.5), f.writeTime());
    await f.driverA.tick();
    await _settle();
    _expectConverged(f.syncA, f.syncB);

    // B's next local write reaches A on B's own dial.
    f.syncB.applyDelta(_delta('ship:3', 'x', 7.0), f.writeTime(1));
    await f.driverB.tick();
    await _settle();
    _expectConverged(f.syncA, f.syncB);
    expect(
      f.syncA.projection.componentValue(
        entityKey: 'ship:3',
        component: 'Position',
        field: 'x',
      ),
      7.0,
    );
  });
}
