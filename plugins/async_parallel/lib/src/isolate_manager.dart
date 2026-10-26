import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'double_buffer.dart';

/// Manages isolate lifecycle and double-buffer coordination.
///
/// Handles the creation, communication, and cleanup of compute isolates
/// while maintaining the double buffering protocol.
///
/// ## Protocol
///
/// The manager runs a single compute isolate that owns the *write* buffer.
/// The owner isolate owns the *read* buffer and renders from it. Buffers are
/// transferred with [TransferableTypedData] for zero-copy ownership moves:
///
/// 1. [start] spawns the isolate, creates a [DoubleBuffer], and sends the
///    write buffer to the isolate as an [IsolateMessageType.initialize].
/// 2. [computeFrame] forwards input to the isolate. Frames submitted before
///    [start] completes, or while a frame is in flight, are queued and
///    dispatched in order once the isolate is ready.
/// 3. When the isolate finishes a frame it sends an
///    [IsolateMessageType.bufferTransfer] carrying the computed buffer. The
///    manager receives it, swaps the double buffer, and re-sends the former
///    read buffer for the next frame.
/// 4. [shutdown] requests a clean exit, awaits the isolate terminating (via its
///    `onExit` port), and cancels pending subscriptions and queued frames.
class IsolateManager {
  /// Creates an isolate manager for the specified compute function.
  IsolateManager(this._computeEntryPoint);

  final void Function(_ComputeIsolateArgs) _computeEntryPoint;

  Isolate? _isolate;

  SendPort? _sendPort;

  DoubleBuffer? _doubleBuffer;

  StreamSubscription? _subscription;

  StreamSubscription<Object?>? _exitSubscription;

  Completer<bool>? _exitCompleter;

  final Queue<_PendingFrame> _pendingFrames = Queue<_PendingFrame>();

  bool _started = false;

  bool _shuttingDown = false;

  /// Gets the current render buffer (safe to read from the owner isolate).
  DoubleBuffer? get renderBuffer => _doubleBuffer;

  /// Whether the compute isolate has been started and is accepting work.
  bool get isStarted => _started;

  /// Sends input data to the compute isolate for processing.
  ///
  /// Returns `true` if the frame was dispatched immediately, or `false` if it
  /// was queued because the isolate was not yet ready. Queued frames are
  /// dispatched in submission order once the isolate becomes ready.
  bool computeFrame(final Object inputData) {
    if (_shuttingDown) return false;

    if (_started && _sendPort != null && _doubleBuffer != null) {
      _sendToCompute(
        IsolateMessage(IsolateMessageType.computeFrame, data: inputData),
      );
      return true;
    }

    final completer = Completer<bool>();
    _pendingFrames.add(_PendingFrame(inputData, completer));
    return false;
  }

  /// Shuts down the compute isolate and cleans up resources.
  ///
  /// Returns `true` if an isolate was running and has been shut down, `false`
  /// if the manager was already stopped or never started.
  Future<bool> shutdown() async {
    if (_isolate == null) return false;

    _shuttingDown = true;
    // Drain pending frames so their Completers complete rather than hanging.
    while (_pendingFrames.isNotEmpty) {
      final pending = _pendingFrames.removeFirst();
      pending.completer.complete(false);
    }

    final isolate = _isolate!;

    try {
      _sendToCompute(const IsolateMessage(IsolateMessageType.shutdown));
    } on Object {
      // The isolate may already be gone; ignore send failures.
    }

    // Give the isolate a chance to exit cleanly, then force-kill if needed.
    final exitedCleanly = await Future.any([
      _exitCompleter?.future ?? Future<bool>.value(true),
      Future<bool>.delayed(const Duration(milliseconds: 200), () => false),
    ]);

    if (!exitedCleanly) {
      isolate.kill(priority: Isolate.immediate);
    }

    await _exitSubscription?.cancel();
    _exitSubscription = null;
    _exitCompleter = null;
    await _subscription?.cancel();
    _subscription = null;
    _sendPort = null;
    _doubleBuffer = null;
    _isolate = null;
    _started = false;
    _shuttingDown = false;
    return true;
  }

  /// Starts the compute isolate and initializes double buffering.
  ///
  /// Throws a [StateError] if called while already started.
  Future<void> start(final int bufferSizeBytes) async {
    if (_started) {
      throw StateError('IsolateManager already started');
    }

    _doubleBuffer = DoubleBuffer(bufferSizeBytes);

    final receivePort = ReceivePort();
    final exitPort = ReceivePort();
    _exitCompleter = Completer<bool>();

    _isolate = await Isolate.spawn(
      _computeEntryPoint,
      _ComputeIsolateArgs(receivePort.sendPort, bufferSizeBytes),
      onExit: exitPort.sendPort,
    );

    _exitSubscription = exitPort.listen(
      (final _) {
        _exitCompleter?.complete(true);
        exitPort.close();
      },
      onError: (final _) {
        _exitCompleter?.complete(true);
        exitPort.close();
      },
    );
    _subscription = receivePort.listen(_handleMessage);
    _sendPort = receivePort.sendPort;
    _started = true;

    // Send initial buffer to compute isolate.
    _sendToCompute(
      IsolateMessage(
        IsolateMessageType.initialize,
        transferable: _doubleBuffer!.writeBuffer.transfer(),
      ),
    );

    // Dispatch any frames that were queued before start() completed.
    while (_pendingFrames.isNotEmpty) {
      final pending = _pendingFrames.removeFirst();
      _sendToCompute(
        IsolateMessage(IsolateMessageType.computeFrame, data: pending.input),
      );
      pending.completer.complete(true);
    }
  }

  void _handleMessage(final Object? message) {
    if (message is IsolateMessage) {
      switch (message.type) {
        case IsolateMessageType.bufferTransfer:
          // Receive the computed buffer.
          final buffer = _doubleBuffer;
          if (buffer == null) return;
          buffer.writeBuffer.receive(message.transferable!);
          buffer.swap();

          // Send the old read buffer back for next computation.
          _sendToCompute(
            IsolateMessage(
              IsolateMessageType.initialize,
              transferable: buffer.writeBuffer.transfer(),
            ),
          );
        case IsolateMessageType.initialize:
        case IsolateMessageType.computeFrame:
        case IsolateMessageType.shutdown:
          // These messages are sent TO the compute isolate, not FROM it.
          break;
      }
    }
  }

  void _sendToCompute(final IsolateMessage message) {
    final port = _sendPort;
    if (port == null) return;
    try {
      port.send(message);
    } on Object {
      // The isolate may be gone; ignore send failures.
    }
  }
}

/// A frame submitted to [IsolateManager.computeFrame] before the isolate was
/// ready, along with the Completer that its submitter is awaiting.
class _PendingFrame {
  _PendingFrame(this.input, this.completer);

  final Object input;
  final Completer<bool> completer;
}

/// Messages sent between isolates.
class IsolateMessage {
  /// Creates an isolate message payload.
  const IsolateMessage(this.type, {this.data, this.transferable});

  /// Message discriminator.
  final IsolateMessageType type;

  /// Optional custom message data.
  final Object? data;

  /// Optional transferred typed-data payload.
  final TransferableTypedData? transferable;
}

/// Message types for isolate communication.
enum IsolateMessageType {
  /// Initialize the compute isolate with buffer information.
  initialize,

  /// Compute a new frame with the provided input.
  computeFrame,

  /// Shutdown the compute isolate.
  shutdown,

  /// Buffer transfer from compute to owner isolate.
  bufferTransfer,
}

/// Arguments passed to the compute isolate entry point.
class _ComputeIsolateArgs {
  const _ComputeIsolateArgs(this.sendPort, this.bufferSizeBytes);

  final SendPort sendPort;
  final int bufferSizeBytes;
}
