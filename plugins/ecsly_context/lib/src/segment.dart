/// Mechanical, product-agnostic clause segmentation over plain text.
///
/// Memory-shaped lines (agent notes, summaries, log bullets) are compound:
/// clauses joined by `;` and `. `, usually under a topic prefix before the
/// first `:`, with a small closed marker vocabulary (`blocker:`, `LANDED`,
/// `next =`, ...). Because that shape is known, the decomposition is
/// mechanical: no model, no NLP, deterministic on the same input.
///
/// The law mirrors the graph's: clauses are verbatim char spans of the
/// source text — never rewritten, truncated or merged. A consumer reads the
/// char range `[clause.start, clause.end)` and gets exactly [TextClause.text];
/// segmentation is a projection, the source stays untouched.
///
/// The grammar, applied in order:
/// 1. A leading date token (`yyyy-mm-dd` or `mm-dd` or `mm-dd..mm-dd`)
///    followed by a separator is stripped into [TextSegmentation.dateToken].
/// 2. A leading topic prefix (letter-starting word, then `: `) at depth
///    zero becomes [TextSegmentation.topic] and is stripped from clause 1;
///    marker words (`blocker:`, `next:`) are never taken as the topic.
/// 3. The body splits at depth-zero `;` always, and at `.` when it ends a
///    sentence: the next char is whitespace or end-of-text, the char before
///    is not a digit or another dot (so versions `v0.0.18` and decimals
///    `3.5` hold), and the first non-space char after is not a digit.
///    Nothing splits inside parens, brackets or quotes.
/// 4. Each clause gets a mechanical [ClauseKind] from closed marker tables
///    — a leading open/action marker wins, then a done word anywhere, else
///    fact. Kinds are hints from word shape, not semantics.
library;

/// The mechanical kind of a [TextClause].
enum ClauseKind {
  /// An open thread: blocker, queue, todo, gap, pending, failure.
  open,

  /// A settled outcome: landed, proven, shipped, merged, fixed, passing.
  done,

  /// A directive: next step, fix, run command, plan.
  action,

  /// Anything else — the default.
  fact,
}

/// One verbatim clause: a char span of the segmented source text.
final class TextClause {
  const TextClause._(
    this.index,
    this.start,
    this.end,
    this.text,
    this.kind,
  );

  /// 1-based position of this clause within its segmentation.
  final int index;

  /// Char offset into the source text where the clause starts (inclusive).
  final int start;

  /// Char offset into the source text where the clause ends (exclusive).
  final int end;

  /// The clause text: exactly the source's char range `[start, end)`.
  final String text;

  /// The mechanical kind assigned by the marker tables.
  final ClauseKind kind;

  @override
  String toString() => 'c$index[${kind.name}] $text';
}

/// The result of segmenting one source text.
final class TextSegmentation {
  const TextSegmentation._(
    this.source,
    this.dateToken,
    this.topic,
    this.clauses,
  );

  /// The verbatim input this segmentation came from.
  final String source;

  /// The leading date token (`yyyy-mm-dd`, `mm-dd`, `mm-dd..mm-dd`), or the
  /// empty string when the text has none. Stripped from clause 1 only.
  final String dateToken;

  /// The line-level topic prefix (`codemap sprints12-18` in
  /// `codemap sprints12-18: census flywheel`), or null. Marker words are
  /// never taken as the topic. Every clause inherits it.
  final String? topic;

  /// The clauses, in source order, 1-based ([TextClause.index]).
  final List<TextClause> clauses;

  /// Clauses of one kind (the filter shape search layers need).
  Iterable<TextClause> clausesOf(final ClauseKind kind) =>
      clauses.where((final clause) => clause.kind == kind);

  @override
  String toString() =>
      'TextSegmentation(topic=${topic ?? '-'}, clauses=${clauses.length})';
}

/// Leading markers that type a clause [ClauseKind.open]: an open thread.
const List<String> clauseOpenMarkers = <String>[
  'blocker',
  'blockers',
  'open',
  'queue',
  'todo',
  'gap',
  'pending',
  'missing',
  'fails',
  'failing',
  'broken',
];

/// Leading markers that type a clause [ClauseKind.action]: a directive.
const List<String> clauseActionMarkers = <String>[
  'next',
  'fix',
  'fixme',
  'run',
  'plan',
  'then',
];

/// Words anywhere in a clause that type it [ClauseKind.done]: a settled
/// outcome. Checked only when no leading open/action marker matched.
const List<String> clauseDoneWords = <String>[
  'landed',
  'proven',
  'shipped',
  'merged',
  'closed',
  'fixed',
  'resolved',
  'done',
  'passes',
  'passing',
  'green',
  'completed',
  'achieved',
];

final RegExp _dateToken = RegExp(
  r'^(\d{4}-\d{2}-\d{2}|\d{2}-\d{2}(\.\.(\d{2}-)?\d{2})?)(?=[\s:]\s*\S|$)',
);

final RegExp _wordPattern = RegExp("[a-z0-9]+(?:'[a-z]+)?");

/// Segments [source] into mechanical clauses (see the library grammar).
///
/// Pure and deterministic: the same text always yields the same clauses,
/// and every clause satisfies `text == the source's chars in [start, end)`.
TextSegmentation segmentText(final String source) {
  final units = source.codeUnits;
  var bodyStart = 0;
  var dateToken = '';
  final dateMatch = _dateToken.firstMatch(source);
  if (dateMatch != null) {
    dateToken = dateMatch.group(0)!.trim();
    bodyStart = dateMatch.end;
  }
  while (bodyStart < source.length && _isSpace(source, bodyStart)) {
    bodyStart += 1;
  }

  var topicStart = bodyStart;
  String? topic;
  final colon = _topicColon(source, bodyStart);
  if (colon != null) {
    final candidate = _copyChars(source, bodyStart, colon).trim();
    final lowered = candidate.toLowerCase();
    final isTopicShaped =
        candidate.isNotEmpty &&
        candidate.length <= 40 &&
        _hasLetter(candidate) &&
        !_openMarkers.contains(lowered) &&
        !_actionMarkers.contains(lowered);
    if (isTopicShaped) {
      topic = candidate;
      topicStart = colon + 1;
    }
  }

  final clauses = <TextClause>[];
  var clauseIndex = 0;
  var clauseStart = topicStart;
  var depth = 0;
  var quote = false;
  for (var i = topicStart; i < source.length; i++) {
    final char = source[i];
    switch (char) {
      case '(' || '[' || '{' when !quote:
        depth += 1;
      case ')' || ']' || '}' when !quote:
        depth = depth > 0 ? depth - 1 : 0;
      case "'" || '"' when depth == 0:
        quote = !quote;
      case ';' when depth == 0 && !quote:
        clauseIndex = _emit(
          units,
          source,
          clauseStart,
          i,
          ++clauseIndex,
          clauses,
        );
        clauseStart = i + 1;
      case '.' when _endsSentence(source, i):
        clauseIndex = _emit(
          units,
          source,
          clauseStart,
          i,
          ++clauseIndex,
          clauses,
        );
        clauseStart = i + 1;
    }
  }
  _emit(units, source, clauseStart, source.length, ++clauseIndex, clauses);
  return TextSegmentation._(source, dateToken, topic, clauses);
}

/// Emits the clause for the span `[start, end)` when it survives trimming;
/// returns the next clause index to use.
int _emit(
  final List<int> units,
  final String source,
  final int rawStart,
  final int rawEnd,
  final int index,
  final List<TextClause> clauses,
) {
  var start = rawStart;
  var end = rawEnd;
  while (start < end && _isSpace(source, start)) {
    start += 1;
  }
  while (end > start && _isSpace(source, end - 1)) {
    end -= 1;
  }
  if (start >= end) {
    return index - 1;
  }
  // A verbatim range copy without the substring-to-fit primitive the
  // design law forbids: one native pass over the precomputed code units.
  final text = String.fromCharCodes(units, start, end);
  clauses.add(TextClause._(index, start, end, text, _classify(text)));
  return index;
}

/// Copies a short char range (topic candidates, abbreviations).
String _copyChars(final String source, final int start, final int end) {
  final buffer = StringBuffer();
  for (var i = start; i < end; i++) {
    buffer.writeCharCode(source.codeUnitAt(i));
  }
  return buffer.toString();
}

ClauseKind _classify(final String text) {
  final lowered = text.toLowerCase();
  final words = _wordPattern
      .allMatches(lowered)
      .map((final match) => match.group(0)!)
      .toList();
  if (words.isEmpty) {
    return ClauseKind.fact;
  }
  final first = words.first;
  if (_openMarkers.contains(first)) {
    return ClauseKind.open;
  }
  if (_actionMarkers.contains(first)) {
    return ClauseKind.action;
  }
  for (final word in words) {
    if (_doneWords.contains(word)) {
      return ClauseKind.done;
    }
  }
  return ClauseKind.fact;
}

/// Whether the `.` at [dot] ends a sentence: the next char is whitespace or
/// end-of-text, the dot is not part of a number or an ellipsis, and the
/// first non-space char after is not a digit (which would make it an
/// ordered-list marker like `. 2`).
bool _endsSentence(final String source, final int dot) {
  if (dot == 0) {
    return false;
  }
  final before = source[dot - 1];
  if (before == '.' || _isDigit(before)) {
    return false;
  }
  if (_abbreviationBefore(source, dot)) {
    return false;
  }
  var cursor = dot + 1;
  while (cursor < source.length && _isSpace(source, cursor)) {
    cursor += 1;
  }
  if (cursor == dot + 1 && cursor < source.length) {
    return false; // no whitespace after the dot: not a sentence end
  }
  if (cursor >= source.length) {
    return true;
  }
  return !_isDigit(source[cursor]);
}

/// Whether the word ending at [dot] is a known abbreviation (`e.g`, `i.e`,
/// `etc`, `vs`, `cf`, `approx`), whose dot never ends a sentence.
bool _abbreviationBefore(final String source, final int dot) {
  var start = dot;
  while (start > 0) {
    final char = source[start - 1];
    final isWord =
        (char.codeUnitAt(0) >= 0x61 && char.codeUnitAt(0) <= 0x7a) ||
        (char.codeUnitAt(0) >= 0x41 && char.codeUnitAt(0) <= 0x5a) ||
        char == '.';
    if (!isWord) {
      break;
    }
    start -= 1;
  }
  if (start == dot) {
    return false;
  }
  return _abbreviations.contains(_copyChars(source, start, dot).toLowerCase());
}

const Set<String> _abbreviations = <String>{
  'e.g',
  'i.e',
  'etc',
  'vs',
  'cf',
  'approx',
};

/// Finds the topic colon: the first depth-zero `:` at or after [from],
/// unless the run before it breaks topic shape — a clause separator, a
/// quote, a sentence dot (version dots continue), or a URL scheme
/// (`://`). Returns the colon index, or null when there is no topic.
int? _topicColon(final String source, final int from) {
  for (var i = from; i < source.length; i++) {
    switch (source[i]) {
      case ':' when i + 1 >= source.length || source[i + 1] != '/':
        return i;
      case ';' || '(' || '[' || '{' || "'" || '"' || '\n':
        return null;
      case '.':
        // A dot at the very end cannot continue a word — there is no
        // next char to check, and probing past the last index would
        // throw (text ending in a bare sentence dot, e.g. a plain
        // one-liner memory with no topic colon).
        final continues =
            i > 0 &&
            i + 1 < source.length &&
            _isWordChar(source[i - 1]) &&
            _isWordChar(source[i + 1]);
        if (!continues) {
          return null;
        }
    }
  }
  return null;
}

bool _isWordChar(final String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a);
}

bool _hasLetter(final String text) {
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if ((code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a)) {
      return true;
    }
  }
  return false;
}

bool _isSpace(final String source, final int index) {
  final char = source.codeUnitAt(index);
  return char == 0x20 || char == 0x09;
}

bool _isDigit(final String char) =>
    char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

final Set<String> _openMarkers = clauseOpenMarkers.toSet();
final Set<String> _actionMarkers = clauseActionMarkers.toSet();
final Set<String> _doneWords = clauseDoneWords.toSet();
