import 'beat_kind.dart';

// All fields are final and beats are value objects; the lint's @immutable
// marker lives in package:meta, which this SDK-only package does not depend
// on.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// One immutable record in the context graph.
///
/// [text] is always the whole, verbatim stored text: the context core has no
/// substring-to-fit primitive and never rewrites, truncates or merges text.
/// Raw beats are permanent; derived beats (summaries, decompositions) are
/// rebuildable and forgettable. The only field any event ever flips is
/// [archived], and only on the original of a decomposition.
final class ContextBeat {
  /// Creates a beat. Prefer going through [ContextGraph]-driven events;
  /// beats are value objects and never mutated in place.
  ContextBeat({
    required this.id,
    required this.date,
    required this.text,
    this.threadId = 'main',
    this.kind = BeatKind.raw,
    final Iterable<int> summarizes = const <int>[],
    this.decomposedFrom,
    this.archived = false,
  }) : summarizes = List<int>.unmodifiable(summarizes);

  /// Monotonic, 1-based beat id. Never reused, even after a forget.
  final int id;

  /// ISO calendar date (`yyyy-mm-dd`).
  final String date;

  /// The whole stored text, verbatim and immutable.
  final String text;

  /// Conversation thread this beat belongs to.
  final String threadId;

  /// Raw, summary or decomposition.
  final BeatKind kind;

  /// Source beat ids (summaries only): typed provenance links.
  final List<int> summarizes;

  /// Original beat id (decompositions only): typed provenance link.
  final int? decomposedFrom;

  /// View filter: decompose marks its original archived. Archived originals
  /// persist verbatim and stay readable; they only leave the wake frame.
  final bool archived;

  /// Returns a copy with [archived] set to true. The only transformation
  /// any beat ever undergoes; text and provenance are never touched.
  ContextBeat toArchived() => ContextBeat(
    id: id,
    date: date,
    text: text,
    threadId: threadId,
    kind: kind,
    summarizes: summarizes,
    decomposedFrom: decomposedFrom,
    archived: true,
  );

  @override
  bool operator ==(final Object other) =>
      other is ContextBeat &&
      other.id == id &&
      other.date == date &&
      other.text == text &&
      other.threadId == threadId &&
      other.kind == kind &&
      other.archived == archived &&
      other.decomposedFrom == decomposedFrom &&
      _listEquals(other.summarizes, summarizes);

  @override
  int get hashCode => Object.hash(
    id,
    date,
    text,
    threadId,
    kind,
    archived,
    decomposedFrom,
    Object.hashAll(summarizes),
  );

  @override
  String toString() =>
      'ContextBeat(#$id $kind $date thread=$threadId archived=$archived)';

  static bool _listEquals(final List<int> a, final List<int> b) {
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
}
