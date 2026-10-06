import 'context_beat.dart';
import 'segment.dart';

/// The whole-clause projection of one beat (ADR 0073): the record stays
/// one immutable text, its parts are clause addresses (`<id>.<c>`), and
/// nothing is ever copied into child beats.
///
/// Budgets resolve by selection: a clause joins the frame only when it
/// fits whole, and everything else is named here with its address —
/// `zoom <id>.<c>` recovers any of them. [firstClauseOversize] names the
/// one case a cut would be tempting (the first clause alone exceeds the
/// budget): the clause stays whole and the flag says so.
final class ClauseView {
  /// Creates a view. Prefer going through [ContextGraph.clauseView];
  /// clauses are value spans of the beat's immutable text.
  const ClauseView({
    required this.beat,
    required this.shown,
    required this.elided,
    required this.budgetChars,
    required this.firstClauseOversize,
  });

  /// The beat being viewed. [ContextBeat.text] stays the whole, verbatim
  /// record; the clauses below are verbatim char spans of it.
  final ContextBeat beat;

  /// Whole clauses in frame, source order.
  final List<TextClause> shown;

  /// Whole clauses out of frame, source order — the named elision.
  final List<TextClause> elided;

  /// The budget the view was built with.
  final int budgetChars;

  /// Whether the single shown clause alone exceeds [budgetChars] (it is
  /// still rendered whole — the flag exists so no consumer is tempted to
  /// cut it).
  final bool firstClauseOversize;

  /// Whether any clause was elided.
  bool get truncated => elided.isNotEmpty;

  /// The elided clauses' addresses (`<id>.<c>`), each recoverable via
  /// zoom.
  List<String> get elidedAddresses => <String>[
    for (final clause in elided) '${beat.id}.${clause.index}',
  ];

  /// The contract payload: ids, spans and counts — the beat's text only
  /// travels inside its clauses, whole.
  Map<String, Object?> toJson() => <String, Object?>{
    'beatId': beat.id,
    'threadId': beat.threadId,
    'beatKind': beat.kind.name,
    'budgetChars': budgetChars,
    'totalClauses': shown.length + elided.length,
    'shown': <Object?>[
      for (final clause in shown)
        <String, Object?>{
          'index': clause.index,
          'kind': clause.kind.name,
          'start': clause.start,
          'end': clause.end,
          'text': clause.text,
        },
    ],
    'elided': <Object?>[
      for (final clause in elided)
        <String, Object?>{
          'index': clause.index,
          'kind': clause.kind.name,
          'address': '${beat.id}.${clause.index}',
        },
    ],
    'firstClauseOversize': firstClauseOversize,
    'truncated': truncated,
  };

  @override
  String toString() =>
      'ClauseView(#${beat.id} shown=${shown.length} elided=${elided.length})';
}
