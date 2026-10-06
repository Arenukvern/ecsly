/// Micro-benchmarks for the ecsly_context core.
///
/// Run from the plugin directory: `dart run bench/benchmark.dart`
/// Measures: append throughput (fsync per event), batched-write throughput,
/// JSON parse and fold scaling (foldAll must stay linear — the per-event
/// index rebuild made it quadratic; this bench guards that), wake
/// projection, recall, zoom, and resident set size after a large fold.
// ignore_for_file: avoid_print, prefer_final_parameters, avoid_redundant_argument_values, prefer_const_declarations
library;

import 'dart:convert';
import 'dart:io';

import 'package:ecsly_context/ecsly_context.dart';

final class _MemStore implements ContextStore {
  _MemStore(this.events);
  final List<ContextEvent> events;
  @override
  List<ContextEvent> load() => events;
  @override
  void append(ContextEvent event) => events.add(event);
  @override
  void appendAll(final List<ContextEvent> events) => this.events.addAll(events);
  @override
  void close() {}
}

String _humanMs(Duration d) => d.inMicroseconds >= 1000
    ? '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms'
    : '${d.inMicroseconds} µs';

List<ContextEvent> _parseFile(String path) {
  final lines = File(path).readAsLinesSync();
  final events = <ContextEvent>[];
  for (final line in lines) {
    if (line.isEmpty) continue;
    events.add(ContextEvent.fromJson(jsonDecode(line) as Map<String, Object?>));
  }
  return events;
}

/// Synthetic store: [raws] raw beats plus block summaries over each
/// [block] consecutive raws (the shape the real memory store has).
List<ContextEvent> _synthetic(int raws, int block) {
  final events = <ContextEvent>[];
  for (var i = 1; i <= raws; i++) {
    events.add(
      BeatAppended(
        id: i,
        date: '2026-10-06',
        text: 'synthetic beat $i discussing widgets, flumox, and bean '
            'counting with identifier X$i',
      ),
    );
  }
  var next = raws;
  for (var start = 1; start <= raws; start += block) {
    final end = (start + block - 1) > raws ? raws : (start + block - 1);
    next += 1;
    events.add(
      SummaryAdded(
        id: next,
        date: '2026-10-06',
        text: 'summary of beats $start-$end about widgets and beans',
        threadId: 'memory',
        summarizes: [for (var id = start; id <= end; id++) id],
      ),
    );
  }
  return events;
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('ecsly_context_bench');
  const nAppend = 1000;
  final text =
      'benchmark memory line with several indexable words: widget flumox bean';

  // ---- 1. append throughput (durability: fsync per event) ---------------
  final log = await JsonlEventLog.open('${dir.path}/append.jsonl');
  final graph = ContextGraph(log);
  final sw = Stopwatch()..start();
  for (var i = 0; i < nAppend; i++) {
    graph.append('2026-10-06', '$text $i');
  }
  sw.stop();
  log.close();
  final appendMsPer = sw.elapsedMicroseconds / nAppend / 1000;
  print('append (fsync/event): $nAppend events in '
      '${_humanMs(sw.elapsed)} → ${appendMsPer.toStringAsFixed(3)} ms/event, '
      '${(1000 / appendMsPer).round()} events/s');

  // ---- 2. batched write (one pass, no per-event fsync) ------------------
  final batchFile = File('${dir.path}/batch.jsonl');
  sw..reset()..start();
  final sink = batchFile.openSync(mode: FileMode.write);
  for (var i = 1; i <= nAppend; i++) {
    sink.writeStringSync(
      '${jsonEncode(BeatAppended(id: i, date: '2026-10-06', text: '$text $i').toJson())}\n',
    );
  }
  sink.flushSync();
  sink.closeSync();
  print('batched write (no fsync/event): $nAppend lines in '
      '${_humanMs(sw.elapsed)}');

  // ---- 3. real store: parse + fold + index ------------------------------
  const realStorePath =
      '/Users/antonio/.optmem/memory/store/events.jsonl';
  List<ContextEvent>? realEvents;
  if (File(realStorePath).existsSync()) {
    sw..reset()..start();
    realEvents = _parseFile(realStorePath);
    final parseUs = sw.elapsedMicroseconds;
    sw.reset();
    final realState = ContextState.foldAll(realEvents);
    sw.stop();
    print('real store (${realEvents.length} events): parse '
        '${_humanMs(Duration(microseconds: parseUs))}, fold+index '
        '${_humanMs(sw.elapsed)}, beats=${realState.beats.length}');
    final realGraph = ContextGraph(_MemStore(realEvents));
    sw..reset()..start();
    final view = realGraph.wake(budgetLines: 96);
    sw.stop();
    print('wake(96) on real store: ${_humanMs(sw.elapsed)} → '
        '${view.lines.length} lines, ${view.absences.length} absences');
    sw..reset()..start();
    final recall = realGraph.recall('harness');
    sw.stop();
    print('recall("harness") on real store: ${_humanMs(sw.elapsed)} → '
        '${recall.totalMatches} matches');
    sw..reset()..start();
    realGraph.zoom(const IdRange(1, 512));
    sw.stop();
    print('zoom(1-512) on real store: ${_humanMs(sw.elapsed)}');
  } else {
    print('real store not found at $realStorePath — skipping');
  }

  // ---- 4. fold scaling (the per-event index rebuild is O(n) per fold) ---
  for (final size in const [1000, 2000, 4000]) {
    final events = _synthetic(size, 4);
    sw..reset()..start();
    ContextState.foldAll(events);
    sw.stop();
    print('fold ${events.length} events '
        '($size raws): ${_humanMs(sw.elapsed)}');
  }

  // ---- 5. wake + recall on a larger synthetic store ---------------------
  final bigEvents = _synthetic(4000, 4);
  final bigGraph = ContextGraph(_MemStore(bigEvents));
  sw..reset()..start();
  final bigView = bigGraph.wake(budgetLines: 96);
  sw.stop();
  print('wake(96) on 4000 raws + ${bigEvents.length - 4000} summaries: '
      '${_humanMs(sw.elapsed)} → ${bigView.lines.length} lines');
  sw..reset()..start();
  bigGraph.recall('widget');
  sw.stop();
  print('recall("widget") on 4000 raws: ${_humanMs(sw.elapsed)}');
  sw..reset()..start();
  bigGraph.zoom(const IdRange(1, 2048));
  sw.stop();
  print('zoom(1-2048) on 4000 raws: ${_humanMs(sw.elapsed)}');

  // ---- 5b. mechanical segmentation + clause search -----------------------
  // Segment throughput, index build, and clause-grain queries — the
  // on-the-fly search path (no persisted index; rebuilt per invocation).
  List<ClauseDoc> docsOf(final List<ContextEvent> events) => <ClauseDoc>[
        for (final event in events)
          if (event is BeatAppended)
            ClauseDoc(id: event.id, date: event.date, beatKind: 'raw', text: event.text)
          else if (event is SummaryAdded)
            ClauseDoc(id: event.id, date: event.date, beatKind: 'summary', text: event.text),
      ];

  if (realEvents != null) {
    sw..reset()..start();
    final realDocs = docsOf(realEvents);
    var clauseTotal = 0;
    for (final doc in realDocs) {
      clauseTotal += segmentText(doc.text).clauses.length;
    }
    sw.stop();
    print('segment ${realDocs.length} real docs: ${_humanMs(sw.elapsed)} → '
        '$clauseTotal clauses');

    sw..reset()..start();
    final realIndex = ClauseIndex.build(realDocs);
    sw.stop();
    print('clause index on real store: ${_humanMs(sw.elapsed)} → '
        '${realIndex.docCount} docs, ${realIndex.clauseCount} clauses');

    sw..reset()..start();
    final tokenHits = realIndex.search(const ClauseQuery('harness blocker'));
    sw.stop();
    print('clause search "harness blocker" (and): ${_humanMs(sw.elapsed)} → '
        '${tokenHits.totalHits} matches');
    sw..reset()..start();
    final anyHits = realIndex.search(
      const ClauseQuery('harness blocker', requireAll: false),
    );
    sw.stop();
    print('clause search "harness blocker" (any): ${_humanMs(sw.elapsed)} → '
        '${anyHits.totalHits} matches');
    sw..reset()..start();
    final regexHits = realIndex.search(
      const ClauseQuery('focusId', regex: true),
    );
    sw.stop();
    print('clause search regex "focusId": ${_humanMs(sw.elapsed)} → '
        '${regexHits.totalHits} matches');
    sw..reset()..start();
    final kindHits = realIndex.search(
      const ClauseQuery('harness', clauseKinds: {ClauseKind.open}),
    );
    sw.stop();
    print('clause search kind=open "harness": ${_humanMs(sw.elapsed)} → '
        '${kindHits.totalHits} matches');
  }

  // ---- 5c. segment+index scaling (must stay linear in doc count) --------
  for (final size in const [1000, 2000, 4000]) {
    final docs = docsOf(_synthetic(size, 4));
    sw..reset()..start();
    final index = ClauseIndex.build(docs);
    sw.stop();
    final buildMs = sw.elapsedMicroseconds / 1000;
    sw..reset()..start();
    index.search(const ClauseQuery('widget flumox', requireAll: false));
    sw.stop();
    print('segment+index $size docs: ${_humanMs(Duration(microseconds: (buildMs * 1000).round()))}, '
        'search any: ${_humanMs(sw.elapsed)}, '
        'clauses=${index.clauseCount}');
  }

  // ---- 6. resident set after the largest fold ---------------------------
  print('max RSS so far: ${(ProcessInfo.maxRss / 1024 / 1024).toStringAsFixed(1)} MB');
  dir.deleteSync(recursive: true);
}
