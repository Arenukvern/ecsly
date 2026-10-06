import 'context_beat.dart';

/// One recall match: the beat and its keyword score.
final class RecallMatch {
  /// Creates a match. [score] is the number of query keywords present in
  /// the beat's indexed tokens.
  const RecallMatch({required this.beat, required this.score});

  /// The matching beat (text is the whole stored text, verbatim).
  final ContextBeat beat;

  /// Keyword score used for ranking (higher ranks first).
  final int score;
}

/// Result of [ContextGraph.recall]: ranked matches plus a named tail when
/// capped.
final class RecallResult {
  /// Creates a recall result.
  const RecallResult({required this.matches, required this.totalMatches});

  /// Returned matches (at most the recall cap).
  final List<RecallMatch> matches;

  /// Number of matches before capping.
  final int totalMatches;

  /// `'Newest N of M matches'` when capped; null when nothing was cut.
  String? get truncationNotice {
    if (totalMatches <= matches.length) {
      return null;
    }
    return 'Newest ${matches.length} of $totalMatches matches';
  }
}
