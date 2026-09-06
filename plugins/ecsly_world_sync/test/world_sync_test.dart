import 'dart:math';

import 'package:ecsly_world_sync/ecsly_world_sync.dart';
import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

ComponentDelta _delta(
  final String entity,
  final String component,
  final String field,
  final Object? value,
) => ComponentDelta(
  entityKey: entity,
  component: component,
  field: field,
  value: value,
);

/// Two replicas with fixed local workloads, including one conflicting
/// write (both write `ship:1/Position/x`).
(WorldSync, WorldSync) _twoReplicas() {
  var tick = DateTime.utc(2026, 9, 6, 12);
  DateTime next() => tick = tick.add(const Duration(milliseconds: 7));

  final a = WorldSync(actorId: 'replica_a');
  final b = WorldSync(actorId: 'replica_b');

  a.applyDelta(_delta('ship:1', 'Position', 'x', 1.5), next());
  a.applyDelta(_delta('ship:1', 'Position', 'y', 2.5), next());
  a.applyEvent(
    const WorldSyncEvent(name: 'score', key: 'replica_a', value: 10),
    next(),
  );
  // Conflicting write: issued later by wall clock, so it must win LWW.
  b.applyDelta(_delta('ship:1', 'Position', 'x', 0.5), next());
  b.applyDelta(_delta('ship:2', 'Health', 'hp', 80), next());
  b.applyEvent(
    const WorldSyncEvent(name: 'spawned', key: 'ship:2', value: true),
    next(),
  );
  return (a, b);
}

/// One anti-entropy exchange over [transport]: each side ships what the
/// peer has not observed; inboxes are drained in [seed]-shuffled order.
void _exchange(
  final WorldSync a,
  final WorldSync b,
  final FakeTransport transport,
  final int seed,
) {
  transport.send('replica_a', 'replica_b', a.opsFor(b.vv));
  transport.send('replica_b', 'replica_a', b.opsFor(a.vv));
  final forA = transport.drain('replica_a')..shuffle(Random(seed));
  final forB = transport.drain('replica_b')..shuffle(Random(seed + 1));
  a.applyRemote(forA);
  b.applyRemote(forB);
}

void _expectConverged(final WorldSync a, final WorldSync b) {
  expect(b.projection.values, a.projection.values);
  expect(a.opsFor(b.vv), isEmpty, reason: 'a must have nothing b lacks');
  expect(b.opsFor(a.vv), isEmpty, reason: 'b must have nothing a lacks');
}

void main() {
  test('two replicas converge through shuffled delivery over a fake '
      'transport', () {
    final (a, b) = _twoReplicas();
    final transport = FakeTransport()
      ..register('replica_a')
      ..register('replica_b');

    _exchange(a, b, transport, 7);
    _expectConverged(a, b);

    // LWW winner for the conflicted key is deterministic: b's write is the
    // latest by HLC, regardless of delivery order.
    final x = b.projection.componentValue(
      entityKey: 'ship:1',
      component: 'Position',
      field: 'x',
    );
    expect(x, 0.5);
    expect(
      a.projection.eventValue(name: 'score', key: 'replica_a'),
      10,
    );
    expect(
      a.projection.eventValue(name: 'spawned', key: 'ship:2'),
      true,
    );
  });

  test('convergence holds for many shuffled delivery orders', () {
    for (var seed = 0; seed < 25; seed++) {
      final (a, b) = _twoReplicas();
      // Feed every op from both replicas to both replicas, in a shuffled
      // order, including each replica's own ops (redelivery).
      final all = [...a.pendingOps, ...b.pendingOps]
        ..shuffle(Random(seed));
      a.applyRemote(all);
      b.applyRemote(all);
      _expectConverged(a, b);
      final x = a.projection.componentValue(
        entityKey: 'ship:1',
        component: 'Position',
        field: 'x',
      );
      expect(x, 0.5, reason: 'seed $seed');
    }
  });

  test('redelivery is idempotent', () {
    final (a, b) = _twoReplicas();
    final transport = FakeTransport()
      ..register('replica_a')
      ..register('replica_b');
    _exchange(a, b, transport, 3);
    final stateBefore = a.projection.values;
    final vvBefore = a.vv;

    // Redeliver everything several times, in varying orders.
    final all = [...a.pendingOps, ...b.pendingOps];
    for (var round = 0; round < 5; round++) {
      final shuffled = List<OpRecord>.of(all)..shuffle(Random(round));
      a.applyRemote(shuffled);
      b.applyRemote(shuffled.reversed);
    }

    expect(b.projection.values, stateBefore);
    expect(a.projection.values, stateBefore);
    expect(a.vv, vvBefore);
    expect(b.opsFor(a.vv), isEmpty);
  });

  test('removals converge as tombstones and redeliver idempotently', () {
    var tick = DateTime.utc(2026, 9, 6, 12);
    DateTime next() => tick = tick.add(const Duration(milliseconds: 7));
    final a = WorldSync(actorId: 'replica_a');
    final b = WorldSync(actorId: 'replica_b');

    a.applyDelta(_delta('ship:1', 'Buff', 'shield', true), next());
    b.applyRemote(a.pendingOps);
    expect(
      b.projection.componentValue(
        entityKey: 'ship:1',
        component: 'Buff',
        field: 'shield',
      ),
      true,
    );

    a.removeDelta(_delta('ship:1', 'Buff', 'shield', null), next());
    b.applyRemote(a.opsFor(b.vv));
    expect(
      b.projection.contains('ship:1/Buff/shield'),
      isFalse,
      reason: 'tombstoned keys are absent from the projection',
    );
    // Re-applying the same ops (including the older set op) stays removed.
    b.applyRemote([...a.pendingOps, ...b.pendingOps]);
    expect(b.projection.contains('ship:1/Buff/shield'), isFalse);
  });

  test('JSON round-trip restores projection, vector, and sync ability', () {
    final (a, b) = _twoReplicas();
    final transport = FakeTransport()
      ..register('replica_a')
      ..register('replica_b');
    _exchange(a, b, transport, 11);

    final restored = WorldSync.fromJson(a.toJson());
    expect(restored.projection.values, a.projection.values);
    expect(restored.vv.toJson(), a.vv.toJson());
    expect(restored.pendingOps.length, a.pendingOps.length);

    // A restored replica keeps participating: new ops still converge.
    final tick = DateTime.utc(2026, 9, 6, 13);
    restored.applyDelta(_delta('ship:3', 'Health', 'hp', 42), tick);
    b.applyRemote(restored.opsFor(b.vv));
    expect(
      b.projection.componentValue(
        entityKey: 'ship:3',
        component: 'Health',
        field: 'hp',
      ),
      42,
    );
  });

  test('compaction: lagging replica catches up via snapshot, not deltas',
      () {
    final (a, b) = _twoReplicas();
    final transport = FakeTransport()
      ..register('replica_a')
      ..register('replica_b');
    _exchange(a, b, transport, 5);

    // Parent-chosen compaction policy (executed by the kernel).
    final pendingBefore = a.pendingOps.length;
    final retired = a.compact();
    expect(retired, pendingBefore, reason: 'log is truncated');
    expect(a.pendingOps, isEmpty);

    // A fresh replica is fully covered by VV but gets no deltas — it needs
    // a snapshot.
    final fresh = WorldSync(actorId: 'replica_c');
    expect(a.opsFor(fresh.vv), isEmpty);
    expect(a.needsSnapshotFor(fresh.vv), isTrue);

    final snapshot = a.snapshotFor();
    expect(fresh.adoptSnapshot(snapshot), isTrue);
    expect(fresh.projection.values, a.projection.values);

    // The already-synced peer (b) does not adopt a stale snapshot.
    expect(b.adoptSnapshot(snapshot), isFalse);
    expect(b.projection.values, a.projection.values);
  });

  test('WorldSync rejects non-LWW strategies for the projection', () {
    final doc = ConvergenceDoc(
      docId: 'world',
      actorId: 'replica_a',
    );
    final json = doc.toJson();
    json['strategy'] = 'rga_text';
    expect(() => WorldSync.fromJson(json), throwsArgumentError);
  });
}
