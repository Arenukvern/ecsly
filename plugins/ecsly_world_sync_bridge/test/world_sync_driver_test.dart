import 'package:ecsly_world_sync_bridge/ecsly_world_sync_bridge.dart';
import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

import 'test_components.dart';

/// Transport spy: records every outbound message, delegating to the wrapped
/// link so the wire still flows.
class _SpyTransport implements WorldSyncTransport {
  _SpyTransport(this._inner);

  final WorldSyncTransport _inner;
  final List<({String to, WorldSyncMessage message})> sent = [];

  @override
  void send(final String toPeerId, final WorldSyncMessage message) {
    sent.add((to: toPeerId, message: message));
    _inner.send(toPeerId, message);
  }

  @override
  Stream<WorldSyncIncoming> get messages => _inner.messages;

  bool sentAny(final Type messageType) =>
      sent.any((final entry) => entry.message.runtimeType == messageType);
}

/// One anti-entropy round-trip between two manually-driven drivers: both
/// tick, then every queued envelope is delivered to its receiver until the
/// wire goes quiet.
void _exchange(
  final WorldSyncDriver driverA,
  final LocalSyncTransport linkA,
  final WorldSyncDriver driverB,
  final LocalSyncTransport linkB,
) {
  driverA.tick();
  driverB.tick();
  var rounds = 0;
  while ((linkA.hasQueued || linkB.hasQueued) && rounds < 32) {
    linkA.takeQueued().forEach(driverA.handleIncoming);
    linkB.takeQueued().forEach(driverB.handleIncoming);
    rounds++;
  }
  expect(rounds, lessThan(32), reason: 'exchange did not settle');
}

void main() {
  group('WorldSyncMessage JSON round-trips', () {
    WorldSync syncWithOneOp() {
      final sync = WorldSync(actorId: 'a');
      sync.applyDelta(
        const ComponentDelta(
          entityKey: '1',
          component: 'C',
          field: '0',
          value: 1,
        ),
        DateTime.utc(2026, 9, 26, 12),
      );
      return sync;
    }

    test('VvMessage', () {
      final sync = syncWithOneOp();
      final decoded =
          WorldSyncMessage.fromJsonAs<VvMessage>(VvMessage(sync.vv).toJson());
      expect(decoded.type, 'vv');
      expect(decoded.vv.toJson(), sync.vv.toJson());
    });

    test('OpsMessage', () {
      final sync = syncWithOneOp();
      final decoded = WorldSyncMessage.fromJsonAs<OpsMessage>(
        OpsMessage(sync.pendingOps).toJson(),
      );
      expect(decoded.type, 'ops');
      expect(decoded.ops.length, 1);
      expect(decoded.ops.single.toJson(), sync.pendingOps.single.toJson());
    });

    test('SnapshotMessage', () {
      final sync = syncWithOneOp();
      final snapshot = sync.snapshotFor();
      final decoded = WorldSyncMessage.fromJsonAs<SnapshotMessage>(
        SnapshotMessage(snapshot).toJson(),
      );
      expect(decoded.type, 'snapshot');
      expect(decoded.snapshot.docId, snapshot.docId);
      expect(decoded.snapshot.baseVv.toJson(), snapshot.baseVv.toJson());
      expect(decoded.snapshot.state, snapshot.state);
      expect(decoded.snapshot.createdAt.toJson(), snapshot.createdAt.toJson());
    });

    test('discriminates types and rejects unknowns and bad versions', () {
      expect(
        WorldSyncMessage.fromJson(VvMessage(VersionVector()).toJson()),
        isA<VvMessage>(),
      );
      expect(
        () => WorldSyncMessage.fromJson(<String, Object?>{
          'v': 1,
          'type': 'mystery',
        }),
        throwsArgumentError,
      );
      expect(
        () => WorldSyncMessage.fromJson(<String, Object?>{
          'v': 999,
          'type': 'vv',
          'vv': <String, Object?>{},
        }),
        throwsArgumentError,
        reason: 'unsupported format versions must not be guessed at',
      );
    });
  });

  group('LocalSyncHub', () {
    test('routes deep copies FIFO and isolates mutable state', () async {
      final hub = LocalSyncHub();
      final a = hub.register('a');
      final b = hub.register('b');

      final sync = WorldSync(actorId: 'a');
      sync.applyDelta(
        const ComponentDelta(
          entityKey: '1',
          component: 'C',
          field: '0',
          value: 1,
        ),
        DateTime.utc(2026, 9, 26, 12),
      );
      final ops = List<OpRecord>.of(sync.pendingOps);
      a.send('b', OpsMessage(ops));

      // Mutating the sender's list after send must not touch the wire copy.
      ops.clear();
      expect(b.hasQueued, isTrue);
      final received = b.takeQueued();
      expect(received.length, 1);
      expect(received.single.fromPeerId, 'a');
      final opsMessage = received.single.message as OpsMessage;
      expect(opsMessage.ops.length, 1);
      expect(opsMessage.ops.single.toJson(), sync.pendingOps.single.toJson());

      // FIFO across multiple messages, synchronous delivery to listeners.
      a.send('b', OpsMessage(List<OpRecord>.of(sync.pendingOps)));
      a.send('b', VvMessage(VersionVector()));
      final seen = <WorldSyncMessage>[];
      final sub = b.messages.listen((final e) => seen.add(e.message));
      b.flush();
      expect(seen.length, 2, reason: 'both queued messages delivered');
      expect(seen.first, isA<OpsMessage>(), reason: 'FIFO order');
      expect(seen.last, isA<VvMessage>(), reason: 'FIFO order');
      expect(b.hasQueued, isFalse);
      await sub.cancel();

      expect(
        () => a.send('ghost', VvMessage(VersionVector())),
        throwsArgumentError,
      );
      expect(
        () => a.send('a', VvMessage(VersionVector())),
        throwsArgumentError,
      );
    });

    test('localSyncPair wires two transports that reach each other', () {
      final (a, b) = localSyncPair('left', 'right');
      a.send('right', VvMessage(VersionVector()));
      expect(b.takeQueued().single.fromPeerId, 'left');
    });
  });

  group('SnapshotPolicy', () {
    WorldSync syncWith(final int ops) {
      final sync = WorldSync(actorId: 'a');
      var t = DateTime.utc(2026, 9, 26, 12);
      for (var i = 0; i < ops; i++) {
        t = t.add(const Duration(milliseconds: 1));
        sync.applyDelta(
          ComponentDelta(
            entityKey: '$i',
            component: 'C',
            field: '0',
            value: i,
          ),
          t,
        );
      }
      return sync;
    }

    test('fires above maxLogOps, regardless of interval', () {
      const policy = SnapshotPolicy(
        maxLogOps: 4,
        minInterval: Duration(hours: 1),
      );
      expect(
        policy.shouldCompact(syncWith(5), DateTime.utc(2026, 9, 26, 12, 1)),
        isTrue,
        reason: 'log length 5 > maxLogOps 4',
      );
    });

    test('fires on elapsed interval with a non-empty log', () {
      const policy = SnapshotPolicy(); // defaults: 512 ops / 5 minutes
      final sync = syncWith(3);
      final now = DateTime.utc(2026, 9, 26, 12);
      expect(
        policy.shouldCompact(
          sync,
          now.add(const Duration(minutes: 6)),
          lastCompactionAt: now,
        ),
        isTrue,
      );
      expect(
        policy.shouldCompact(
          sync,
          now.add(const Duration(minutes: 4)),
          lastCompactionAt: now,
        ),
        isFalse,
        reason: 'interval not elapsed yet',
      );
      expect(
        policy.shouldCompact(sync, now.add(const Duration(hours: 1))),
        isFalse,
        reason: 'never compacted: no interval has elapsed since anything',
      );
    });

    test('never fires on an empty log', () {
      const policy = SnapshotPolicy(
        maxLogOps: 4,
        minInterval: Duration.zero,
      );
      final sync = WorldSync(actorId: 'a');
      sync.compact(); // empty the log
      expect(
        policy.shouldCompact(
          sync,
          DateTime.utc(2026, 9, 27),
          lastCompactionAt: DateTime.utc(2026),
        ),
        isFalse,
      );
    });

    test('defaults are 512 ops / 5 minutes', () {
      const policy = SnapshotPolicy();
      expect(policy.maxLogOps, 512);
      expect(policy.minInterval, const Duration(minutes: 5));
    });
  });

  group('WorldSyncDriver', () {
    test('tick broadcasts VvMessage to every peer', () {
      final hub = LocalSyncHub();
      final linkA = hub.register('a');
      final linkB = hub.register('b');
      final linkC = hub.register('c');
      final driver = WorldSyncDriver(
        sync: WorldSync(actorId: 'a'),
        transport: linkA,
        peers: {'b', 'c'},
      );

      driver.tick();
      expect(linkB.takeQueued().single.message, isA<VvMessage>());
      expect(linkC.takeQueued().single.message, isA<VvMessage>());
    });

    test('compacted replica serves a snapshot to a fresh lagging peer', () {
      final hub = LocalSyncHub();
      final linkA = hub.register('a');
      final linkC = hub.register('c');

      final worldA = buildTestWorld();
      final syncA = WorldSync(actorId: 'a');
      final bridgeA = WorldSyncBridge(world: worldA, sync: syncA);
      final spyA = _SpyTransport(linkA);
      final driverA = WorldSyncDriver(
        sync: syncA,
        transport: spyA,
        peers: {'c'},
      );

      final ship = spawnShip(worldA, 1, health: true);
      writeColumn(worldA, ship, PositionComponent, 0, 1.5);
      writeColumn(worldA, ship, PositionComponent, 1, 2.5);
      writeColumn(worldA, ship, HealthComponent, 0, 55);
      expect(bridgeA.emitDeltas(), 3);

      // Compact, write more, compact again: the log is empty, so no delta
      // can serve a fresh peer — only the snapshot can.
      syncA.compact();
      writeColumn(worldA, ship, HealthComponent, 0, 90);
      expect(bridgeA.emitDeltas(), 1);
      syncA.compact();
      expect(syncA.pendingOps, isEmpty);

      // Fresh lagging replica C joins with an empty vector.
      final syncC = WorldSync(actorId: 'c');
      final driverC = WorldSyncDriver(
        sync: syncC,
        transport: linkC,
        peers: {'a'},
      );

      driverC.tick(); // C's "I have nothing" vv reaches A
      driverA.handleIncoming(linkA.takeQueued().single);

      // A answered with a snapshot, NOT ops (nothing left in the log).
      expect(spyA.sentAny(SnapshotMessage), isTrue);
      expect(spyA.sentAny(OpsMessage), isFalse);
      final reply = linkC.takeQueued().single;
      expect(reply.message, isA<SnapshotMessage>());

      driverC.handleIncoming(reply);
      expect(syncC.projection.values, syncA.projection.values);
      expect(
        syncC.projection.componentValue(
          entityKey: '1',
          component: 'HealthComponent',
          field: '0',
        ),
        90,
      );

      // Redelivering the same (now stale) snapshot is a safe no-op.
      driverC.handleIncoming(reply);
      expect(syncC.projection.values, syncA.projection.values);
    });

    test('a fully covered peer receives nothing, never a snapshot', () {
      final hub = LocalSyncHub();
      final linkA = hub.register('a');
      final linkB = hub.register('b');

      final worldA = buildTestWorld();
      final syncA = WorldSync(actorId: 'a');
      final bridgeA = WorldSyncBridge(world: worldA, sync: syncA);
      final driverA = WorldSyncDriver(
        sync: syncA,
        transport: linkA,
        peers: {'b'},
      );
      final syncB = WorldSync(actorId: 'b');
      final driverB = WorldSyncDriver(
        sync: syncB,
        transport: linkB,
        peers: {'a'},
      );

      final ship = spawnShip(worldA, 1);
      writeColumn(worldA, ship, PositionComponent, 0, 1.5);
      bridgeA.emitDeltas();
      _exchange(driverA, linkA, driverB, linkB);
      expect(syncB.projection.values, syncA.projection.values);

      // Compact A and exchange again: B is fully covered (its vv dominates
      // A's), so B's answer must be silence — no ops, no snapshot.
      syncA.compact();
      final spyB = _SpyTransport(linkB);
      driverA.tick();
      linkB.takeQueued().forEach(driverB.handleIncoming);
      expect(spyB.sentAny(SnapshotMessage), isFalse);
      expect(spyB.sentAny(OpsMessage), isFalse);
      expect(linkA.hasQueued, isFalse);

      // A stale snapshot delivered straight to B is rejected by the kernel
      // adoption rule (B already covers its base vector) — over-sending is
      // safe, but changes nothing.
      final projectionBefore = syncB.projection.values;
      driverB.handleIncoming(
        WorldSyncIncoming(
          fromPeerId: 'a',
          message: SnapshotMessage(syncA.snapshotFor()),
        ),
      );
      expect(syncB.projection.values, projectionBefore);
    });

    test('periodic mode ticks, listens, compacts, and stops', () async {
      final hub = LocalSyncHub();
      final linkA = hub.register('a');
      final linkB = hub.register('b');
      final sync = WorldSync(actorId: 'a');
      final driver = WorldSyncDriver(
        sync: sync,
        transport: linkA,
        peers: {'b'},
        policy: const SnapshotPolicy(
          maxLogOps: 2,
          minInterval: Duration(hours: 1),
        ),
      );

      expect(driver.isRunning, isFalse);
      driver.start(interval: const Duration(milliseconds: 5));
      expect(driver.isRunning, isTrue);

      // Periodic ticks broadcast vvs to peers.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(linkB.takeQueued(), isNotEmpty);

      // Three local ops exceed maxLogOps 2, so a periodic tick compacts.
      var t = DateTime.utc(2026, 9, 26, 12);
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 1));
        sync.applyDelta(
          ComponentDelta(
            entityKey: '$i',
            component: 'C',
            field: '0',
            value: i,
          ),
          t,
        );
      }
      expect(sync.pendingOps.length, 3);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sync.pendingOps, isEmpty, reason: 'policy compaction fired');
      expect(driver.compactions, greaterThanOrEqualTo(1));

      // Stop ends the periodic ticks; nothing new is queued afterwards.
      driver.stop();
      expect(driver.isRunning, isFalse);
      linkB.takeQueued();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(linkB.takeQueued(), isEmpty, reason: 'no ticks after stop');
    });
  });
}
