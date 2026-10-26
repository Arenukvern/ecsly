import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

/// Benchmarks for world snapshot capture, encode, decode, and restore.
///
/// Run with: `flutter test test/benchmark_test.dart`
/// (or `just bench-serialization` from the repo root).
///
/// Results are printed to stdout as ops/sec and µs/op. These are wall-clock
/// micro-benchmarks; treat relative movements, not absolute numbers, as the
/// signal.

/// Measures [run] for ~500ms after warmup and prints µs/op + ops/s.
int _measure(final String name, final int Function() run) {
  // Warmup.
  run();
  run();

  const targetMs = 500;
  final watch = Stopwatch()..start();
  var iterations = 0;
  while (watch.elapsedMilliseconds < targetMs) {
    iterations += run();
  }
  watch.stop();

  final usPerOp = watch.elapsedMicroseconds / iterations;
  final opsPerSec = iterations / (watch.elapsedMicroseconds / 1e6);
  // ignore: avoid_print
  print(
    '$name: ${usPerOp.toStringAsFixed(1)} µs/op | '
    '${opsPerSec.toStringAsFixed(0)} ops/s ($iterations iters)',
  );
  return iterations;
}

World _worldWith(final int entityCount) {
  final world = buildSerializationTestWorld();
  registerPersistentId(world);
  for (var i = 0; i < entityCount; i++) {
    world.spawnComponents([
      PersistentId(i + 1),
      const PositionComponent(),
      const HealthComponent(),
      const ScoreComponent(),
    ]);
  }
  world.flush();
  return world;
}

void main() {
  // ignore: avoid_print
  print('--- ecsly_serialization benchmarks ---');

  test(
    'benchmark: capture/encode/decode/restore at 100 / 1k / 10k entities',
    () {
      for (final count in const [100, 1000, 10000]) {
        final source = _worldWith(count);
        final snapshot = captureWorldSnapshot(source);
        final encoded = encodeWorldSnapshot(snapshot);

        _measure('capture   [$count entities]', () {
          captureWorldSnapshot(source);
          return 1;
        });

        _measure('encode    [$count entities]', () {
          encodeWorldSnapshot(snapshot);
          return 1;
        });

        _measure('decode    [$count entities]', () {
          decodeWorldSnapshot(encoded);
          return 1;
        });

        // Restore into an empty target — the spawn-fresh path.
        final target = buildSerializationTestWorld();
        _measure('restore   [$count entities]', () {
          restoreWorldSnapshot(target, snapshot);
          return 1;
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('benchmark: single-entity column capture', () {
    final world = _worldWith(1);
    final entity = world.archetypes.all.expand((final a) => a.entities).first;

    _measure('captureEntityColumns [1 entity, 3 components]', () {
      for (var i = 0; i < 10000; i++) {
        captureEntityColumns(world, entity);
      }
      return 10000;
    });
  });
}
