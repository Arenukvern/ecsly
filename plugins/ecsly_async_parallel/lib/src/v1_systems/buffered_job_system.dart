import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:async_parallel/async_parallel.dart';
import 'package:ecsly/ecsly.dart';

import 'resource.dart';
import 'schedule_job_types.dart';
import 'schedule_parallel_task_system.dart';

/// {@template buffered_schedule_job_system}
/// A [ScheduleParallelTaskSystem] whose chunks are flat [TypedData] buffers,
/// transferred between isolates with zero-copy [TransferableTypedData].
///
/// ## Why this exists
///
/// [PartitionedScheduleJobSystem] sends arbitrary Dart objects across isolate
/// boundaries, which the VM copies. For hot paths where the data is already a
/// flat buffer — positions, velocities, collision pairs — that copy is pure
/// waste. This base class constrains `TChunk` to [TypedData] and routes chunk
/// payloads through [TransferableBuffer], so the worker views the *same*
/// memory the owner handed over.
///
/// ## The isolate constraint
///
/// Background execution requires a **top-level or static** function — an
/// isolate cannot receive an instance method or a closure capturing `this`.
/// [workerEntry] is that top-level hook; [executeChunk] is the instance-side
/// mirror used by [runSerial]. They must implement the same logic.
///
/// ## Wire protocol
///
/// [workerEntry] receives `[SendPort replyTo, TransferableTypedData chunk]`,
/// materializes the chunk, runs the per-chunk work, and sends
/// `[bool ok, TransferableTypedData result]` back on `replyTo`.
///
/// ## What is zero-copy
///
/// * **Chunk input**: transferred via [TransferableTypedData]. The worker
///   materializes the exact buffer the owner produced — no copy.
/// * **Chunk output**: returned through the isolate's result channel, so it is
///   copied. Outputs are typically small (a frame's worth of manifolds), so
///   this is the right place to accept a copy.
///
/// ## Pooled execution
///
/// By default, each chunk spawns a fresh isolate via [Isolate.spawn]. Override
/// [dispatchChunk] to route through a pooled executor instead — amortizes
/// isolate startup cost for many small, frequent tasks.
///
/// ## Migration path
///
/// Existing [PartitionedScheduleJobSystem] subclasses keep working unchanged.
/// Adopt this base class when your extract/merge can operate on raw buffers —
/// that is the point at which zero-copy actually pays off.
/// {@endtemplate}
abstract class BufferedScheduleJobSystem<
  TChunk extends TypedData,
  TResult extends TypedData
>
    extends ScheduleParallelTaskSystem {
  /// {@macro buffered_schedule_job_system}
  const BufferedScheduleJobSystem();

  /// Top-level worker entry point for background execution.
  ///
  /// Receives `[SendPort replyTo, TransferableTypedData chunk]`, materializes
  /// the chunk, runs the per-chunk work, and sends `[bool ok,
  /// TransferableTypedData result]` back on `replyTo`.
  void Function(SendPort replyTo, TransferableTypedData chunk) get workerEntry;

  /// Extracts a single [TypedData] buffer of per-frame input from the world.
  TypedData extractTyped(final World world);

  /// Slices [buffer] into per-chunk views.
  ///
  /// Default: split evenly by [chunkStrideBytes], yielding views over the
  /// original buffer (no copy). Override to customize chunk boundaries.
  List<ScheduleJobChunk<TChunk>> partitionTyped(
    final TypedData buffer,
    final ScheduleExecutionPolicyResource policy,
  ) {
    final stride = chunkStrideBytes;
    if (stride <= 0 || buffer.lengthInBytes <= stride) {
      return <ScheduleJobChunk<TChunk>>[
        ScheduleJobChunk<TChunk>(chunkKey: 0, payload: buffer as TChunk),
      ];
    }

    final chunks = <ScheduleJobChunk<TChunk>>[];
    var offset = 0;
    var key = 0;
    while (offset < buffer.lengthInBytes) {
      final end = (offset + stride < buffer.lengthInBytes)
          ? offset + stride
          : buffer.lengthInBytes;
      final view = _sublistView<TChunk>(buffer, offset, end);
      chunks.add(ScheduleJobChunk<TChunk>(chunkKey: key++, payload: view));
      offset = end;
    }
    return chunks;
  }

  /// Stride, in bytes, between consecutive chunks.
  int get chunkStrideBytes;

  /// Runs a single chunk and returns its result buffer.
  ///
  /// Instance-side mirror of [workerEntry], used by [runSerial].
  TResult executeChunk(final TChunk chunk);

  /// Merges ordered chunk results back into the world.
  void mergeTyped(
    final World world,
    final List<ScheduleJobChunkResult<TResult>> orderedResults,
  );

  /// Wraps a chunk view so it can be sent across an isolate boundary.
  TransferableBuffer wrapChunk(final TChunk chunk) =>
      TransferableBuffer.fromTypedData(chunk);

  /// Reconstructs a chunk view from a transferred buffer.
  TChunk unwrapChunk(final TransferableBuffer buffer) => buffer.data as TChunk;

  /// Reconstructs a result view from a transferred buffer.
  ///
  /// [TransferableBuffer.receive] materializes data as [Uint8List]; this method
  /// reinterprets the underlying buffer as [TResult]. Override if your result
  /// type needs custom reconstruction.
  TResult unwrapResult(final TransferableBuffer buffer) {
    final data = buffer.data;
    if (TResult == Float32List) {
      return Float32List.view(
            data.buffer,
            data.offsetInBytes,
            data.lengthInBytes ~/ 4,
          )
          as TResult;
    }
    if (TResult == Float64List) {
      return Float64List.view(
            data.buffer,
            data.offsetInBytes,
            data.lengthInBytes ~/ 8,
          )
          as TResult;
    }
    if (TResult == Int32List) {
      return Int32List.view(
            data.buffer,
            data.offsetInBytes,
            data.lengthInBytes ~/ 4,
          )
          as TResult;
    }
    if (TResult == Int64List) {
      return Int64List.view(
            data.buffer,
            data.offsetInBytes,
            data.lengthInBytes ~/ 8,
          )
          as TResult;
    }
    if (TResult == Uint8List) {
      return data as TResult;
    }
    return data as TResult;
  }

  /// Dispatches a single chunk to a background worker.
  ///
  /// Defaults to spawning a fresh isolate per chunk via [Isolate.spawn].
  /// Override to route through a pooled executor instead — amortizes isolate
  /// startup cost for many small, frequent tasks.
  ///
  /// The [payload] is a [TransferableTypedData] containing the chunk buffer.
  /// The returned future completes with `[bool ok, TransferableTypedData result]`.
  Future<List<Object?>> dispatchChunk(
    final TransferableTypedData payload,
    final void Function(SendPort replyTo, TransferableTypedData chunk) worker,
  ) async {
    final replyPort = ReceivePort();
    final isolate = await Isolate.spawn(_bufferedWorkerBridge, [
      replyPort.sendPort,
      worker,
      payload,
    ]);
    final result = await replyPort.first as List<Object?>;
    isolate.kill(priority: Isolate.immediate);
    replyPort.close();
    return result;
  }

  @override
  void runSerial(final World world) {
    final policy = resolveScheduleExecutionPolicy(world);
    final buffer = extractTyped(world);
    final chunks = partitionTyped(buffer, policy);
    if (chunks.isEmpty) {
      mergeTyped(world, <ScheduleJobChunkResult<TResult>>[]);
      return;
    }

    final results = <ScheduleJobChunkResult<TResult>>[];
    for (final chunk in chunks) {
      results.add(
        ScheduleJobChunkResult<TResult>(
          chunkKey: chunk.chunkKey,
          value: executeChunk(chunk.payload),
        ),
      );
    }
    results.sort((final a, final b) => a.chunkKey.compareTo(b.chunkKey));
    mergeTyped(world, results);
  }

  @override
  Future<void> runDeterministic(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    if (policy.workerCount <= 1) {
      runSerial(world);
      return;
    }

    final buffer = extractTyped(world);
    final chunks = partitionTyped(buffer, policy);
    if (chunks.length <= 1) {
      runSerial(world);
      return;
    }

    final futures = <Future<ScheduleJobChunkResult<TResult>>>[];
    for (final chunk in chunks) {
      futures.add(_runChunkInIsolate(wrapChunk(chunk.payload), chunk.chunkKey));
    }

    final results = await Future.wait(futures);
    results.sort((final a, final b) => a.chunkKey.compareTo(b.chunkKey));
    mergeTyped(world, results);
  }

  @override
  Future<void> runBestEffort(
    final World world, {
    required final ScheduleExecutionPolicyResource policy,
    required final ScheduleJobResultQueueResource queue,
  }) async {
    final frameId = currentScheduleExecutionFrame(world);
    var mergedCompletedFrame = false;
    if (policy.workerCount <= 1) {
      runSerial(world);
      return;
    }

    final completedFrameId = frameId - 1;
    if (completedFrameId >= 0) {
      queue.dropStaleResults(jobKey: jobKey, minFrameId: completedFrameId);
      final completed = queue.takeForFrame<TResult>(
        jobKey: jobKey,
        frameId: completedFrameId,
      );
      if (completed.isNotEmpty) {
        mergeTyped(world, completed);
        mergedCompletedFrame = true;
      }
    }

    if (queue.hasInFlightJob(jobKey)) {
      return;
    }

    final buffer = extractTyped(world);
    final chunks = partitionTyped(buffer, policy);
    if (chunks.length <= 1) {
      if (!mergedCompletedFrame) {
        runSerial(world);
      }
      return;
    }

    if (!queue.beginInFlight(jobKey: jobKey, frameId: frameId)) {
      return;
    }

    unawaited(
      Future.wait(
            chunks.map(
              (final chunk) =>
                  _runChunkInIsolate(wrapChunk(chunk.payload), chunk.chunkKey),
            ),
          )
          .then((final results) {
            results.sort(
              (final a, final b) => a.chunkKey.compareTo(b.chunkKey),
            );
            queue.completeInFlight(
              ScheduleJobResultEnvelope<TResult>(
                jobKey: jobKey,
                frameId: frameId,
                results: results,
              ),
            );
          })
          .catchError((final _) {
            queue.cancelInFlight(jobKey: jobKey, frameId: frameId);
          }),
    );
  }

  /// Runs a single chunk in a background isolate.
  ///
  /// The chunk is transferred zero-copy via [TransferableTypedData]. The
  /// isolate runs [workerEntry] on the received view and returns the result
  /// buffer through its result channel.
  Future<ScheduleJobChunkResult<TResult>> _runChunkInIsolate(
    final TransferableBuffer chunkBuffer,
    final int chunkKey,
  ) async {
    final transferred = chunkBuffer.transfer();
    final result = await dispatchChunk(transferred, workerEntry);

    final ok = result[0]! as bool;
    final payload = result[1]! as TransferableTypedData;
    if (!ok) {
      throw StateError('buffered worker failed for chunk $chunkKey');
    }
    final received = TransferableBuffer(0)..receive(payload);
    return ScheduleJobChunkResult<TResult>(
      chunkKey: chunkKey,
      value: unwrapResult(received),
    );
  }
}

/// Top-level bridge that turns an [Isolate.spawn] message into a single
/// [workerEntry] call and replies with `[bool ok, TransferableTypedData]`.
void _bufferedWorkerBridge(final List<Object?> message) {
  final replyTo = message[0]! as SendPort;
  final worker = message[1]! as void Function(SendPort, TransferableTypedData);
  final chunk = message[2]! as TransferableTypedData;
  worker(replyTo, chunk);
}

/// A zero-copy view over a contiguous region of another [TypedData] buffer.
///
/// Used by [BufferedScheduleJobSystem.partitionTyped] when slicing a large
/// input buffer into per-chunk views. It points at the original buffer rather
/// than copying, so partitioning is allocation-free.
class BufferSliceView {
  /// Creates a view over [source] from [startByte] to [endByte].
  BufferSliceView(this.source, this.startByte, this.endByte)
    : assert(startByte >= 0, 'startByte must be non-negative'),
      assert(endByte >= startByte, 'endByte must be >= startByte'),
      assert(
        endByte <= source.lengthInBytes,
        'endByte must not exceed source length',
      );

  /// The underlying buffer this view points into.
  final TypedData source;

  /// Byte offset of the slice within [source].
  final int startByte;

  /// End offset of the slice within [source] (exclusive).
  final int endByte;

  /// Length of the slice in bytes.
  int get lengthInBytes => endByte - startByte;

  /// The underlying [ByteBuffer].
  ByteBuffer get buffer => source.buffer;
}

/// Creates a typed view over a sub-region of [buffer], preserving the type.
T _sublistView<T extends TypedData>(
  final TypedData buffer,
  final int start,
  final int end,
) {
  final byteOffset = buffer.offsetInBytes + start;
  final byteLength = end - start;
  if (T == Uint8List) {
    return Uint8List.view(buffer.buffer, byteOffset, byteLength) as T;
  }
  if (T == Int32List) {
    return Int32List.view(buffer.buffer, byteOffset, byteLength ~/ 4) as T;
  }
  if (T == Float32List) {
    return Float32List.view(buffer.buffer, byteOffset, byteLength ~/ 4) as T;
  }
  if (T == Float64List) {
    return Float64List.view(buffer.buffer, byteOffset, byteLength ~/ 8) as T;
  }
  if (T == Uint16List) {
    return Uint16List.view(buffer.buffer, byteOffset, byteLength ~/ 2) as T;
  }
  return buffer.buffer.asUint8List(byteOffset, byteLength) as T;
}
