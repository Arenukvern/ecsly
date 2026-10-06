/// Clause-grain search over segmented documents: rg-style reach with
/// ranking and typed filters, rebuilt on the fly from plain records.
///
/// The API is deliberately product-agnostic: documents enter as
/// [ClauseDoc] records (an integer id, an ISO date, a product kind label,
/// verbatim text) — no beat type, no store, no tool concepts. Any product
/// segments its records with [segmentText] and feeds them here; the index
/// is cheap to rebuild per invocation, so the record store stays the only
/// truth and no derived index is ever persisted.
///
/// Two query modes share one result contract:
/// - token mode (default): query words must all be present (`requireAll`),
///   ranked by idf-weighted coverage, newest id as the tie-break;
/// - regex mode (`regex: true`): the pattern matches the clause text
///   directly, ranked newest first.
///
/// Results are capped with a named tail, mirroring the graph's recall law:
/// nothing is silently dropped — `Newest N of M clause matches` names the
/// cut.
library;

import 'dart:math' as math;

import 'context_state.dart';
import 'segment.dart';

/// One searchable record in product-agnostic shape.
final class ClauseDoc {
  /// Creates a document. [date] is an ISO calendar date (or empty);
  /// [beatKind] is the product's own kind label (`raw`, `summary`, ...),
  /// never interpreted by this package.
  const ClauseDoc({
    required this.id,
    required this.text,
    this.date = '',
    this.beatKind = '',
  });

  /// The product's record id (a beat id, a log line number, ...). Only
  /// ordering uses it: newer (larger) ids win ties.
  final int id;

  /// ISO calendar date the record belongs to, or the empty string.
  final String date;

  /// The product's kind label, passed through filters verbatim.
  final String beatKind;

  /// The whole record text, verbatim; clauses are char spans into it.
  final String text;
}

/// One matching clause: the record, the verbatim span, the score.
final class ClauseHit {
  /// Creates a hit. [score] is the idf-weighted token coverage, or 1.0 in
  /// regex mode.
  const ClauseHit(this.doc, this.clause, this.score);

  /// The record the clause came from.
  final ClauseDoc doc;

  /// The matching clause (a verbatim span of [ClauseDoc.text]).
  final TextClause clause;

  /// idf-weighted token coverage, or 1.0 in regex mode. Higher ranks first.
  final double score;

  @override
  String toString() => '#${doc.id}.c${clause.index}[${clause.kind.name}] '
      '${clause.text}';
}

/// The result of a [ClauseIndex.search]: ranked hits plus a named tail
/// when the cap cut anything.
final class ClauseSearchResult {
  /// Creates a result: the capped, ranked [hits] and the [totalHits] count
  /// before capping.
  const ClauseSearchResult(this.hits, this.totalHits);

  /// Returned hits (at most the query cap), ranked.
  final List<ClauseHit> hits;

  /// Number of matching clauses before capping.
  final int totalHits;

  /// Whether the cap cut matches.
  bool get truncated => totalHits > hits.length;

  /// `'Newest N of M clause matches'` when capped; null when nothing was
  /// cut.
  String? get truncationNotice {
    if (!truncated) {
      return null;
    }
    return 'Newest ${hits.length} of $totalHits clause matches';
  }
}

/// A clause-grain query over a [ClauseIndex].
final class ClauseQuery {
  /// Creates a query. The empty defaults mean "no filter".
  const ClauseQuery(
    this.query, {
    this.regex = false,
    this.requireAll = true,
    this.clauseKinds = const <ClauseKind>{},
    this.topics = const <String>{},
    this.beatKinds = const <String>{},
    this.since = '',
    this.until = '',
    this.cap = defaultClauseCap,
  });

  /// The query text: token words, or a regex pattern in regex mode.
  final String query;

  /// Whether [query] is a regular expression (matched case-insensitively,
  /// like the graph's recall) instead of tokens.
  final bool regex;

  /// Token mode: whether every query token must be present (true, the
  /// precise default) or any one suffices.
  final bool requireAll;

  /// Only clauses of these kinds; empty means all kinds.
  final Set<ClauseKind> clauseKinds;

  /// Only records whose [TextSegmentation.topic] equals one of these
  /// (case-insensitive); empty means all topics.
  final Set<String> topics;

  /// Only records whose [ClauseDoc.beatKind] equals one of these
  /// (case-insensitive); empty means all kinds.
  final Set<String> beatKinds;

  /// Inclusive lower ISO date bound; empty means unbounded.
  final String since;

  /// Inclusive upper ISO date bound; empty means unbounded.
  final String until;

  /// Maximum hits returned.
  final int cap;

  /// The default match cap.
  static const int defaultClauseCap = 20;
}

/// An in-memory clause index over [ClauseDoc] records: segments every
/// document once at build, indexes clause tokens for idf ranking, and
/// answers [search] queries. Pure data — rebuilt per invocation, never
/// persisted.
final class ClauseIndex {
  /// Builds the index: segments every document once and posts its clause
  /// tokens. Pure — nothing is written anywhere.
  ClauseIndex.build(final Iterable<ClauseDoc> docs) {
    for (final doc in docs) {
      final segmentation = segmentText(doc.text);
      for (final clause in segmentation.clauses) {
        final ordinal = _clauses.length;
        final tokens = ContextState.tokenize(clause.text);
        _clauses.add(_Entry(doc, segmentation.topic, clause, tokens));
        for (final token in tokens) {
          _postings.putIfAbsent(token, () => <int>[]).add(ordinal);
        }
      }
      if (segmentation.topic != null) {
        _topics.add(segmentation.topic!.toLowerCase());
      }
    }
    // idf over clauses: rare tokens are worth more. Every clause holding
    // the token shares the same weight, so scores stay comparable.
    _idf = <String, double>{
      for (final entry in _postings.entries)
        entry.key: math.log(1 + _clauses.length / entry.value.length),
    };
  }

  final List<_Entry> _clauses = <_Entry>[];
  final Map<String, List<int>> _postings = <String, List<int>>{};
  final Set<String> _topics = <String>{};
  late final Map<String, double> _idf;

  /// Number of indexed records.
  int get docCount => _clauses.isEmpty
      ? 0
      : _clauses.map((final entry) => entry.doc.id).toSet().length;

  /// Number of indexed clauses.
  int get clauseCount => _clauses.length;

  /// Distinct topics seen at build (lowercased).
  Set<String> get topics => Set<String>.unmodifiable(_topics);

  /// Runs [querySpec] against the index: filters first, then matching and
  /// ranking, then the cap. Deterministic; the same index and query always
  /// yield the same hits.
  ClauseSearchResult search(final ClauseQuery querySpec) {
    if (querySpec.cap < 1) {
      throw ArgumentError.value(querySpec.cap, 'cap', 'must be >= 1');
    }
    final queryTopics = <String>{
      for (final topic in querySpec.topics) topic.toLowerCase(),
    };
    final queryBeatKinds = <String>{
      for (final kind in querySpec.beatKinds) kind.toLowerCase(),
    };
    final RegExp? pattern;
    final List<String> tokens;
    if (querySpec.regex) {
      pattern = RegExp(querySpec.query, caseSensitive: false);
      tokens = const <String>[];
    } else {
      pattern = null;
      tokens = ContextState.tokenize(querySpec.query).toList()..sort();
    }

    var total = 0;
    final hits = <ClauseHit>[];
    for (var ordinal = 0; ordinal < _clauses.length; ordinal++) {
      final entry = _clauses[ordinal];
      final clause = entry.clause;
      if (querySpec.clauseKinds.isNotEmpty &&
          !querySpec.clauseKinds.contains(clause.kind)) {
        continue;
      }
      if (queryTopics.isNotEmpty &&
          (entry.topic == null ||
              !queryTopics.contains(entry.topic!.toLowerCase()))) {
        continue;
      }
      if (queryBeatKinds.isNotEmpty &&
          !queryBeatKinds.contains(entry.doc.beatKind.toLowerCase())) {
        continue;
      }
      if (querySpec.since.isNotEmpty &&
          (entry.doc.date.isEmpty || entry.doc.date.compareTo(querySpec.since) < 0)) {
        continue;
      }
      if (querySpec.until.isNotEmpty &&
          (entry.doc.date.isEmpty || entry.doc.date.compareTo(querySpec.until) > 0)) {
        continue;
      }
      final double score;
      if (pattern != null) {
        if (!pattern.hasMatch(clause.text)) {
          continue;
        }
        score = 1.0;
      } else {
        if (tokens.isEmpty) {
          continue;
        }
        var present = 0;
        var weight = 0.0;
        final clauseTokens = entry.tokens;
        for (final token in tokens) {
          if (clauseTokens.contains(token)) {
            present += 1;
            weight += _idf[token] ?? 0;
          }
        }
        if (present == 0 || (querySpec.requireAll && present < tokens.length)) {
          continue;
        }
        score = weight;
      }
      total += 1;
      final hit = ClauseHit(entry.doc, clause, score);
      if (hits.length < querySpec.cap) {
        hits.add(hit);
        if (hits.length == querySpec.cap) {
          hits.sort(_rank);
        }
      } else if (_rank(hit, hits.last) < 0) {
        hits[querySpec.cap - 1] = hit;
        hits.sort(_rank);
      }
    }
    if (hits.length < querySpec.cap) {
      hits.sort(_rank);
    }
    return ClauseSearchResult(List.unmodifiable(hits), total);
  }

  /// Ranks by score desc, then newest record, then latest clause.
  static int _rank(final ClauseHit a, final ClauseHit b) {
    if (a.score != b.score) {
      return b.score.compareTo(a.score);
    }
    if (a.doc.id != b.doc.id) {
      return b.doc.id.compareTo(a.doc.id);
    }
    return b.clause.index.compareTo(a.clause.index);
  }
}

final class _Entry {
  const _Entry(this.doc, this.topic, this.clause, this.tokens);
  final ClauseDoc doc;
  final String? topic;
  final TextClause clause;
  final Set<String> tokens;
}
