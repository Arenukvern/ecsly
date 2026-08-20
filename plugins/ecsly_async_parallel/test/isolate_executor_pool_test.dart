import 'dart:isolate';
import 'dart:typed_data';

import 'package:async_parallel/async_parallel.dart';
import 'package:ecsly/ecsly.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';
import 'package:test/test.dart';

/// Worker entry for pooled isolate: receives [SendPort replyTo, TransferableTypedData chunk].
void _pooledDoubleFloatsWorker(final SendPort ownerSendPort) {
  final port = ReceivePort();
  ownerSendPort.send(port.sendPort);
  port.listen((final message) {
    if (message is List<Object?>) {
      final pair = message;
      final replyTo = pair[0]! as SendPort;
      final chunk = pair[1]! as TransferableTypedData;
      final received = TransferableBuffer(0)..receive(chunk);
      final input = received.data.buffer.asFloat32List();
      final output = Float32List(input.length);
      for (var i = 0; i < input.length; i++) {
        output[i] = input[i] * 2;
      }
      final transferable = TransferableTypedData.fromList([output]);
      replyTo.send([true, transferable]);
    }
  });
}

/// Doubles each float in the chunk. Top-level so it can run in an isolate.
void _doubleFloatsWorker(
  final SendPort replyTo,
  final TransferableTypedData chunk,
) {
  final received = TransferableBuffer(0)..receive(chunk);
  final input = received.data.buffer.asFloat32List();
  final output = Float32List(input.length);
  for (var i = 0; i < input.length; i++) {
    output[i] = input[i] * 2;
  }
  final transferable = TransferableTypedData.fromList([output]);
  replyTo.send([true, transferable]);
}

/// A buffered job system that doubles float buffers.
class _DoubleFloatsJobSystem
    extends BufferedScheduleJobSystem<Float32List, Float32List> {
  _DoubleFloatsJobSystem(this.input);

  final Float32List input;

  @override
  String get jobKey => 'test.double_floats';

  @override
  void Function(SendPort replyTo, TransferableTypedData chunk)
  get workerEntry => _doubleFloatsWorker;

  @override
  int get chunkStrideBytes => 16; // 4 floats per chunk

  @override
  Float32List extractTyped(final World world) => input;

  @override
  Float32List executeChunk(final Float32List chunk) {
    final output = Float32List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      output[i] = chunk[i] * 2;
    }
    return output;
  }

  @override
  void mergeTyped(
    final World world,
    final List<ScheduleJobChunkResult<Float32List>> orderedResults,
  ) {
    final total = orderedResults.fold<int>(
      0,
      (final sum, final r) => sum + r.value.length,
    );
    final merged = Float32List(total);
    var offset = 0;
    for (final r in orderedResults) {
      merged.setRange(offset, offset + r.value.length, r.value);
      offset += r.value.length;
    }
    world.resources.push(_DoubledBuffer(merged));
  }
}

class _DoubledBuffer extends Resource {
  _DoubledBuffer(this.data);
  final Float32List data;
}

void main() {
  group('IsolateExecutorPoolDart', () {
    test('runs work through a pooled executor', () async {
      final pool = IsolateExecutorPoolDart(
        workerEntry: _pooledDoubleFloatsWorker,
        size: 2,
      );
      try {
        final input = Float32List.fromList([1, 2, 3, 4]);
        final buffer = TransferableBuffer.fromTypedData(input);
        final transferred = buffer.transfer();
        final payload = await pool
            .compute<TransferableTypedData, TransferableTypedData>(
              (_) => TransferableTypedData.fromList([]),
              transferred,
            );
        final received = TransferableBuffer(0)..receive(payload);
        final output = received.data.buffer.asFloat32List();
        expect(output, equals(Float32List.fromList([2, 4, 6, 8])));
      } finally {
        await pool.shutdown();
      }
    });

    test('reuses workers across multiple tasks', () async {
      final pool = IsolateExecutorPoolDart(
        workerEntry: _pooledDoubleFloatsWorker,
        size: 2,
      );
      try {
        final results = <double>[];
        for (var i = 0; i < 10; i++) {
          final input = Float32List.fromList([i.toDouble()]);
          final buffer = TransferableBuffer.fromTypedData(input);
          final transferred = buffer.transfer();
          final payload = await pool
              .compute<TransferableTypedData, TransferableTypedData>(
                (_) => TransferableTypedData.fromList([]),
                transferred,
              );
          final received = TransferableBuffer(0)..receive(payload);
          final output = received.data.buffer.asFloat32List();
          results.add(output[0]);
        }
        expect(
          results,
          equals(List.generate(10, (final i) => (i * 2).toDouble())),
        );
      } finally {
        await pool.shutdown();
      }
    });
  });

  group('BufferedScheduleJobSystem zero-copy', () {
    test('runSerial doubles all values', () {
      final world = World();
      final input = Float32List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final job = _DoubleFloatsJobSystem(input);

      job.runSerial(world);

      final result = world.getResource<_DoubledBuffer>();
      expect(
        result.data,
        equals(Float32List.fromList([2, 4, 6, 8, 10, 12, 14, 16])),
      );
    });

    test(
      'runDeterministic doubles all values via background isolates',
      () async {
        final world = World();
        final policy = world.getResource<ScheduleExecutionPolicyResource>()
          ..mode = ScheduleExecutionPolicy.deterministic
          ..workerCount = 4;
        policy.markFrame(1);
        world.upsertResource(ScheduleJobResultQueueResource());

        final input = Float32List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final job = _DoubleFloatsJobSystem(input);

        await job.runDeterministic(
          world,
          policy: policy,
          queue: world.getResource<ScheduleJobResultQueueResource>(),
        );

        final result = world.getResource<_DoubledBuffer>();
        expect(
          result.data,
          equals(Float32List.fromList([2, 4, 6, 8, 10, 12, 14, 16])),
        );
      },
    );

    test('serial and deterministic produce identical results', () async {
      final input = Float32List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final world1 = World();
      final job1 = _DoubleFloatsJobSystem(input);
      job1.runSerial(world1);
      final result1 = world1.getResource<_DoubledBuffer>();

      final world2 = World();
      final policy2 = world2.getResource<ScheduleExecutionPolicyResource>()
        ..mode = ScheduleExecutionPolicy.deterministic
        ..workerCount = 4;
      policy2.markFrame(1);
      world2.upsertResource(ScheduleJobResultQueueResource());
      final job2 = _DoubleFloatsJobSystem(input);
      await job2.runDeterministic(
        world2,
        policy: policy2,
        queue: world2.getResource<ScheduleJobResultQueueResource>(),
      );
      final result2 = world2.getResource<_DoubledBuffer>();

      expect(result2.data, equals(result1.data));
    });
  });
}
