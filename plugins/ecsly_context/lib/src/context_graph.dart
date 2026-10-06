import 'beat_kind.dart';
import 'bit_set.dart';
import 'clause_view.dart';
import 'context_beat.dart';
import 'context_event.dart';
import 'context_exception.dart';
import 'context_state.dart';
import 'context_store.dart';
import 'families.dart';
import 'id_range.dart';
import 'iso_date.dart';
import 'recall.dart';
import 'segment.dart';
import 'wake_view.dart';
import 'zoom.dart';

/// Default line budget for [ContextGraph.wake].
const int defaultWakeBudgetLines = 12;

/// Default match cap for [ContextGraph.recall].
const int defaultRecallCap = 20;

/// Facade over a [ContextStore]: the whole beat-graph context mechanism.
///
/// Design law — the API makes violations inexpressible:
/// - text is stored and rendered verbatim; there is no substring-to-fit
///   primitive here;
/// - budgets resolve by selection with named absences (id ranges, reasons,
///   covering summary ids);
/// - raw beats are permanent; only derived beats (summaries,
///   decompositions) are forgettable;
/// - every derived beat carries typed provenance
///   ([ContextBeat.summarizes] / [ContextBeat.decomposedFrom]).
final class ContextGraph {
  /// Wraps [store], replaying its events into the in-memory state.
  ContextGraph(final ContextStore store)
    : _store = store,
      _state = ContextState.foldAll(store.load());

  final ContextStore _store;
  ContextState _state;

  /// The current folded state (beats, next id, keyword index, coverage).
  ContextState get state => _state;

  /// Contiguous id ranges covered by live summaries.
  List<IdRange> get coverage => _state.coverageRanges;

  /// Appends a raw beat with ISO [date] and verbatim [text].
  ///
  /// The id is monotonic. Raw beats are permanent: they can never be
  /// forgotten. A `decompositionAdded` event (readable forever, no longer
  /// minted here — parts are clause addresses now, ADR 0073) archives its
  /// original out of the frame while the record persists verbatim.
  ContextBeat append(
    final String date,
    final String text, {
    final String threadId = 'main',
  }) {
    final event = BeatAppended(
      id: _state.nextId,
      date: validateIsoDate(date),
      text: text,
      threadId: threadId,
    );
    return _commit(event, () => _state.beats[event.id]!);
  }

  /// Appends a batch of pre-built [events] under one durable store flush
  /// and one fold — the import/migration path. Event ids must continue
  /// the current id sequence contiguously (the fold validates it).
  List<ContextBeat> appendAll(final List<ContextEvent> events) {
    if (events.isEmpty) return const <ContextBeat>[];
    final stored = List<ContextEvent>.unmodifiable(events);
    _store.appendAll(stored);
    _state = _state.foldMany(stored);
    return <ContextBeat>[
      for (final event in stored)
        if (event is BeatAppended) _state.beats[event.id]!,
    ];
  }

  /// Derives a summary beat over [sourceIds]; the sources stay untouched.
  ///
  /// All source ids must exist ([UnknownBeatException] names the missing
  /// ones). The summary inherits date and thread from the newest source, and
  /// records its typed provenance in [ContextBeat.summarizes].
  ContextBeat derive(final List<int> sourceIds, final String text) {
    if (sourceIds.isEmpty) {
      throw const ContextEventException(
        'derive requires at least one source id',
      );
    }
    final missing = sourceIds
        .where((final id) => !_state.beats.containsKey(id))
        .toList();
    if (missing.isNotEmpty) {
      throw UnknownBeatException(missing);
    }
    var newest = _state.beats[sourceIds.first]!;
    for (final id in sourceIds.skip(1)) {
      final candidate = _state.beats[id]!;
      if (candidate.id > newest.id) {
        newest = candidate;
      }
    }
    final event = SummaryAdded(
      id: _state.nextId,
      date: newest.date,
      text: text,
      threadId: newest.threadId,
      summarizes: List<int>.unmodifiable(sourceIds),
    );
    return _commit(event, () => _state.beats[event.id]!);
  }

  /// Forgets a derived beat. Raw beats are refused with
  /// [RawBeatForgetException]; forgetting never cascades and never touches
  /// raw records.
  void forget(final int derivedBeatId) {
    final beat = _state.beats[derivedBeatId];
    if (beat == null) {
      throw UnknownBeatException([derivedBeatId]);
    }
    if (beat.kind == BeatKind.raw) {
      throw RawBeatForgetException(derivedBeatId);
    }
    _commit(BeatForgotten(id: derivedBeatId), () {});
  }

  /// View-archives [ids]: they leave the projected frame (wake, coverage)
  /// but persist verbatim and stay readable via [read]/[zoom]. Lifecycle
  /// selection, never destruction; every id must exist.
  void archive(final List<int> ids) {
    if (ids.isEmpty) return;
    _commit(BeatsArchived(ids: List<int>.unmodifiable(ids)), () {});
  }

  /// Reads the full beat at [id], or null when it does not exist.
  ContextBeat? read(final int id) => _state.beats[id];

  /// Projects the newest-first wake view within [budgetLines].
  ///
  /// The latest raw (or decomposition) beats render verbatim; older ranges
  /// render through the most coverage-providing summaries; everything else
  /// becomes a named [Absence]. [lines] never exceeds [budgetLines].
  WakeView wake({final int budgetLines = defaultWakeBudgetLines}) {
    if (budgetLines < 1) {
      throw ArgumentError.value(budgetLines, 'budgetLines', 'must be >= 1');
    }
    final beats = _state.beats.values.toList()
      ..sort((final a, final b) => a.id.compareTo(b.id));
    // Columnar membership: coverage and the rendered frame are bit sets
    // over the contiguous id space, so a summary's freshness test is a
    // word-AND instead of per-id hash lookups.
    final maxId = beats.isEmpty ? 0 : beats.last.id;
    final summaries = <ContextBeat>[];
    final covered = IdBitSet(maxId);
    for (final beat in beats) {
      // Archived summaries leave the frame entirely; their sources become
      // verbatim-visible again. Only live summaries provide coverage.
      if (beat.kind == BeatKind.summary && !beat.archived) {
        summaries.add(beat);
        covered.addAll(beat.summarizes);
      }
    }
    final lines = <WakeLine>[];
    final rendered = IdBitSet(maxId);
    for (final beat in beats.reversed) {
      if (lines.length == budgetLines) {
        break;
      }
      final excluded =
          beat.kind == BeatKind.summary ||
          beat.archived ||
          covered.contains(beat.id);
      if (excluded) {
        continue;
      }
      lines.add(WakeLine(beat: beat));
      rendered.add(beat.id);
    }
    // Detail decays with age: summaries are admitted newest-range first,
    // finest at a tie, so the frame spends its budget on the present and
    // collapses only the distant past (the classic cover order).
    int rangeEndOf(final ContextBeat summary) {
      var max = summary.summarizes.first;
      for (final id in summary.summarizes) {
        if (id > max) max = id;
      }
      return max;
    }

    final pending = List.of(summaries)
      ..sort((final a, final b) {
        final endA = rangeEndOf(a);
        final endB = rangeEndOf(b);
        if (endA != endB) return endB.compareTo(endA);
        return a.summarizes.length.compareTo(b.summarizes.length);
      });
    final pendingBits = <IdBitSet>[
      for (final summary in pending) IdBitSet(maxId)..addAll(summary.summarizes),
    ];
    while (lines.length < budgetLines && pending.isNotEmpty) {
      var chosenIndex = -1;
      for (var i = 0; i < pending.length; i++) {
        if (pendingBits[i].hasAnyOutside(rendered)) {
          chosenIndex = i;
          break;
        }
      }
      if (chosenIndex == -1) {
        break;
      }
      final chosen = pending.removeAt(chosenIndex);
      final chosenBits = pendingBits.removeAt(chosenIndex);
      lines.add(
        WakeLine(
          beat: chosen,
          rangeStart: chosen.summarizes.reduce(
            (final a, final b) => a < b ? a : b,
          ),
          rangeEnd: chosen.summarizes.reduce(
            (final a, final b) => a > b ? a : b,
          ),
        ),
      );
      rendered.union(chosenBits);
    }
    final absentIds = <int>[
      for (final beat in beats)
        if (beat.kind != BeatKind.summary &&
            !beat.archived &&
            !rendered.contains(beat.id))
          beat.id,
    ];
    final absences = <Absence>[];
    var index = 0;
    while (index < absentIds.length) {
      final start = absentIds[index];
      final startCovering = _coveringSummaryIds(summaries, start);
      var end = start;
      // A run continues while ids stay contiguous AND share the same
      // covering summaries, so a range always has one honest reason.
      while (index + 1 < absentIds.length &&
          absentIds[index + 1] == end + 1) {
        final nextCovering = _coveringSummaryIds(summaries, absentIds[index + 1]);
        if (_coveringEquals(nextCovering, startCovering)) {
          index += 1;
          end += 1;
        } else {
          break;
        }
      }
      absences.add(
        Absence(
          rangeStart: start,
          rangeEnd: end,
          reason: startCovering.isEmpty
              ? Absence.notSummarized
              : Absence.summarizedOutOfFrame,
          summaryIds: startCovering,
        ),
      );
      index += 1;
    }
    return WakeView(
      lines: List.unmodifiable(lines),
      absences: List.unmodifiable(absences),
      totalBeats: beats.length,
      budgetLines: budgetLines,
    );
  }

  /// Zooms [range] into its two halves: summaries for sub-ranges, raw for
  /// singles. Descend until [ZoomBeat] items appear.
  ZoomResult zoom(final IdRange range) {
    if (range.isSingle) {
      final beat = _state.beats[range.start];
      if (beat == null) {
        throw UnknownBeatException([range.start]);
      }
      return ZoomResult(range: range, items: <ZoomItem>[ZoomBeat(beat)]);
    }
    final half = range.length ~/ 2;
    final first = IdRange(range.start, range.start + half - 1);
    final second = IdRange(range.start + half, range.end);
    return ZoomResult(
      range: range,
      items: <ZoomItem>[_zoomHalf(first), _zoomHalf(second)],
    );
  }

  /// Projects behaviour-signature families over the live beats (meaning
  /// payload contract v1): ranked by fan-in with connections and member
  /// id ranges, capped at [cap] with a named `truncated` tail. A pure
  /// read projection — the graph, its events and its texts stay untouched.
  FamiliesView families({final int cap = defaultFamiliesCap}) =>
      buildFamilies(_state, cap: cap);

  /// Projects the beat at [id] into whole mechanical clauses within
  /// [budgetChars] — the part-grain view that replaced splitting a record
  /// into child beats (ADR 0073): the text stays one immutable record,
  /// parts are its clause addresses (`<id>.<c>`), and nothing is ever
  /// copied.
  ///
  /// Selection is whole-clause: a clause joins the frame only when it
  /// fits whole; everything else becomes a named elision carrying its
  /// address. The first clause always makes the frame — when it alone
  /// exceeds the budget the view says so instead of cutting it.
  ClauseView clauseView(final int id, {final int budgetChars = 1200}) {
    final beat = read(id);
    if (beat == null) {
      throw UnknownBeatException([id]);
    }
    if (budgetChars < 1) {
      throw ArgumentError.value(budgetChars, 'budgetChars', 'must be >= 1');
    }
    final segmentation = segmentText(beat.text);
    final shown = <TextClause>[];
    final elided = <TextClause>[];
    var spent = 0;
    var oversize = false;
    for (final clause in segmentation.clauses) {
      final cost = clause.end - clause.start;
      if (shown.isEmpty || spent + cost <= budgetChars) {
        shown.add(clause);
        spent += cost;
      } else {
        elided.add(clause);
      }
    }
    if (shown.length == 1 && spent > budgetChars) {
      oversize = true;
    }
    return ClauseView(
      beat: beat,
      shown: List.unmodifiable(shown),
      elided: List.unmodifiable(elided),
      budgetChars: budgetChars,
      firstClauseOversize: oversize,
    );
  }

  /// Recalls beats whose text matches [pattern], ranked by keyword score
  /// (query tokens present in the rebuilt keyword index) with newest id as
  /// the tie-break, capped at [cap] with a named
  /// `'Newest N of M matches'` tail.
  ///
  /// Archived beats are out of the search frame — the same lifecycle
  /// selection `wake` applies and the clause docs of `find` build with.
  /// [read] and [zoom] still reach them: archived records persist
  /// verbatim.
  RecallResult recall(
    final String pattern, {
    final int cap = defaultRecallCap,
  }) {
    if (cap < 1) {
      throw ArgumentError.value(cap, 'cap', 'must be >= 1');
    }
    final regex = RegExp(pattern);
    final queryTokens = ContextState.tokenize(pattern);
    final matches = <RecallMatch>[];
    for (final beat in _state.beats.values) {
      if (beat.archived || !regex.hasMatch(beat.text)) {
        continue;
      }
      var score = 0;
      for (final token in queryTokens) {
        if (_state.keywordIndex[token]?.contains(beat.id) ?? false) {
          score += 1;
        }
      }
      matches.add(RecallMatch(beat: beat, score: score));
    }
    matches.sort((final a, final b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return b.beat.id.compareTo(a.beat.id);
    });
    final kept = matches.length > cap ? matches.sublist(0, cap) : matches;
    return RecallResult(
      matches: List.unmodifiable(kept),
      totalMatches: matches.length,
    );
  }

  ZoomItem _zoomHalf(final IdRange half) {
    ContextBeat? best;
    for (final beat in _state.beats.values) {
      if (beat.kind != BeatKind.summary || !_coversAll(beat, half)) {
        continue;
      }
      if (best == null || beat.id > best.id) {
        best = beat;
      }
    }
    final covering = best;
    if (covering == null) {
      return ZoomRange(half);
    }
    return ZoomSummary(covering, half);
  }

  bool _coversAll(final ContextBeat summary, final IdRange range) {
    for (var id = range.start; id <= range.end; id++) {
      if (!summary.summarizes.contains(id)) {
        return false;
      }
    }
    return true;
  }

  List<int> _coveringSummaryIds(final List<ContextBeat> summaries, final int id) {
    final covering = <int>[
      for (final summary in summaries)
        if (summary.summarizes.contains(id)) summary.id,
    ]..sort();
    return covering;
  }

  bool _coveringEquals(final List<int> a, final List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  T _commit<T>(final ContextEvent event, final T Function() readBack) {
    _store.append(event);
    _state = _state.fold(event);
    return readBack();
  }
}
