import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ecsly_visualization_studio/preview_checkpoint.dart';

void main() {
  test(
    'remount startup reads storage after a dispatched old save settles',
    () async {
      final coordinator = CheckpointCoordinator();
      final gate = Completer<void>();
      final started = Completer<void>();
      var stored = 'previous';
      final old = coordinator.attach(
        key: 'alpha',
        write: (value) async {
          started.complete();
          await gate.future;
          stored = value;
          return true;
        },
        read: () async => stored,
      );
      final saved = old.save('latest');
      final detachedResult = expectLater(saved, throwsStateError);
      await started.future;
      old.detach();
      var reads = 0;
      final initial = coordinator.readSettled('alpha', () async {
        reads++;
        return stored;
      });
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      gate.complete();
      await detachedResult;
      expect(await initial, 'latest');
      expect(reads, 1);
    },
  );

  test(
    'replacement waits for dispatched save and drops old queued save',
    () async {
      final coordinator = CheckpointCoordinator();
      final gate = Completer<void>();
      final started = Completer<void>();
      final writes = <String>[];
      String? stored;
      final old = coordinator.attach(
        key: 'alpha',
        write: (value) async {
          writes.add(value);
          started.complete();
          await gate.future;
          stored = value;
          return true;
        },
        read: () async => stored,
      );
      final first = old.save('old dispatched');
      final firstRefusal = expectLater(first, throwsStateError);
      await started.future;
      final queued = old.save('old queued');
      final queuedRefusal = expectLater(queued, throwsStateError);
      old.detach();
      final replacement = coordinator.attach(
        key: 'alpha',
        write: (value) async {
          writes.add(value);
          stored = value;
          return true;
        },
        read: () async => stored,
      );
      final latest = replacement.save('new owner');
      old.detach(); // Stale teardown must not release replacement ownership.
      expect(replacement.active, isTrue);
      expect(writes, ['old dispatched']);
      gate.complete();
      await firstRefusal;
      await queuedRefusal;
      expect(await latest, isTrue);
      expect(writes, ['old dispatched', 'new owner']);
      expect(await replacement.load(), 'new owner');
      replacement.detach();
    },
  );

  test('late restore cannot return data to detached viewer', () async {
    final coordinator = CheckpointCoordinator();
    final read = Completer<String?>();
    final started = Completer<void>();
    final owner = coordinator.attach(
      key: 'alpha',
      write: (_) async => true,
      read: () {
        started.complete();
        return read.future;
      },
    );
    final pending = owner.load();
    final refused = expectLater(pending, throwsStateError);
    await started.future;
    owner.detach();
    read.complete('obsolete');
    await refused;
  });

  test('failed storage does not poison lane or block another viewer', () async {
    final coordinator = CheckpointCoordinator();
    var attempts = 0;
    final alpha = coordinator.attach(
      key: 'alpha',
      write: (_) async {
        if (++attempts == 1) throw StateError('adapter failure');
        return true;
      },
      read: () async => null,
    );
    final beta = coordinator.attach(
      key: 'beta',
      write: (_) async => true,
      read: () async => null,
    );
    await expectLater(alpha.save('first'), throwsStateError);
    expect(await beta.save('independent'), isTrue);
    expect(await alpha.save('retry explicitly requested'), isTrue);
    alpha.detach();
    beta.detach();
  });
}
