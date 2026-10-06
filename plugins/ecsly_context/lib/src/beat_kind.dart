/// Kind of a [ContextBeat] in the context graph.
///
/// The kind decides the permanence contract: [raw] beats are permanent and
/// immutable, [summary] and [decomposition] beats are derived, rebuildable
/// and forgettable.
enum BeatKind {
  /// An original, permanent record. Never forgettable, never rewritten.
  raw,

  /// A derived, rebuildable condensation of source beats
  /// ([ContextBeat.summarizes] carries the provenance links).
  summary,

  /// A derived part produced by decomposing an original beat
  /// ([ContextBeat.decomposedFrom] carries the provenance link).
  decomposition,
}
