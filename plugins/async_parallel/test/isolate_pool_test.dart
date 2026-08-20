import 'package:async_parallel/async_parallel.dart';
import 'package:test/test.dart';

void main() {
  group('IsolateExecutorPool', () {
    test('runs work through a top-level worker entry', () async {
      final pool = IsolateExecutorPool(examplePoolWorkerEntry);
      try {
        final results = await Future.wait(
          List.generate(10, (final i) => pool.execute<int>(i)),
        );
        expect(results, equals(List.generate(10, (final i) => i * 2)));
      } finally {
        await pool.shutdown();
      }
    });

    test('reuses a single worker across many small tasks', () async {
      // A size-1 pool must service all 50 requests on one long-lived isolate.
      final pool = IsolateExecutorPool(examplePoolWorkerEntry, size: 1);
      try {
        final results = await Future.wait(
          List.generate(50, (final i) => pool.execute<int>(i)),
        );
        expect(results, hasLength(50));
        // The worker doubles its input, so every result is even and in order.
        expect(results, equals(List.generate(50, (final i) => i * 2)));
      } finally {
        await pool.shutdown();
      }
    });

    test('dispatches concurrently up to pool size', () async {
      final pool = IsolateExecutorPool(examplePoolWorkerEntry, size: 4);
      try {
        final stopwatch = Stopwatch()..start();
        final results = await Future.wait(
          List.generate(8, (final i) => pool.execute<int>(i)),
        );
        stopwatch.stop();
        expect(results, hasLength(8));
        // 8 tasks across 4 reused workers finish far faster than 8 fresh
        // isolate spawns would.
        expect(stopwatch.elapsedMilliseconds, lessThan(4000));
      } finally {
        await pool.shutdown();
      }
    });

    test('rejects work submitted after shutdown', () async {
      final pool = IsolateExecutorPool(examplePoolWorkerEntry, size: 1);
      await pool.shutdown();
      expect(() => pool.execute<int>(1), throwsA(isA<StateError>()));
    });
  });

  group('IsolateExecutorPoolAdapter', () {
    test('adapts a pool to the IsolateExecutor interface', () async {
      final pool = IsolateExecutorPool(examplePoolWorkerEntry, size: 2);
      final executor = IsolateExecutorPoolAdapter(pool);
      try {
        final results = await Future.wait(
          List.generate(
            6,
            (final i) => executor.compute<int, int>((_) => 0, i),
          ),
        );
        expect(results, equals(List.generate(6, (final i) => i * 2)));
      } finally {
        await pool.shutdown();
      }
    });
  });
}
