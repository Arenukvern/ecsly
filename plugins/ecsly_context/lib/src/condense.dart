/// The condensed projection of a segmented text: live clauses verbatim,
/// settled clauses named.
///
/// This is the VIEW-side answer to "does the vertical axis need its own
/// compression?" — it does not need a store transformation (nap-of-one-beat
/// is proven zero-value); it needs a projection that spends the frame on
/// what is still live. [condenseSegmentation] classifies a segmentation's
/// clauses into shown (open/action — the bleeding edges) and elided
/// (done/fact — settled memory), keeping every shown clause a verbatim
/// span and naming every elided one by clause index and kind, so nothing
/// disappears unnamed and `zoom <id>.<clause>` recovers any of it.
///
/// Like wake itself, this is a projection: the source text is never
/// rewritten and the segmentation stays computed, never persisted.
library;

import 'segment.dart';

/// The condensed view of one [TextSegmentation].
final class CondensedSegmentation {
  /// Creates a condensed view: the [shown] live clauses and the [elided]
  /// settled ones, in source order within each list.
  const CondensedSegmentation(this.shown, this.elided);

  /// The live clauses (open/action), verbatim, in source order.
  final List<TextClause> shown;

  /// The settled clauses (done/fact), named by index and kind.
  final List<TextClause> elided;

  /// Whether anything is elided at all (false → render the text whole).
  bool get hasElisions => elided.isNotEmpty;

  /// The elided clause indexes as a compact contiguous-range string
  /// (`c1-c3`, `c2`, `c1, c3`), the shape absence lines use.
  String get elidedNames {
    final names = <String>[];
    var index = 0;
    while (index < elided.length) {
      final start = elided[index].index;
      var end = start;
      while (index + 1 < elided.length &&
          elided[index + 1].index == end + 1) {
        index += 1;
        end += 1;
      }
      names.add(start == end ? 'c$start' : 'c$start-c$end');
      index += 1;
    }
    return names.join(', ');
  }

  /// The kinds present among the elided clauses, in enumeration order
  /// (`done, fact`) — the one-line "what was dropped" reason.
  String get elidedKinds {
    final kinds = <String>[];
    for (final kind in ClauseKind.values) {
      if (elided.any((final clause) => clause.kind == kind)) {
        kinds.add(kind.name);
      }
    }
    return kinds.join(', ');
  }
}

/// Classifies [segmentation] into shown live clauses and elided settled
/// ones. Pure: no text is rewritten, no clause is dropped.
CondensedSegmentation condenseSegmentation(
  final TextSegmentation segmentation,
) {
  final shown = <TextClause>[];
  final elided = <TextClause>[];
  for (final clause in segmentation.clauses) {
    switch (clause.kind) {
      case ClauseKind.open || ClauseKind.action:
        shown.add(clause);
      case ClauseKind.done || ClauseKind.fact:
        elided.add(clause);
    }
  }
  return CondensedSegmentation(shown, elided);
}
