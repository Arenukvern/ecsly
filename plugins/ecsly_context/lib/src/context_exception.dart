/// Base class of every named failure in the context core.
///
/// All errors are named: callers can distinguish unknown beats, raw-beat
/// forget refusals, log corruption, lock contention and replay violations.
abstract class ContextException implements Exception {
  /// Creates an exception with a human-readable [message].
  const ContextException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ContextException: $message';
}

/// One or more beat ids do not exist in the current state.
final class UnknownBeatException extends ContextException {
  /// Names the offending beat ids.
  UnknownBeatException(this.beatIds)
    : super('unknown beat ids: ${beatIds.join(', ')}');

  /// The ids that do not exist.
  final List<int> beatIds;
}

/// A derived beat was expected, but the id names a raw beat.
///
/// Raw records are permanent: forgetting never touches them.
final class RawBeatForgetException extends ContextException {
  /// Names the raw beat that cannot be forgotten.
  RawBeatForgetException(this.beatId)
    : super(
        'cannot forget raw beat #$beatId: raw records are permanent and '
        'only derived beats are forgettable',
      );

  /// The raw beat id.
  final int beatId;
}

/// An event violates the log contract during replay.
final class ContextEventException extends ContextException {
  /// Creates a replay failure with a describing [message].
  const ContextEventException(super.message);
}

/// The event log is corrupt beyond tail repair.
///
/// A corrupt final line is tail-repaired silently (it was never
/// acknowledged); corruption earlier in the log is named here instead.
final class ContextLogCorruptException extends ContextException {
  /// Names the log [path] and the 1-based [line] that cannot be read.
  ContextLogCorruptException(this.path, this.line, final String detail)
    : super('corrupt event log $path at line $line: $detail');

  /// Log file path.
  final String path;

  /// 1-based line number of the corruption.
  final int line;
}

/// The log's lockfile could not be acquired within the retry budget.
///
/// Another process holds the log; no second writer is allowed.
final class ContextLockException extends ContextException {
  /// Names the [lockPath] and the number of [attempts] made.
  ContextLockException(this.lockPath, this.attempts)
    : super('could not acquire lock $lockPath after $attempts attempts; '
        'another process holds the log');

  /// Lockfile path.
  final String lockPath;

  /// Number of acquisition attempts made before giving up.
  final int attempts;
}

/// A date is not a valid ISO calendar date (`yyyy-mm-dd`).
final class InvalidDateException extends ContextException {
  /// Names the offending [date].
  InvalidDateException(this.date)
    : super('invalid ISO date: "$date" (expected a real yyyy-mm-dd date)');

  /// The offending date string.
  final String date;
}
