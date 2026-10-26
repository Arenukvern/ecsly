// ignore_for_file: prefer_final_parameters

import 'fingerprint.dart';
import 'replay_entry.dart';

/// Envelope version for on-disk / wire replay logs.
const int replayLogFormatVersion = 1;

/// Metadata stored once at the front of a [ReplayLog].
class ReplayLogHeader {
  /// Creates a header.
  const ReplayLogHeader({
    required this.formatVersion,
    required this.fingerprints,
  });

  /// Format version (see [replayLogFormatVersion]).
  final int formatVersion;

  /// Build and schema fingerprints for drift detection.
  final ReplayFingerprints fingerprints;

  Map<String, Object?> toJson() => <String, Object?>{
    'formatVersion': formatVersion,
    'fingerprints': fingerprints.toJson(),
  };

  // ignore: prefer_constructors_over_static_methods
  static ReplayLogHeader fromJson(final Map<String, Object?> json) =>
      ReplayLogHeader(
        formatVersion:
            (json['formatVersion'] as num?)?.toInt() ?? replayLogFormatVersion,
        fingerprints: ReplayFingerprints.fromJson(
          (json['fingerprints'] as Map<String, Object?>?) ?? const {},
        ),
      );
}

/// Append-only replay log ordered by `(tick, seq)` with event-key index.
class ReplayLog {
  /// Creates an empty log.
  ReplayLog({required this.header}) : _entries = <ReplayEntry>[];

  /// Creates a log from existing rows (rebuilds index).
  ReplayLog.fromEntries({
    required this.header,
    required final List<ReplayEntry> entries,
  }) : _entries = List<ReplayEntry>.from(entries) {
    _rebuildIndex();
    _validateOrdering();
  }

  /// Log header (fingerprints, format version).
  final ReplayLogHeader header;

  final List<ReplayEntry> _entries;
  final Map<String, ReplayPosition> _eventIndex = <String, ReplayPosition>{};

  /// All entries in order.
  List<ReplayEntry> get entries => List<ReplayEntry>.unmodifiable(_entries);

  /// Next sequence number for [tick] (0 when tick advances).
  int nextSeqForTick(final int tick) {
    if (_entries.isEmpty) return 0;
    final last = _entries.last;
    if (last.tick == tick) return last.seq + 1;
    return 0;
  }

  /// Appends [entry], enforcing monotonic `(tick, seq)` and unique [eventKey].
  void append(final ReplayEntry entry) {
    if (_entries.isNotEmpty) {
      final last = _entries.last;
      if (entry.tick < last.tick) {
        throw StateError(
          'Replay log tick regressed from ${last.tick} to ${entry.tick}.',
        );
      }
      if (entry.tick == last.tick && entry.seq <= last.seq) {
        throw StateError(
          'Replay log seq must increase within tick ${entry.tick}.',
        );
      }
      if (entry.tick > last.tick && entry.seq != 0) {
        throw StateError(
          'First seq in a new tick must be 0 (got ${entry.seq} at tick '
          '${entry.tick}).',
        );
      }
    } else if (entry.seq != 0) {
      throw StateError('First replay entry must use seq 0.');
    }

    if (entry.eventKey != null) {
      if (_eventIndex.containsKey(entry.eventKey)) {
        throw StateError('Duplicate eventKey "${entry.eventKey}".');
      }
      _eventIndex[entry.eventKey!] = ReplayPosition.after(entry);
    }

    _entries.add(entry);
  }

  /// Removes entries at or after [position] and drops stale index rows.
  void truncateFrom(final ReplayPosition position) {
    var cut = _entries.length;
    for (var i = 0; i < _entries.length; i++) {
      if (!_entries[i].isBeforeOrAt(position.tick, position.seq)) {
        cut = i;
        break;
      }
    }
    if (cut >= _entries.length) return;
    _entries.removeRange(cut, _entries.length);
    _rebuildIndex();
  }

  /// Looks up `(tick, seq)` for [eventKey].
  ReplayPosition? positionForEventKey(final String eventKey) =>
      _eventIndex[eventKey];

  /// Last entry position, or null when empty.
  ReplayPosition? get lastPosition =>
      _entries.isEmpty ? null : ReplayPosition.after(_entries.last);

  Map<String, Object?> toJson() => <String, Object?>{
    'header': header.toJson(),
    'entries': _entries.map((final e) => e.toJson()).toList(growable: false),
  };

  // ignore: prefer_constructors_over_static_methods
  static ReplayLog fromJson(final Map<String, Object?> json) {
    final header = ReplayLogHeader.fromJson(
      (json['header'] as Map<String, Object?>?) ?? const {},
    );
    final raw = (json['entries'] as List<Object?>?) ?? const [];
    final entries = raw
        .whereType<Map<String, Object?>>()
        .map(ReplayEntry.fromJson)
        .toList(growable: false);
    return ReplayLog.fromEntries(header: header, entries: entries);
  }

  void _rebuildIndex() {
    _eventIndex.clear();
    for (final entry in _entries) {
      if (entry.eventKey == null) continue;
      _eventIndex[entry.eventKey!] = ReplayPosition.after(entry);
    }
  }

  void _validateOrdering() {
    for (var i = 1; i < _entries.length; i++) {
      if (_entries[i].compareTo(_entries[i - 1]) <= 0) {
        throw StateError('Replay log ordering violation at index $i.');
      }
    }
  }
}
