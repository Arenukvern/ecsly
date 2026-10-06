import 'context_beat.dart';
import 'id_range.dart';

/// One half (or single) result of zooming into an id range.
sealed class ZoomItem {
  /// Subclasses only.
  const ZoomItem();
}

/// A summary covering a zoomed sub-range: descend through provenance.
final class ZoomSummary extends ZoomItem {
  /// Creates the item for [summary] covering [range].
  const ZoomSummary(this.summary, this.range);

  /// The covering summary beat.
  final ContextBeat summary;

  /// The sub-range the summary covers.
  final IdRange range;
}

/// A single id resolved to its beat: the zoom reached raw content.
final class ZoomBeat extends ZoomItem {
  /// Creates the item for the resolved [beat].
  const ZoomBeat(this.beat);

  /// The beat at the zoomed id.
  final ContextBeat beat;
}

/// No summary covers this sub-range; zoom deeper or derive a summary.
final class ZoomRange extends ZoomItem {
  /// Creates the item for the uncovered [range].
  const ZoomRange(this.range);

  /// The uncovered sub-range.
  final IdRange range;
}

/// Result of [ContextGraph.zoom]: the requested range and its two halves
/// (summaries for sub-ranges, raw for singles).
final class ZoomResult {
  /// Creates a zoom result.
  const ZoomResult({required this.range, required this.items});

  /// The zoomed range.
  final IdRange range;

  /// The two halves in order (a single item for single-id ranges).
  final List<ZoomItem> items;
}
