import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'context_event.dart';
import 'context_exception.dart';
import 'context_store.dart';

/// [ContextStore] backed by a JSON Lines file: one event object per line.
///
/// Durability and multi-process safety:
/// - every [append] writes the encoded event plus a newline and fsyncs
///   before returning — the newline is the acknowledgement;
/// - an exclusive-create `<path>.lock` file guards the log; a second opener
///   retries [lockAttempts] times ([lockRetryDelay] apart), then fails with
///   [ContextLockException];
/// - [load] repairs a corrupt tail: a final line without a trailing newline
///   (or a final line that does not parse) was never acknowledged and is
///   truncated. Corruption earlier in the file is a
///   [ContextLogCorruptException], never silent.
final class JsonlEventLog implements ContextStore {
  JsonlEventLog._(
    this._path,
    this._lockPath,
    final RandomAccessFile log,
    final RandomAccessFile? lock, {
    this.readOnly = false,
  }) : _log = log,
       _lock = lock,
       _repaired = false;

  final String _path;
  final String _lockPath;

  /// Whether this handle is a lock-free reader ([openReadOnly]).
  final bool readOnly;
  RandomAccessFile? _log;
  RandomAccessFile? _lock;
  bool _repaired;
  bool _closed = false;

  static final Random _jitter = Random();

  /// Opens (creating if needed) the log at [path] and acquires its lock.
  ///
  /// Retries the exclusive lock creation [lockAttempts] times, waiting
  /// [lockRetryDelay] between attempts, then throws [ContextLockException].
  // ignore: prefer_constructors_over_static_methods -- async construction
  static Future<JsonlEventLog> open(
    final String path, {
    final int lockAttempts = 50,
    final Duration lockRetryDelay = const Duration(milliseconds: 20),
  }) async {
    final file = File(path);
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final lockPath = '$path.lock';
    RandomAccessFile? lock;
    for (var attempt = 1;; attempt++) {
      try {
        // Exclusive-create lockfile: refused while another process holds
        // the log (Dart's exclusive FileModes were removed from the SDK).
        File(lockPath).createSync(exclusive: true);
        lock = File(lockPath).openSync(mode: FileMode.write);
        break;
      } on FileSystemException {
        _stealIfStale(lockPath);
        if (attempt >= lockAttempts) {
          throw ContextLockException(lockPath, lockAttempts);
        }
        // Full-jitter backoff: contention resolves in one fsync, so a
        // bounded window with spread beats a fixed short spin.
        final base = lockRetryDelay.inMilliseconds;
        await Future<void>.delayed(
          Duration(milliseconds: base + _jitter.nextInt(base + 1)),
        );
      }
    }
    lock.writeStringSync('${DateTime.now().toIso8601String()} pid=$pid\n');
    lock.flushSync();
    final log = file.openSync(mode: FileMode.append);
    return JsonlEventLog._(path, lockPath, log, lock);
  }

  /// Opens the log for reading WITHOUT acquiring the writer lock: the log
  /// is append-only, so any number of readers may run against a writer.
  /// A torn final line (a writer died mid-append) is skipped as never
  /// acknowledged; only a writing [open] truncates it.
  static Future<JsonlEventLog> openReadOnly(final String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    final log = file.openSync(mode: FileMode.append);
    return JsonlEventLog._(
      path,
      '$path.lock',
      log,
      null,
      readOnly: true,
    );
  }

  /// Deletes the lockfile when its holder is provably dead — a crashed or
  /// SIGPIPE-killed process never reached [close], and its lock must not
  /// wedge the log forever. A lock without a readable `pid=` line (its
  /// writer is mid-creation) counts as live, as does a holder that answers
  /// `kill -0`, including another user's (`EPERM`).
  static void _stealIfStale(final String lockPath) {
    final file = File(lockPath);
    final String contents;
    try {
      contents = file.readAsStringSync();
    } on FileSystemException {
      return; // vanished between the failed create and this read: retry
    }
    final match = RegExp(r'pid=(\d+)').firstMatch(contents);
    if (match == null) return;
    final holder = int.parse(match.group(1)!);
    if (holder == pid) return;
    final probe = Process.runSync(
      'kill',
      <String>['-0', '$holder'],
      stderrEncoding: utf8,
    );
    final alive = probe.exitCode == 0 ||
        (probe.stderr as String).contains('Operation not permitted');
    if (alive) return;
    try {
      file.deleteSync();
    } on FileSystemException {
      // Lost the steal race; the next attempt sees a fresh lock.
    }
  }

  @override
  List<ContextEvent> load() {
    _requireOpen();
    if (!readOnly) {
      _repairTail();
    }
    final bytes = File(_path).readAsBytesSync();
    final lastNewline = bytes.lastIndexOf(_newline);
    final acknowledged = lastNewline + 1;
    final events = <ContextEvent>[];
    var start = 0;
    var lineNumber = 0;
    var truncateFrom = -1;
    while (start < acknowledged) {
      final newline = bytes.indexOf(_newline, start);
      lineNumber += 1;
      try {
        final line = utf8.decode(
          bytes.sublist(start, newline),
          allowMalformed: false,
        );
        if (line.trim().isNotEmpty) {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, Object?>) {
            throw const ContextEventException(
              'event line must be a JSON object',
            );
          }
          events.add(ContextEvent.fromJson(decoded));
        }
      } on FormatException catch (error) {
        // The final line was never acknowledged: repair the tail. Anything
        // earlier is real corruption and is named, never silent.
        if (newline != lastNewline) {
          throw ContextLogCorruptException(_path, lineNumber, error.message);
        }
        truncateFrom = start;
        break;
      } on ContextEventException catch (error) {
        if (newline != lastNewline) {
          throw ContextLogCorruptException(_path, lineNumber, error.message);
        }
        truncateFrom = start;
        break;
      }
      start = newline + 1;
    }
    if (truncateFrom != -1 && !readOnly) {
      _truncateTo(truncateFrom);
    }
    return events;
  }

  @override
  void append(final ContextEvent event) {
    appendAll(<ContextEvent>[event]);
  }

  @override
  void appendAll(final List<ContextEvent> events) {
    _requireOpen();
    _repairTail();
    final log = _log!;
    for (final event in events) {
      log.writeStringSync('${jsonEncode(event.toJson())}\n');
    }
    // One flush for the batch: a crash mid-batch leaves a prefix whose
    // partial final line is tail-repaired, so the contract (an event is
    // either fully acknowledged or absent) holds at batch granularity.
    log.flushSync();
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _log?.closeSync();
    _log = null;
    _lock?.closeSync();
    _lock = null;
    if (readOnly) {
      return; // no lock file was ever taken
    }
    final lockFile = File(_lockPath);
    if (lockFile.existsSync()) {
      lockFile.deleteSync();
    }
  }

  void _repairTail() {
    if (_repaired) {
      return;
    }
    final file = File(_path);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      final acknowledged = bytes.lastIndexOf(_newline) + 1;
      if (acknowledged != bytes.length) {
        _truncateTo(acknowledged);
      }
    }
    _repaired = true;
  }

  void _truncateTo(final int length) {
    final log = _log!;
    log.truncateSync(length);
    // The append handle's cursor sat at the old end of file; move it to the
    // new end so the next acknowledged append lands right after the last
    // valid line.
    log.setPositionSync(length);
    log.flushSync();
  }

  void _requireOpen() {
    if (_closed || _log == null) {
      throw StateError('JsonlEventLog at $_path is closed');
    }
  }

  static const int _newline = 0x0A;
}
