// ignore_for_file: prefer_final_parameters

/// Kind of row stored in a [ReplayLog].
enum ReplayEntryKind {
  /// Recorded command with a full serialized outcome (see [commandOutcomeKey]).
  command,

  /// Optional input frame for deterministic games (replayed via host systems).
  input,
}

/// JSON key holding a [WorldSnapshot] map for command outcomes.
const String commandOutcomeKey = 'outcome';

/// JSON key for optional command label (harness-owned string).
const String commandLabelKey = 'label';

/// JSON key for input type name in [ReplayEntryKind.input] payloads.
const String inputTypeKey = 'inputType';

/// JSON key for arbitrary input payload map.
const String inputDataKey = 'data';

/// One ordered row in a replay log.
class ReplayEntry {
  /// Creates a replay entry.
  const ReplayEntry({
    required this.tick,
    required this.seq,
    required this.kind,
    required this.payload,
    this.eventKey,
  });

  /// Simulation tick (monotonic non-decreasing across the log).
  final int tick;

  /// Sequence within [tick] (strictly increasing when tick is unchanged).
  final int seq;

  /// Row kind (command vs input).
  final ReplayEntryKind kind;

  /// Kind-specific JSON payload (command outcome snapshot, input data, …).
  final Map<String, Object?> payload;

  /// Optional opaque correlation key (UTF-8 string or base64 in JSON).
  ///
  /// Harness encodes event ids, actors, parents, etc. here — ecsly_replay only
  /// indexes and seeks on this value.
  final String? eventKey;

  /// Total ordering key for log rows.
  int get orderingKey => Object.hash(tick, seq);

  /// Compares rows in log order.
  int compareTo(final ReplayEntry other) {
    final byTick = tick.compareTo(other.tick);
    if (byTick != 0) return byTick;
    return seq.compareTo(other.seq);
  }

  bool isBeforeOrAt(final int targetTick, final int targetSeq) =>
      tick < targetTick || (tick == targetTick && seq <= targetSeq);

  /// True when this row is strictly after [position].
  bool isAfterPosition(final ReplayPosition position) =>
      tick > position.tick ||
      (tick == position.tick && seq > position.seq);

  Map<String, Object?> toJson() => <String, Object?>{
    'tick': tick,
    'seq': seq,
    'kind': kind.name,
    'payload': payload,
    if (eventKey != null) 'eventKey': eventKey,
  };

  // ignore: prefer_constructors_over_static_methods
  static ReplayEntry fromJson(final Map<String, Object?> json) {
    final kindName = json['kind'] as String? ?? ReplayEntryKind.command.name;
    return ReplayEntry(
      tick: (json['tick'] as num?)?.toInt() ?? 0,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      kind: ReplayEntryKind.values.firstWhere(
        (final k) => k.name == kindName,
        orElse: () => ReplayEntryKind.command,
      ),
      payload: (json['payload'] as Map<String, Object?>?) ?? const {},
      eventKey: json['eventKey'] as String?,
    );
  }
}

/// Seek target: inclusive position in the log.
class ReplayPosition {
  /// Position after applying [entry].
  factory ReplayPosition.after(final ReplayEntry entry) =>
      ReplayPosition(tick: entry.tick, seq: entry.seq);

  /// Creates a replay position.
  const ReplayPosition({required this.tick, required this.seq});

  /// Tick component.
  final int tick;

  /// Sequence within [tick].
  final int seq;

  @override
  String toString() => 'ReplayPosition($tick, $seq)';
}
