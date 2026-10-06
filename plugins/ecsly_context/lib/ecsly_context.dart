/// Pure-Dart context core for memory tools: an append-only beat graph with
/// provenance-carrying summaries and decompositions, budgeted wake
/// projections with named absences, zoom and recall, a crash-safe JSONL
/// event log, and product-agnostic mechanical clause segmentation with
/// clause-grain search over plain records.
///
/// Design law, enforced by the API itself:
/// - text is never rewritten, truncated, substringed or merged — there is
///   no substring-to-fit primitive anywhere; rendered lines are whole
///   stored texts;
/// - budgets resolve by selection with named absences: every out-of-frame
///   range is named with its id range, a reason, and covering summary ids
///   where present;
/// - raw records are permanent and immutable; derived beats (summaries,
///   decompositions) are rebuildable and forgettable, and forgetting a
///   derived beat never touches raw ones;
/// - every derived beat carries typed provenance links to its sources.
library;

export 'src/beat_kind.dart';
export 'src/clause_search.dart';
export 'src/clause_view.dart';
export 'src/condense.dart';
export 'src/context_beat.dart';
export 'src/context_event.dart';
export 'src/context_exception.dart';
export 'src/context_graph.dart';
export 'src/context_state.dart';
export 'src/context_store.dart';
export 'src/families.dart';
export 'src/id_range.dart';
export 'src/iso_date.dart';
export 'src/jsonl_event_log.dart';
export 'src/recall.dart';
export 'src/sections.dart';
export 'src/segment.dart';
export 'src/wake_view.dart';
export 'src/zoom.dart';
