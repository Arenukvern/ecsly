import 'dart:async';
import 'dart:isolate';

import 'double_buffer.dart';

/// Manages isolate lifecycle and double-buffer coordination.
///
/// Handles the creation, communication, and cleanup of compute isolates
/// while maintaining the double buffering protocol.
class IsolateManager {
  /// Creates an isolate manager for the specified compute function.
  IsolateManager(this._computeEntryPoint);

  final void Function(_ComputeIsolateArgs) _computeEntryPoint;

  Isolate? _isolate;

  SendPort? _sendPort;

  DoubleBuffer? _doubleBuffer;

  StreamSubscription? _subscription;

  /// Gets the current render buffer (safe to read from main isolate).
  DoubleBuffer? get renderBuffer => _doubleBuffer;

  /// Sends input data to the compute isolate for processing.
  void computeFrame(final Object inputData) {
    if (_isolate == null) return;

    _sendToCompute(
      IsolateMessage(IsolateMessageType.computeFrame, data: inputData),
    );
  }

  /// Shuts down the compute isolate and cleans up resources.
  Future<void> shutdown() async {
    if (_isolate == null) return;

    _sendToCompute(const IsolateMessage(IsolateMessageType.shutdown));
    _isolate!.kill();
    await _subscription?.cancel();
    _isolate = null;
  }

  /// Starts the compute isolate and initializes double buffering.
  Future<void> start(final int bufferSizeBytes) async {
    _doubleBuffer = DoubleBuffer(bufferSizeBytes);

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _computeEntryPoint,
      _ComputeIsolateArgs(receivePort.sendPort, bufferSizeBytes),
    );

    _subscription = receivePort.listen(_handleMessage);
    _sendPort = receivePort.sendPort;

    // Send initial buffer to compute isolate
    _sendToCompute(
      IsolateMessage(
        IsolateMessageType.initialize,
        transferable: _doubleBuffer!.writeBuffer.transfer(),
      ),
    );
  }

  void _handleMessage(final Object? message) {
    if (message is IsolateMessage) {
      switch (message.type) {
        case IsolateMessageType.bufferTransfer:
          // Receive the computed buffer
          _doubleBuffer!.writeBuffer.receive(message.transferable!);
          _doubleBuffer!.swap();

          // Send the old read buffer back for next computation
          _sendToCompute(
            IsolateMessage(
              IsolateMessageType.initialize,
              transferable: _doubleBuffer!.writeBuffer.transfer(),
            ),
          );
        case IsolateMessageType.initialize:
        case IsolateMessageType.computeFrame:
        case IsolateMessageType.shutdown:
          // These messages are sent TO the compute isolate, not FROM it
          break;
      }
    }
  }

  void _sendToCompute(final IsolateMessage message) {
    _sendPort?.send(message);
  }
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

  /// Buffer transfer from compute to main isolate.
  bufferTransfer,
}

/// Arguments passed to the compute isolate entry point.
class _ComputeIsolateArgs {
  const _ComputeIsolateArgs(this.sendPort, this.bufferSizeBytes);

  final SendPort sendPort;
  final int bufferSizeBytes;
}
