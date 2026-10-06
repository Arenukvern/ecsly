import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

import 'memory_store.dart';

ContextGraph _graph() {
  final graph = ContextGraph(MemoryStore());
  graph.append('2026-10-01', 'wake budget framing');
  graph.append('2026-10-02', 'absence handling agreed');
  graph.append('2026-10-03', 'absence naming and absence ranges');
  graph.append('2026-10-04', 'unrelated beat about boats');
  return graph;
}

void main() {
  test('matches by regex, newest-first within a rank', () {
    final graph = _graph();
    final result = graph.recall('absence');
    expect(result.totalMatches, 2);
    expect(result.truncationNotice, isNull);
    expect(result.matches.map((final match) => match.beat.id), <int>[3, 2]);
  });

  test('keyword score ranks before recency', () {
    final graph = _graph();
    final result = graph.recall('absence|naming');
    // Beat 3 contains both keywords (score 2), beat 2 only one (score 1):
    // the score ranks before the newest-first tie-break.
    expect(result.matches.first.beat.id, 3);
    expect(result.matches.first.score, 2);
    expect(result.matches[1].beat.id, 2);
    expect(result.matches[1].score, 1);
    expect(result.totalMatches, 2);
  });

  test('caps with the named tail', () {
    final graph = _graph();
    final result = graph.recall('a', cap: 2);
    expect(result.totalMatches, 4);
    expect(result.matches, hasLength(2));
    expect(result.truncationNotice, 'Newest 2 of 4 matches');
  });

  test('no matches: empty result without a tail', () {
    final graph = _graph();
    final result = graph.recall('submarine');
    expect(result.totalMatches, 0);
    expect(result.matches, isEmpty);
    expect(result.truncationNotice, isNull);
  });

  test('cap below one is a named argument error', () {
    final graph = _graph();
    expect(() => graph.recall('a', cap: 0), throwsA(isA<ArgumentError>()));
  });

  test('invalid regex patterns surface as FormatException', () {
    final graph = _graph();
    expect(() => graph.recall('['), throwsA(isA<FormatException>()));
  });
}
