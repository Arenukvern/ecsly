import 'dart:math' as math;

import 'beat_kind.dart';
import 'context_beat.dart';
import 'context_event.dart';
import 'context_exception.dart';
import 'id_range.dart';

/// Immutable folded state of an event log.
///
/// State is always the fold of the append-only events; nothing here is
/// persisted as truth. All indexes — including the keyword index — are
/// rebuilt on every fold, so loading the same log twice yields an identical
/// state ([==] holds for equally-folded states).
// Value object with all-final fields; the lint's @immutable marker lives in
// package:meta, which this SDK-only package does not depend on.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
final class ContextState {
  /// An empty state: no beats, next id 1, empty indexes.
  ContextState.empty()
    : beats = const <int, ContextBeat>{},
      nextId = 1,
      keywordIndex = const <String, Set<int>>{};

  const ContextState._(this.beats, this.nextId, this.keywordIndex);

  /// Folds [events] in order onto an empty state.
  ///
  /// Single pass: events are applied to one working beat map and the
  /// keyword index is built once at the end — [fold]'s per-event index
  /// rebuild would make loading a log quadratic in its length.
  factory ContextState.foldAll(final Iterable<ContextEvent> events) {
    final working = <int, ContextBeat>{};
    var nextId = 1;
    for (final event in events) {
      nextId = _apply(working, nextId, event);
    }
    final index = _indexBeats(working.values);
    return ContextState._(
      Map<int, ContextBeat>.unmodifiable(working),
      nextId,
      Map<String, Set<int>>.unmodifiable(index),
    );
  }

  /// Live beats by id, ascending. Forgotten beats are gone; archived
  /// originals remain (they are permanent, only filtered from views).
  final Map<int, ContextBeat> beats;

  /// The next monotonic beat id. Never shrinks, even after a forget.
  final int nextId;

  /// Tokenized keyword index (lowercase word runs -> beat ids), rebuilt on
  /// every fold. Powers recall ranking; never persisted as truth.
  final Map<String, Set<int>> keywordIndex;

  /// Folds [event] into a new state. Pure: the receiver is unchanged.
  ///
  /// Throws [ContextEventException] when the event violates the log
  /// contract: non-monotonic ids, unknown provenance targets, forgetting
  /// unknown or raw beats.
  ///
  /// Cost note: the keyword index is rebuilt for the whole state per fold,
  /// so interactive single-event folds are O(beats). Bulk loading must go
  /// through [foldAll], which applies all events first and indexes once.
  ContextState fold(final ContextEvent event) {
    final newBeats = Map<int, ContextBeat>.of(beats);
    final next = _apply(newBeats, nextId, event);
    return ContextState._(
      newBeats,
      next,
      _indexBeats(newBeats.values),
    );
  }

  /// Folds [events] onto THIS state in a single pass: one working map and
  /// one index build, whatever the batch size. The batch append path for
  /// [ContextGraph.appendAll] — per-event folds would rebuild the index
  /// per event and go quadratic.
  ContextState foldMany(final Iterable<ContextEvent> events) {
    final working = Map<int, ContextBeat>.of(beats);
    var next = nextId;
    for (final event in events) {
      next = _apply(working, next, event);
    }
    return ContextState._(
      working,
      next,
      _indexBeats(working.values),
    );
  }

  /// Applies [event]'s mutation to the working [beats] map in place and
  /// returns the next id. One shared implementation so [fold] and
  /// [foldAll] enforce the identical log contract (non-monotonic ids,
  /// unknown provenance, forgetting unknown or raw beats).
  static int _apply(
    final Map<int, ContextBeat> beats,
    final int currentNextId,
    final ContextEvent event,
  ) {
    switch (event) {
      case BeatAppended():
        _requireMonotonicId(event.id, currentNextId);
        beats[event.id] = ContextBeat(
          id: event.id,
          date: event.date,
          text: event.text,
          threadId: event.threadId,
        );
      case SummaryAdded():
        _requireMonotonicId(event.id, currentNextId);
        final missing = event.summarizes
            .where((final sourceId) => !beats.containsKey(sourceId))
            .toList();
        if (missing.isNotEmpty) {
          throw ContextEventException(
            'summary #${event.id} references unknown source ids: '
            '${missing.join(', ')}',
          );
        }
        beats[event.id] = ContextBeat(
          id: event.id,
          date: event.date,
          text: event.text,
          threadId: event.threadId,
          kind: BeatKind.summary,
          summarizes: event.summarizes,
        );
      case DecompositionAdded():
        final original = beats[event.originalId];
        if (original == null) {
          throw ContextEventException(
            'decomposition references unknown original #${event.originalId}',
          );
        }
        var expectedChildId = currentNextId;
        for (final child in event.children) {
          if (child.id != expectedChildId) {
            throw ContextEventException(
              'non-monotonic decomposition child id #${child.id}; '
              'the log expects #$expectedChildId',
            );
          }
          expectedChildId += 1;
          beats[child.id] = ContextBeat(
            id: child.id,
            date: original.date,
            text: child.text,
            threadId: original.threadId,
            kind: BeatKind.decomposition,
            decomposedFrom: event.originalId,
          );
        }
        beats[event.originalId] = original.toArchived();
      case BeatForgotten():
        final beat = beats[event.id];
        if (beat == null) {
          throw ContextEventException('cannot forget unknown beat #${event.id}');
        }
        if (beat.kind == BeatKind.raw) {
          throw ContextEventException(
            'cannot forget raw beat #${event.id}: raw records are permanent',
          );
        }
        beats.remove(event.id);
      case BeatsArchived():
        final missing = event.ids
            .where((final id) => !beats.containsKey(id))
            .toList();
        if (missing.isNotEmpty) {
          throw ContextEventException(
            'archive references unknown beat ids: ${missing.join(', ')}',
          );
        }
        // View-archive only: flips the frame filter, never the content.
        for (final id in event.ids) {
          beats[id] = beats[id]!.toArchived();
        }
    }
    var maxId = currentNextId - 1;
    for (final id in beats.keys) {
      if (id > maxId) maxId = id;
    }
    return math.max(currentNextId, maxId + 1);
  }

  static void _requireMonotonicId(final int id, final int nextId) {
    if (id != nextId) {
      throw ContextEventException(
        'non-monotonic beat id #$id; the log expects #$nextId',
      );
    }
  }

  static Map<String, Set<int>> _indexBeats(
    final Iterable<ContextBeat> beats,
  ) {
    final index = <String, Set<int>>{};
    for (final beat in beats) {
      for (final token in tokenize(beat.text)) {
        index.putIfAbsent(token, () => <int>{}).add(beat.id);
      }
    }
    return index;
  }

  /// Contiguous id ranges covered by live, non-archived summaries, from
  /// their typed [ContextBeat.summarizes] provenance links.
  List<IdRange> get coverageRanges {
    final covered = <int>{};
    for (final beat in beats.values) {
      if (beat.kind == BeatKind.summary && !beat.archived) {
        covered.addAll(beat.summarizes);
      }
    }
    final ids = covered.toList()..sort();
    final ranges = <IdRange>[];
    var index = 0;
    while (index < ids.length) {
      final start = ids[index];
      var end = start;
      while (index + 1 < ids.length && ids[index + 1] == end + 1) {
        index += 1;
        end += 1;
      }
      ranges.add(IdRange(start, end));
      index += 1;
    }
    return ranges;
  }

  /// Tokenizes [text] for the keyword index: lowercase runs of ASCII letters
  /// and digits. Purely an index concern; text itself is never transformed
  /// for storage or rendering.
  static Set<String> tokenize(final String text) => _tokenPattern
      .allMatches(text.toLowerCase())
      .map((final match) => match.group(0)!)
      .toSet();

  static final RegExp _tokenPattern = RegExp('[a-z0-9]+');

  @override
  bool operator ==(final Object other) =>
      other is ContextState &&
      other.nextId == nextId &&
      _beatMapsEqual(other.beats, beats) &&
      _indexMapsEqual(other.keywordIndex, keywordIndex);

  @override
  int get hashCode => Object.hash(nextId, beats.length, keywordIndex.length);

  @override
  String toString() =>
      'ContextState(beats=${beats.length}, nextId=$nextId)';

  static bool _beatMapsEqual(
    final Map<int, ContextBeat> a,
    final Map<int, ContextBeat> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static bool _indexMapsEqual(
    final Map<String, Set<int>> a,
    final Map<String, Set<int>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) {
        return false;
      }
      final other = b[entry.key]!;
      if (other.length != entry.value.length ||
          !other.containsAll(entry.value)) {
        return false;
      }
    }
    return true;
  }
}
