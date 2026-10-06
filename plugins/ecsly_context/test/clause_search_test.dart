import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

import 'memory_store.dart';

/// Plain records: no beat type, no store — the API any product feeds.
const List<ClauseDoc> _records = <ClauseDoc>[
  ClauseDoc(
    id: 10,
    date: '2026-10-04',
    beatKind: 'summary',
    text: '10-01..04 harness: L0-L4 ladder closed, fasttest in skill; '
        'blocker: jev coordinator repeats focusId = J1 finding',
  ),
  ClauseDoc(
    id: 12,
    date: '2026-10-05',
    beatKind: 'raw',
    text: 'codemap: census flywheel landed, gates green each cycle; '
        'queue: is_null unlock and E0271 hoist',
  ),
  ClauseDoc(
    id: 13,
    date: '2026-10-06',
    beatKind: 'raw',
    text: 'plagiarism: cross-domain census found 0 twins; next = wire the '
        'structural section',
  ),
];

void main() {
  group('product-agnostic records', () {
    late final ClauseIndex index = ClauseIndex.build(_records);

    test('build segments every record', () {
      expect(index.docCount, 3);
      expect(index.clauseCount, 6);
    });

    test('token mode requires all tokens by default', () {
      final result = index.search(const ClauseQuery('jev focusId'));
      expect(result.totalHits, 1);
      expect(result.hits.single.doc.id, 10);
      expect(result.hits.single.clause.text,
          'blocker: jev coordinator repeats focusId = J1 finding');
      expect(result.hits.single.clause.kind, ClauseKind.open);
    });

    test('idf ranks coverage before recency', () {
      // 'census' appears in two records; 'flywheel' only in #12, so the
      // all-token hit on #12 must outrank the single-token hit on #13.
      final result = index.search(
        const ClauseQuery('census flywheel', requireAll: false),
      );
      expect(result.hits.first.doc.id, 12);
    });

    test('any-token mode widens the match', () {
      final all = index.search(
        const ClauseQuery('census flywheel', requireAll: false),
      );
      final any = index.search(
        const ClauseQuery('census flywheel', requireAll: false, cap: 100),
      );
      expect(any.totalHits, all.totalHits);
      final strict = index.search(const ClauseQuery('census flywheel'));
      expect(strict.totalHits, lessThan(any.totalHits));
    });

    test('regex mode matches clause text directly', () {
      final result = index.search(const ClauseQuery('E0271', regex: true));
      expect(result.totalHits, 1);
      expect(result.hits.single.clause.text,
          'queue: is_null unlock and E0271 hoist');
      expect(result.hits.single.clause.kind, ClauseKind.open);
    });

    test('kind filter keeps only matching clauses', () {
      final result = index.search(
        const ClauseQuery('census', clauseKinds: {ClauseKind.open}),
      );
      expect(result.totalHits, 0);
      final blockers = index.search(
        const ClauseQuery('jev', clauseKinds: {ClauseKind.open}),
      );
      expect(blockers.totalHits, 1);
    });

    test('topic and beat-kind filters select records', () {
      final codemap = index.search(
        const ClauseQuery('census', topics: {'codemap'}),
      );
      expect(codemap.totalHits, greaterThanOrEqualTo(1));
      expect(
        codemap.hits.every((final hit) => hit.doc.id == 12),
        isTrue,
      );
      final raws = index.search(
        const ClauseQuery('census', beatKinds: {'raw'}),
      );
      expect(raws.totalHits, greaterThanOrEqualTo(1));
      final summaries = index.search(
        const ClauseQuery('census', beatKinds: {'summary'}),
      );
      expect(summaries.totalHits, 0);
    });

    test('since/until bound the date window inclusively', () {
      final window = index.search(
        const ClauseQuery('census', since: '2026-10-05', until: '2026-10-05'),
      );
      expect(window.totalHits, greaterThanOrEqualTo(1));
      expect(window.hits.every((final hit) => hit.doc.date == '2026-10-05'),
          isTrue);
      final before = index.search(
        const ClauseQuery('census', until: '2026-10-03'),
      );
      expect(before.totalHits, 0);
    });

    test('cap with the named tail', () {
      final result = index.search(
        const ClauseQuery('census unlock finding landed green',
            requireAll: false, cap: 2),
      );
      expect(result.truncated, isTrue);
      expect(result.hits, hasLength(2));
      expect(result.truncationNotice, 'Newest 2 of ${result.totalHits} '
          'clause matches');
    });

    test('empty token query matches nothing', () {
      final result = index.search(const ClauseQuery(''));
      expect(result.totalHits, 0);
      expect(result.truncationNotice, isNull);
    });

    test('cap below one is a named argument error', () {
      expect(
        () => index.search(const ClauseQuery('census', cap: 0)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('graph-fed integration', () {
    test('graph beats flow through ClauseDoc unchanged', () {
      final graph = ContextGraph(MemoryStore());
      graph.append('2026-10-06', 'memo find shipped; bench numbers recorded. '
          'next = point the harness at it');
      graph.append('2026-10-06', 'unrelated note about boats');
      final docs = <ClauseDoc>[
        for (final beat in graph.state.beats.values)
          ClauseDoc(
            id: beat.id,
            date: beat.date,
            beatKind: beat.kind.name,
            text: beat.text,
          ),
      ];
      final index = ClauseIndex.build(docs);
      final result = index.search(const ClauseQuery('memo find shipped'));
      expect(result.totalHits, 1);
      expect(result.hits.single.clause.text, 'memo find shipped');
      // Clause grain: an AND query whose tokens live in different clauses
      // of the same record matches nothing — the precision recall loses.
      expect(
        index.search(const ClauseQuery('shipped recorded')).totalHits,
        0,
      );
      final actions = index.search(
        const ClauseQuery('harness', clauseKinds: {ClauseKind.action}),
      );
      expect(actions.totalHits, 1);
      expect(actions.hits.single.clause.text,
          'next = point the harness at it');
    });
  });
}
