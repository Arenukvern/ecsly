import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

import 'memory_store.dart';

ContextGraph _graphWithSixBeats() {
  final graph = ContextGraph(MemoryStore());
  for (var i = 1; i <= 6; i++) {
    graph.append('2026-10-0$i', 'beat $i');
  }
  return graph;
}

void main() {
  group('append', () {
    test('assigns monotonic ids and stores text verbatim', () {
      final graph = ContextGraph(MemoryStore());
      final first = graph.append('2026-10-01', 'first line');
      final second = graph.append('2026-10-02', 'second line', threadId: 'ops');
      expect(first.id, 1);
      expect(second.id, 2);
      expect(first.kind, BeatKind.raw);
      expect(first.threadId, 'main');
      expect(second.threadId, 'ops');
      expect(first.archived, isFalse);
      expect(graph.read(1)!.text, 'first line');
      expect(graph.read(2)!.text, 'second line');
    });

    test('validates ISO calendar dates', () {
      final graph = ContextGraph(MemoryStore());
      expect(
        () => graph.append('2026-13-01', 'x'),
        throwsA(isA<InvalidDateException>()),
      );
      expect(
        () => graph.append('2026-02-30', 'x'),
        throwsA(isA<InvalidDateException>()),
      );
      expect(
        () => graph.append('20261001', 'x'),
        throwsA(isA<InvalidDateException>()),
      );
    });
  });

  group('derive', () {
    test('links provenance and leaves sources untouched', () {
      final graph = _graphWithSixBeats();
      final summary = graph.derive([1, 2, 3], 'summary of one to three');
      expect(summary.id, 7);
      expect(summary.kind, BeatKind.summary);
      expect(summary.summarizes, <int>[1, 2, 3]);
      expect(summary.date, '2026-10-03');
      expect(summary.threadId, 'main');
      for (final id in [1, 2, 3]) {
        final source = graph.read(id)!;
        expect(source.archived, isFalse);
        expect(source.text, 'beat $id');
      }
    });

    test('inherits date and thread from the newest source', () {
      final graph = ContextGraph(MemoryStore());
      graph.append('2026-10-01', 'a');
      graph.append('2026-10-02', 'b', threadId: 'ops');
      final summary = graph.derive([1, 2], 'both');
      expect(summary.date, '2026-10-02');
      expect(summary.threadId, 'ops');
    });

    test('refuses unknown source ids with a named error', () {
      final graph = _graphWithSixBeats();
      expect(
        () => graph.derive([1, 99], 'x'),
        throwsA(
          isA<UnknownBeatException>().having(
            (final error) => error.beatIds,
            'beatIds',
            <int>[99],
          ),
        ),
      );
    });

    test('provenance survives store reload', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-01', 'a');
      graph.append('2026-10-02', 'b');
      graph.derive([1, 2], 'both');
      final reloaded = ContextGraph(store);
      expect(reloaded.read(3)!.summarizes, <int>[1, 2]);
      expect(reloaded.coverage, <IdRange>[const IdRange(1, 2)]);
    });
  });

  group('decompose', () {
    test('creates linked children and archives the original', () {
      final graph = ContextGraph(MemoryStore());
      final original = graph.append('2026-10-04', 'a long decision record');
      final children = graph.decompose(original.id, <String>[
        'part one',
        'part two',
      ]);
      expect(children, hasLength(2));
      expect(children[0].id, 2);
      expect(children[1].id, 3);
      for (final child in children) {
        expect(child.kind, BeatKind.decomposition);
        expect(child.decomposedFrom, original.id);
        expect(child.date, original.date);
        expect(child.threadId, original.threadId);
      }
      final reloaded = graph.read(original.id)!;
      expect(reloaded.archived, isTrue);
      expect(reloaded.text, 'a long decision record');
      expect(reloaded.kind, BeatKind.raw);
    });

    test('refuses unknown originals and empty parts', () {
      final graph = ContextGraph(MemoryStore());
      expect(
        () => graph.decompose(42, <String>['x']),
        throwsA(isA<UnknownBeatException>()),
      );
      graph.append('2026-10-01', 'x');
      expect(
        () => graph.decompose(1, <String>[]),
        throwsA(isA<ContextEventException>()),
      );
    });
  });

  group('forget', () {
    test('refuses raw beats with a named error', () {
      final graph = ContextGraph(MemoryStore());
      graph.append('2026-10-01', 'raw');
      expect(
        () => graph.forget(1),
        throwsA(
          isA<RawBeatForgetException>().having(
            (final error) => error.beatId,
            'beatId',
            1,
          ),
        ),
      );
      expect(graph.read(1), isNotNull);
    });

    test('refuses unknown beats', () {
      final graph = ContextGraph(MemoryStore());
      expect(
        () => graph.forget(9),
        throwsA(isA<UnknownBeatException>()),
      );
    });

    test('removes only the derived beat; no cascade; ids not reused', () {
      final graph = ContextGraph(MemoryStore());
      graph.append('2026-10-01', 'raw text');
      graph.derive([1], 'summary');
      graph.decompose(1, <String>['p1', 'p2']);
      graph.forget(2);
      expect(graph.read(2), isNull);
      expect(graph.read(1)!.text, 'raw text');
      expect(graph.read(3), isNotNull);
      graph.forget(3);
      expect(graph.read(3), isNull);
      expect(graph.read(4), isNotNull);
      expect(graph.read(1), isNotNull);
      final after = graph.append('2026-10-05', 'after forgetting');
      expect(after.id, 5);
    });
  });

  group('coverage', () {
    test('merges contiguous summary ranges', () {
      final graph = _graphWithSixBeats();
      graph.derive([1, 2, 3], 'first half');
      graph.derive([4, 5, 6], 'second half');
      graph.derive([2, 3, 4], 'middle');
      expect(graph.coverage, <IdRange>[const IdRange(1, 6)]);
    });

    test('archived summaries stop covering', () {
      final graph = _graphWithSixBeats();
      graph.derive([1, 2], 'early');
      graph.decompose(7, <String>['part']);
      expect(graph.coverage, isEmpty);
    });
  });

  group('replay determinism', () {
    test('folding twice yields identical state', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-01', 'one');
      graph.append('2026-10-02', 'two');
      graph.derive([1, 2], 'both');
      graph.decompose(1, <String>['part a', 'part b']);
      graph.forget(5);
      final events = store.load();
      expect(ContextState.foldAll(events), ContextState.foldAll(events));
      var folded = ContextState.empty();
      for (final event in events) {
        folded = folded.fold(event);
      }
      expect(folded, ContextState.foldAll(events));
      final reloaded = ContextGraph(store);
      expect(reloaded.state, ContextState.foldAll(events));
    });
  });

  group('zoom', () {
    test('singles resolve to raw beats', () {
      final graph = _graphWithSixBeats();
      final zoom = graph.zoom(const IdRange(3, 3));
      final item = zoom.items.single;
      expect(item, isA<ZoomBeat>());
      expect((item as ZoomBeat).beat.text, 'beat 3');
    });

    test('halves resolve to summaries when covered', () {
      final graph = _graphWithSixBeats();
      graph.derive([1, 2, 3], 'first half');
      final zoom = graph.zoom(const IdRange(1, 6));
      expect(zoom.items, hasLength(2));
      final first = zoom.items[0];
      expect(first, isA<ZoomSummary>());
      expect((first as ZoomSummary).range, const IdRange(1, 3));
      expect(zoom.items[1], isA<ZoomRange>());
      expect((zoom.items[1] as ZoomRange).range, const IdRange(4, 6));
    });

    test('single unknown id is a named error', () {
      final graph = ContextGraph(MemoryStore());
      expect(
        () => graph.zoom(const IdRange(5, 5)),
        throwsA(isA<UnknownBeatException>()),
      );
    });
  });

  test('view-archive: beats leave the frame, persist verbatim, stay readable', () {
    final log = MemoryStore();
    final graph = ContextGraph(log);
    final a = graph.append('2026-10-06', 'archived candidate one');
    final b = graph.append('2026-10-06', 'still in frame');
    graph.archive([a.id]);

    final view = graph.wake(budgetLines: 12);
    final texts = [for (final line in view.lines) line.text];
    expect(texts, contains('still in frame'));
    expect(texts, isNot(contains('archived candidate one')));

    // Lifecycle selection, never destruction: the record persists verbatim.
    expect(graph.read(a.id)!.text, 'archived candidate one');
    expect(graph.read(a.id)!.archived, isTrue);
    expect(graph.read(b.id)!.archived, isFalse);
  });

  test('view-archive is idempotent and names unknown ids', () {
    final graph = ContextGraph(MemoryStore());
    final beat = graph.append('2026-10-06', 'archive me twice');
    graph.archive([beat.id]);
    expect(() => graph.archive([beat.id]), returnsNormally);
    expect(graph.read(beat.id)!.archived, isTrue);
    expect(() => graph.archive([9999]),
        throwsA(isA<ContextEventException>()));
  });

  test('archiving a summary drops its coverage; sources re-surface', () {
    final graph = ContextGraph(MemoryStore());
    final one = graph.append('2026-10-06', 'covered source one');
    final two = graph.append('2026-10-06', 'covered source two');
    final fresh = graph.append('2026-10-06', 'brand new beat');
    final summary = graph.derive([one.id, two.id], 'both covered sources');
    final covered = graph.wake();
    expect(
      covered.lines.any(
        (final line) => line.rangeStart != null && line.rangeStart == one.id,
      ),
      isTrue,
    );
    graph.archive([summary.id]);
    final after = graph.wake();
    final texts = [for (final line in after.lines) line.text];
    expect(texts, contains('covered source one'));
    expect(texts, contains('covered source two'));
    expect(texts, contains('brand new beat'));
    expect(texts, isNot(contains('both covered sources')));
    expect(fresh.archived, isFalse);
  });
}
