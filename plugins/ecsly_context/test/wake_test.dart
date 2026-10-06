import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

import 'memory_store.dart';

const _dates = <String>[
  '2026-09-25',
  '2026-09-26',
  '2026-09-27',
  '2026-09-28',
  '2026-09-29',
  '2026-09-30',
  '2026-10-01',
  '2026-10-02',
  '2026-10-03',
  '2026-10-04',
  '2026-10-05',
  '2026-10-06',
];

/// 12 raw beats (ids 1-12) plus two summaries: #13 covers 1-3, #14 covers
/// 4-6. Ranges 7-12 stay uncovered.
ContextGraph _graphWithSummaries() {
  final graph = ContextGraph(MemoryStore());
  for (var i = 1; i <= 12; i++) {
    graph.append(_dates[i - 1], 'beat $i');
  }
  graph.derive([1, 2, 3], 'summary of one to three');
  graph.derive([4, 5, 6], 'summary of four to six');
  return graph;
}

void main() {
  group('budget compliance', () {
    test('lines never exceed the budget for every budget size', () {
      final graph = _graphWithSummaries();
      for (var budget = 1; budget <= 14; budget++) {
        final view = graph.wake(budgetLines: budget);
        expect(
          view.lines,
          hasLength(lessThanOrEqualTo(budget)),
          reason: 'budget $budget',
        );
        expect(view.budgetLines, budget);
        final ids = view.lines.map((final line) => line.beat.id).toSet();
        expect(ids.length, view.lines.length, reason: 'budget $budget');
      }
    });

    test('totalBeats counts live beats', () {
      final view = _graphWithSummaries().wake(budgetLines: 1);
      expect(view.totalBeats, 14);
    });
  });

  group('named absences', () {
    test('absence entries carry id ranges, reasons and covering summaries', () {
      final view = _graphWithSummaries().wake(budgetLines: 1);
      expect(view.lines, hasLength(1));
      expect(view.lines.single.beat.id, 12);
      expect(view.absences, isNotEmpty);
      for (final absence in view.absences) {
        expect(absence.rangeStart, lessThanOrEqualTo(absence.rangeEnd));
        expect(
          absence.reason,
          anyOf(Absence.notSummarized, Absence.summarizedOutOfFrame),
        );
      }
      final covered = view.absences
          .where(
            (final absence) => absence.reason == Absence.summarizedOutOfFrame,
          )
          .toList();
      expect(covered, hasLength(1));
      // Adjacent covered ranges merge by reason class even when different
      // summaries cover them; summaryIds is the union over the range.
      expect(covered.single.rangeStart, 1);
      expect(covered.single.rangeEnd, 6);
      expect(covered.single.summaryIds, <int>[13, 14]);
      final uncovered = view.absences.singleWhere(
        (final absence) => absence.reason == Absence.notSummarized,
      );
      expect(uncovered.rangeStart, 7);
      expect(uncovered.rangeEnd, 11);
      expect(uncovered.summaryIds, isEmpty);
    });

    test('absences disappear once everything fits the frame', () {
      final view = _graphWithSummaries().wake(budgetLines: 20);
      expect(view.absences, isEmpty);
    });
  });

  group('newest-first framing', () {
    test('latest beats render verbatim, newest first, as whole texts', () {
      final graph = _graphWithSummaries();
      final view = graph.wake(budgetLines: 20);
      final verbatim = view.lines
          .where((final line) => line.rangeStart == null)
          .map((final line) => line.beat.id)
          .toList();
      expect(verbatim.first, 12);
      final sorted = List.of(verbatim)
        ..sort((final a, final b) => b.compareTo(a));
      expect(verbatim, sorted);
      final stored = <String>{
        for (final beat in graph.state.beats.values) beat.text,
      };
      for (final line in view.lines) {
        expect(stored, contains(line.text));
      }
    });

    test('covered beats render through summaries, never verbatim', () {
      final view = _graphWithSummaries().wake(budgetLines: 20);
      final verbatim = view.lines
          .where((final line) => line.rangeStart == null)
          .map((final line) => line.beat.id)
          .toSet();
      expect(verbatim.intersection(<int>{1, 2, 3, 4, 5, 6}), isEmpty);
      final summaryLines = view.lines
          .where((final line) => line.rangeStart != null)
          .toList();
      expect(summaryLines, hasLength(2));
      expect(summaryLines[0].rangeStart, 4);
      expect(summaryLines[0].rangeEnd, 6);
      expect(summaryLines[0].text, 'summary of four to six');
      expect(summaryLines[1].rangeStart, 1);
      expect(summaryLines[1].rangeEnd, 3);
    });

    test('decomposed originals stay out of the frame but persist', () {
      final graph = ContextGraph(MemoryStore());
      graph.append('2026-10-01', 'the original long record');
      graph.appendAll([
        DecompositionAdded(
          originalId: 1,
          children: [
            const DecompositionPart(id: 2, text: 'part one'),
            const DecompositionPart(id: 3, text: 'part two'),
          ],
        ),
      ]);
      final view = graph.wake(budgetLines: 10);
      expect(view.lines.map((final line) => line.beat.id), <int>[3, 2]);
      final original = graph.read(1)!;
      expect(original.archived, isTrue);
      expect(original.text, 'the original long record');
    });

    test('archived summaries no longer hide their sources', () {
      final graph = ContextGraph(MemoryStore());
      graph.append('2026-10-01', 'one');
      graph.append('2026-10-02', 'two');
      graph.derive([1, 2], 'early summary');
      graph.appendAll([
        DecompositionAdded(
          originalId: 3,
          children: [const DecompositionPart(id: 4, text: 'part')],
        ),
      ]);
      final view = graph.wake(budgetLines: 10);
      final ids = view.lines.map((final line) => line.beat.id).toSet();
      expect(ids.containsAll(<int>[1, 2, 4]), isTrue);
      expect(view.absences, isEmpty);
    });
  });

  test('zero or negative budgets are a named argument error', () {
    final graph = _graphWithSummaries();
    expect(() => graph.wake(budgetLines: 0), throwsA(isA<ArgumentError>()));
  });
}
