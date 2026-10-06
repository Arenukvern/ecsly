# ecsly_context

Beat-graph context core for agent worlds: an append-only store of immutable
"beats" with provenance-carrying summaries and decompositions, budgeted wake
projections that name what is missing, zoom, recall, and a crash-safe JSONL
event log. Adopted as the shared context contract by ADR 0067 in the
ecsai_harness repository; its first consumer is the `xsoulspace_optmem`
memory CLI.

Pure Dart, SDK-only runtime dependencies — consumable as a path dependency
from any repository, and compilable to a static binary.

## Design law

The API makes violations inexpressible:

- **Text is never rewritten.** No substring-to-fit primitive exists anywhere
  in this package. Rendered lines are whole stored texts, selected as-is.
- **Budgets resolve by selection with named absences.** Every out-of-frame
  range is named with its id range, a reason, and covering summary ids where
  present.
- **Raw records are permanent.** Derived beats (summaries, decompositions)
  are rebuildable and forgettable; forgetting a derived beat never touches
  raw ones. Decompose archives its original (a view filter only — the
  original persists verbatim).
- **Every derived beat carries typed provenance**:
  `ContextBeat.summarizes` for summaries, `ContextBeat.decomposedFrom` for
  decompositions.

## Model

- `ContextBeat` — `{id, date, text, threadId, kind, summarizes,
  decomposedFrom, archived}`. Ids are monotonic and never reused.
- `ContextStore` — append-only event log as the single source of truth;
  state is the fold of events, all indexes are rebuilt on load and never
  persisted as truth.
- `JsonlEventLog` — one JSON event per line: flush-on-append, batched
  `appendAll` under one flush for imports, and corrupt-tail repair (a final
  partial line was never acknowledged and is truncated on load).

## Concurrency

- **Reads are lock-free**: `JsonlEventLog.openReadOnly` takes no lock and
  never truncates — any number of processes may read against a writer; a
  torn final line is skipped as unacknowledged.
- **Appends are single-writer, bounded-fair**: the exclusive lockfile
  retries with full jitter inside a bounded window and is stolen when its
  holder pid is provably dead, so a killed process cannot wedge the store.
- **Bulk imports** go through `ContextGraph.appendAll` — one flush per
  batch; per-event flushing is fsync-bound.
- **Loading is linear**: `foldAll` applies all events and builds the
  keyword index exactly once (`bench/benchmark.dart` guards the curve —
  the per-event rebuild was quadratic).
- **Projection internals are columnar**: coverage and the rendered frame
  are bit sets over the contiguous id space (`IdBitSet`); a summary's
  freshness test is a word-AND.

Events: `BeatAppended`, `SummaryAdded`, `DecompositionAdded` (children plus
original archived), `BeatForgotten` (derived only).

## Install

```yaml
dependencies:
  ecsly_context:
```

## Usage

A complete runnable story lives in [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

```dart
final log = await JsonlEventLog.open('memory/context.jsonl');
final graph = ContextGraph(log);

final beat = graph.append('2026-10-06', 'Decided the CLI wakes on a budget.');
final summary = graph.derive([beat.id], 'Wake budget decision, day 1.');
final children = graph.decompose(someOriginal.id, ['part one', 'part two']);

// Everything that did not fit the frame is named, with ids:
final view = graph.wake(budgetLines: 8);
for (final line in view.lines) {
  final label = line.rangeStart == null
      ? '#${line.beat.id}'
      : '#${line.rangeStart}-${line.rangeEnd}';
  stdout.writeln('$label ${line.text}');
}
for (final absence in view.absences) {
  stdout.writeln(
    '[absent #${absence.rangeStart}-${absence.rangeEnd} '
    '${absence.reason}${absence.summaryIds.isEmpty ? '' : ' via ${absence.summaryIds}'}]',
  );
}

graph.forget(summary.id); // derived only; raw beats refuse with RawBeatForgetException
```

### Wake framing

`wake({budgetLines})` frames newest-first: the latest raw (or decomposition)
beats verbatim; older ranges rendered through the most coverage-providing
summaries (each rendered as a range-named line `#40-79 <text>`, keeping its
sources readable via `zoom` and `recall`); everything else becomes
`Absence{rangeStart, rangeEnd, reason, summaryIds}` — a contiguous run of
ids sharing the same covering summaries, so every range carries exactly one
honest reason. Reasons are the named constants `Absence.notSummarized`
(`'not summarized, out of frame'`) and `Absence.summarizedOutOfFrame`
(`'summarized, out of frame'`). Lines never exceed the budget.

### Zoom and recall

- `zoom(range)` splits an id range into its two halves — summaries for
  sub-ranges (`ZoomSummary`), raw beats for singles (`ZoomBeat`), and
  `ZoomRange` where nothing covers a half yet.
- `recall(regex)` ranks matches by keyword score (a tokenized keyword index
  is rebuilt on every fold), newest-first within a rank, and caps with a
  named tail: `'Newest N of M matches'`.

### Legacy import

`parseLegacyLog` parses `#<id> <yyyy-mm-dd> <text>` lines (whitespace
tolerant, ids preserved, dates validated, strictly increasing ids) into
append events. `parseLegacyTree(directory)` reads `log.txt` plus
`summary-<size>.txt` level files, where the k-th record of a level summarizes
the existing raw ids of block `[k*size + 1, (k+1)*size]` (the 1-based
adaptation of `[k*size, (k+1)*size)`), to migrate an existing store.

## Constraints

- Pure Dart; runtime dependencies are the SDK only. `ecsly` is not a
  dependency — this core is ECS-agnostic.
- Only one process may write a log at a time (lockfile); readers in other
  processes should open their own read-only copies.
- A corrupt final log line is treated as unacknowledged and truncated;
  corruption anywhere else is a named `ContextLogCorruptException`.
- `wake` requires `budgetLines >= 1`; there is deliberately no way to ask
  for partial texts.
