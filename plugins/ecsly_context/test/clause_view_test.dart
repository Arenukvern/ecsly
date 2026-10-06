import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

import 'memory_store.dart';

void main() {
  test('a fitting text shows whole and names nothing', () {
    final graph = ContextGraph(MemoryStore());
    graph.append('2026-10-06', 'alpha beta; gamma delta. epsilon zeta.');
    final view = graph.clauseView(1, budgetChars: 1200);
    expect(view.truncated, isFalse);
    expect(view.firstClauseOversize, isFalse);
    expect(view.shown.map((final c) => c.text), <String>[
      'alpha beta',
      'gamma delta',
      'epsilon zeta',
    ]);
    expect(view.elided, isEmpty);
    expect(view.elidedAddresses, isEmpty);
  });

  test('the budget selects whole clauses and names the elided', () {
    final graph = ContextGraph(MemoryStore());
    graph.append('2026-10-06', 'alpha beta; gamma delta. epsilon zeta.');
    // Clause costs are 10, 11, 12 — two fit whole within 22, the third
    // does not, and no clause is ever cut.
    final view = graph.clauseView(1, budgetChars: 22);
    expect(view.shown.map((final c) => c.text), <String>[
      'alpha beta',
      'gamma delta',
    ]);
    expect(view.elided.map((final c) => c.text), <String>['epsilon zeta']);
    expect(view.elidedAddresses, <String>['1.3']);
    expect(view.truncated, isTrue);
    // A shown clause is exactly the source's char span — verbatim, whole.
    final source = graph.read(1)!.text;
    final second = view.shown[1];
    expect(source.substring(second.start, second.end), second.text);
    // The address zoom serves: the elided clause reads back whole.
    final recovered = graph.zoom(const IdRange(1, 1)).items.single
        as ZoomBeat;
    expect(recovered.beat.text, contains('epsilon zeta'));
  });

  test('an oversized first clause stays whole and is named', () {
    final graph = ContextGraph(MemoryStore());
    graph.append(
      '2026-10-06',
      'one very long single clause without any separator that just '
          'keeps going and going and going and going and going',
    );
    final view = graph.clauseView(1, budgetChars: 16);
    expect(view.shown, hasLength(1));
    expect(view.firstClauseOversize, isTrue);
    // Nothing was elided — a one-clause record has no parts to name; the
    // oversize flag is the honesty marker here.
    expect(view.truncated, isFalse);
    expect(view.elidedAddresses, isEmpty);
    // The record itself is untouched — the flag names, never cuts.
    expect(graph.read(1)!.text.length, greaterThan(16));
  });

  test('single-clause texts trivially fit', () {
    final graph = ContextGraph(MemoryStore());
    graph.append('2026-10-06', 'Plain decision line.');
    final view = graph.clauseView(1, budgetChars: 4);
    expect(view.shown, hasLength(1));
    expect(view.firstClauseOversize, isTrue);
    expect(view.elided, isEmpty);
  });

  test('unknown beats and bad budgets are named errors', () {
    final graph = ContextGraph(MemoryStore());
    expect(() => graph.clauseView(9), throwsA(isA<UnknownBeatException>()));
    graph.append('2026-10-06', 'x');
    expect(() => graph.clauseView(1, budgetChars: 0), throwsArgumentError);
  });

  test('the payload carries addresses and counts, never cut text', () {
    final graph = ContextGraph(MemoryStore());
    graph.append('2026-10-06', 'alpha beta; gamma delta. epsilon zeta.');
    final payload = graph.clauseView(1, budgetChars: 22).toJson();
    expect(payload['beatId'], 1);
    expect(payload['totalClauses'], 3);
    expect(payload['truncated'], isTrue);
    final elided = payload['elided']! as List<Object?>;
    expect(
      (elided.single as Map<String, Object?>)['address'],
      '1.3',
    );
    expect(payload.containsKey('firstClauseOversize'), isTrue);
  });
}
