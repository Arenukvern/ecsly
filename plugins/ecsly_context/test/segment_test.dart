import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

void main() {
  group('verbatim spans', () {
    test('every clause is exactly source.substring(start, end)', () {
      const text = 'topic: alpha does x; beta lands y. Gamma opens z';
      final segmentation = segmentText(text);
      expect(segmentation.source, text);
      for (final clause in segmentation.clauses) {
        expect(text.substring(clause.start, clause.end), clause.text);
      }
    });

    test('segments are a projection: source is never rewritten', () {
      const text = 'a; b. c';
      final segmentation = segmentText(text);
      expect(segmentation.clauses.map((final c) => c.text), <String>[
        'a',
        'b',
        'c',
      ]);
    });

    test('clause indexes are 1-based and contiguous', () {
      final segmentation = segmentText('one; two; three');
      expect(
        segmentation.clauses.map((final c) => c.index),
        <int>[1, 2, 3],
      );
    });
  });

  group('split grammar', () {
    test('splits at depth-zero semicolons and sentence dots', () {
      final segmentation = segmentText(
        'first clause; second clause. Third clause; fourth',
      );
      expect(segmentation.clauses.map((final c) => c.text), <String>[
        'first clause',
        'second clause',
        'Third clause',
        'fourth',
      ]);
    });

    test('keeps semicolons and dots inside parens', () {
      final segmentation = segmentText('outer (inner; kept) tail. next');
      expect(segmentation.clauses.map((final c) => c.text), <String>[
        'outer (inner; kept) tail',
        'next',
      ]);
    });

    test('keeps version numbers and decimals whole', () {
      final segmentation = segmentText(
        'shipped v0.0.18 with 3.5 ms latency and 1.2k users',
      );
      expect(segmentation.clauses, hasLength(1));
      expect(segmentation.clauses.single.text,
          'shipped v0.0.18 with 3.5 ms latency and 1.2k users');
    });

    test('keeps ellipses whole', () {
      final segmentation = segmentText('waited... then retried');
      expect(segmentation.clauses, hasLength(1));
    });

    test('does not split at common abbreviations', () {
      final segmentation = segmentText(
        'the parser (e.g. the fold) improved; etc. follows later',
      );
      expect(segmentation.clauses.first.text,
          'the parser (e.g. the fold) improved');
      expect(segmentation.clauses, hasLength(2));
    });

    test('empty and separator-only texts yield no clauses', () {
      expect(segmentText('').clauses, isEmpty);
      expect(segmentText('  ;  .  ').clauses, isEmpty);
    });
  });

  group('date token and topic prefix', () {
    test('strips a leading mm-dd..dd date token', () {
      final segmentation = segmentText('10-01..04 all lanes: plagiarism CI');
      expect(segmentation.dateToken, '10-01..04');
      expect(segmentation.topic, 'all lanes');
      expect(segmentation.clauses.first.text, 'plagiarism CI');
    });

    test('strips a leading iso date token', () {
      final segmentation = segmentText('2026-10-06 shipped the fold fix');
      expect(segmentation.dateToken, '2026-10-06');
      expect(segmentation.topic, isNull);
      expect(segmentation.clauses.first.text, 'shipped the fold fix');
    });

    test('marker words are never taken as the topic', () {
      final segmentation = segmentText('blocker: the seat wedged; open: two');
      expect(segmentation.topic, isNull);
      expect(segmentation.clauses.first.kind, ClauseKind.open);
    });

    test('a url scheme is not a topic', () {
      final segmentation = segmentText('see https://example.com/x for logs');
      expect(segmentation.topic, isNull);
    });

    test('every clause inherits the topic', () {
      final segmentation = segmentText('codemap: census flywheel; gates green');
      expect(segmentation.topic, 'codemap');
      expect(segmentation.clauses.map((final c) => c.text), <String>[
        'census flywheel',
        'gates green',
      ]);
    });
  });

  group('mechanical kinds', () {
    test('leading open markers type open clauses', () {
      expect(
        segmentText('blocker: seat wedged').clauses.single.kind,
        ClauseKind.open,
      );
      expect(
        segmentText('queue: two reviews').clauses.single.kind,
        ClauseKind.open,
      );
    });

    test('leading action markers type action clauses', () {
      expect(
        segmentText('next = rerun the ladder').clauses.single.kind,
        ClauseKind.action,
      );
      expect(
        segmentText('run: just check xsoulspace_optmem').clauses.single.kind,
        ClauseKind.action,
      );
    });

    test('done words anywhere type done clauses', () {
      expect(
        segmentText('span text at any zoom PROVEN live').clauses.single.kind,
        ClauseKind.done,
      );
      expect(
        segmentText('the migration landed on tuesday').clauses.single.kind,
        ClauseKind.done,
      );
    });

    test('leading markers win over done words', () {
      expect(
        segmentText('gap: the landing is delayed').clauses.single.kind,
        ClauseKind.open,
      );
    });

    test('plain statements are facts', () => expect(
          segmentText('the store holds 984 events').clauses.single.kind,
          ClauseKind.fact,
        ));

    test('kind filter projects one kind', () {
      final segmentation = segmentText(
        'blocker: a; the fix landed. next = verify; plain note',
      );
      expect(
        segmentation.clausesOf(ClauseKind.open).map((final c) => c.text),
        <String>['blocker: a'],
      );
      expect(
        segmentation.clausesOf(ClauseKind.done).map((final c) => c.text),
        <String>['the fix landed'],
      );
    });

    test('a text ending in a bare sentence dot segments without throwing', () {
      // Regression: the topic scan probed one char past the last index
      // when the FIRST dot was the last character (families contracts
      // segment short one-liners like this every day).
      final segmentation = segmentText('Plain decision line.');
      expect(segmentation.clauses, hasLength(1));
      expect(segmentation.clauses.single.kind, ClauseKind.fact);
      expect(segmentation.topic, isNull);
      expect(segmentText('a dot. and more. tail.').clauses, hasLength(3));
    });
  });
}
