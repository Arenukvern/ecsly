/// End-to-end context-core story: append beats, derive a summary, decompose
/// an original, wake within a budget, zoom, recall.
///
/// Run with: `dart run example/main.dart`
library;

import 'dart:io';

import 'package:ecsly_context/ecsly_context.dart';

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('ecsly_context_demo');
  try {
    final log = await JsonlEventLog.open('${dir.path}/context.jsonl');
    final graph = ContextGraph(log);

    // Raw beats: permanent, immutable, stored verbatim.
    for (final entry in _days.entries) {
      graph.append(entry.key, entry.value);
    }

    // A summary: derived, provenance-linked to its sources.
    final first = graph.derive(
      [1, 2, 3],
      'Launch week: budget framing decided, absence naming agreed, '
      'JSONL log made crash-safe.',
    );

    // A decomposition: children + archived original (still readable).
    final decision = graph.read(4)!;
    final parts = graph.decompose(decision.id, [
      'Recall caps at twenty with a named tail.',
      'Wake frames newest-first and names every absence.',
    ]);

    stdout.writeln('total beats: ${graph.wake().totalBeats}');
    stdout.writeln('coverage: ${graph.coverage.join(', ')}');

    final view = graph.wake(budgetLines: 4);
    stdout.writeln('--- wake (budget ${view.budgetLines}) ---');
    for (final line in view.lines) {
      final label = line.rangeStart == null
          ? '#${line.beat.id}'
          : '#${line.rangeStart}-${line.rangeEnd}';
      stdout.writeln('$label ${line.text}');
    }
    for (final absence in view.absences) {
      final via = absence.summaryIds.isEmpty
          ? ''
          : ' via ${absence.summaryIds.join(',')}';
      stdout.writeln(
        '[absent #${absence.rangeStart}-${absence.rangeEnd} '
        '${absence.reason}$via]',
      );
    }

    stdout.writeln('--- zoom #2-5 ---');
    final zoom = graph.zoom(const IdRange(2, 5));
    for (final item in zoom.items) {
      switch (item) {
        case ZoomSummary():
          stdout.writeln('summary ${item.summary.id}: ${item.summary.text}');
        case ZoomBeat():
          stdout.writeln('beat ${item.beat.id}: ${item.beat.text}');
        case ZoomRange():
          stdout.writeln('uncovered ${item.range}');
      }
    }

    stdout.writeln('--- recall "absence" ---');
    final recall = graph.recall('absence', cap: 2);
    for (final match in recall.matches) {
      stdout.writeln('#${match.beat.id} (score ${match.score})');
    }
    final notice = recall.truncationNotice;
    if (notice != null) {
      stdout.writeln(notice);
    }

    stdout.writeln('--- forget derived beat ${first.id} ---');
    graph.forget(first.id);
    stdout.writeln(
      'forgotten: ${graph.read(first.id) == null}, '
      'raw #1 intact: ${graph.read(1)!.text}',
    );

    // Decomposition children are derived too; the raw original is not.
    graph.forget(parts.first.id);
    try {
      graph.forget(decision.id);
      // ignore: avoid_catching_errors
    } on RawBeatForgetException catch (error) {
      stdout.writeln('refused: ${error.message}');
    }

    log.close();
  } finally {
    dir.deleteSync(recursive: true);
  }
}

const Map<String, String> _days = <String, String>{
  '2026-10-01':
      'Day 1: decided the memory CLI wakes within a line budget, never '
      'truncating text.',
  '2026-10-02':
      'Day 2: absences must carry id ranges, a reason, and covering summary '
      'ids where present.',
  '2026-10-03':
      'Day 3: the event log fsyncs every append and repairs an '
      'unacknowledged tail on load.',
  '2026-10-04':
      'Day 4: recall ranks by the keyword index rebuilt on fold, capped '
      'with a named tail.',
  '2026-10-05':
      'Day 5: zoom splits a range into two halves; singles resolve to raw '
      'beats.',
  '2026-10-06':
      'Day 6: legacy logs import with ids preserved and dates validated.',
};
