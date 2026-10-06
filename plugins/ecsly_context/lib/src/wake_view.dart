import 'context_beat.dart';

/// One rendered wake line: a whole stored text, never truncated.
///
/// [beat] is the source beat; [text] is its whole verbatim text. For summary
/// lines [rangeStart] and [rangeEnd] name the covered id range (rendered as
/// `#40-79 <text>`); verbatim lines leave them null.
final class WakeLine {
  /// Creates a line over [beat], optionally naming its coverage range.
  const WakeLine({required this.beat, this.rangeStart, this.rangeEnd});

  /// The beat this line renders.
  final ContextBeat beat;

  /// Lowest covered id (summary lines only).
  final int? rangeStart;

  /// Highest covered id (summary lines only).
  final int? rangeEnd;

  /// The whole stored text of [beat], verbatim.
  String get text => beat.text;
}

/// A named out-of-frame id range.
///
/// Budgets resolve by selection with named absences: every range that exists
/// but did not make the frame appears here with its id range, a reason, and
/// the ids of summaries that cover it, where present.
final class Absence {
  /// Creates a named absence over `[rangeStart, rangeEnd]`.
  const Absence({
    required this.rangeStart,
    required this.rangeEnd,
    required this.reason,
    this.summaryIds = const <int>[],
  });

  /// The reason constant for ranges no summary covers:
  /// `'not summarized, out of frame'`.
  static const String notSummarized = 'not summarized, out of frame';

  /// The reason constant for ranges a summary covers but whose summary line
  /// did not fit the budget: `'summarized, out of frame'`.
  static const String summarizedOutOfFrame = 'summarized, out of frame';

  /// Lowest absent beat id.
  final int rangeStart;

  /// Highest absent beat id.
  final int rangeEnd;

  /// Why the range is absent: [notSummarized] or [summarizedOutOfFrame].
  final String reason;

  /// Ids of the live summaries covering (part of) this range — the union
  /// over the range, sorted.
  final List<int> summaryIds;
}

/// The wake projection: the actor's decision view after a cold start.
///
/// Newest-first framing — latest raw (or decomposition) beats verbatim, older
/// ranges rendered through the most coverage-providing summaries, everything
/// else named in [absences]. [lines] never exceeds the requested budget.
final class WakeView {
  /// Creates a wake view.
  const WakeView({
    required this.lines,
    required this.absences,
    required this.totalBeats,
    required this.budgetLines,
  });

  /// Rendered lines, newest first, at most [budgetLines] of them.
  final List<WakeLine> lines;

  /// Named out-of-frame ranges, ascending.
  final List<Absence> absences;

  /// Number of live beats in the state (all kinds, including archived).
  final int totalBeats;

  /// The line budget this view was built with.
  final int budgetLines;
}
