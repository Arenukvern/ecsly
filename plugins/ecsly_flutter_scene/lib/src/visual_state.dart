/// The pure visual state of ONE mapped entity — no Flutter, no
/// flutter_scene. The binder diffs these; a [SceneSink] materializes
/// them. Positions are XYZ in the consumer's own layout (the adapter
/// never lays out a graph itself — the first consumer owns that).
library;

/// The closed shape vocabulary the sinks must support.
/// The closed shape vocabulary the sinks must support.
enum SceneShape {
  /// A point mass (sphere).
  sphere,

  /// A box (cuboid).
  cuboid,

  /// A flat disc.
  disc,

  /// An always-visible flat quad (unlit).
  billboard,

  /// A polyline through [VisualState.points].
  polyline,
}

  /// A point mass (sphere).
class VisualState {
  /// A box (cuboid).
  const VisualState({
  /// A flat disc.
    required this.shape,
  /// An always-visible flat quad (unlit).
    required this.argb,
  /// A polyline through [VisualState.points].
    required this.size,
    required this.position,
    this.label,
    this.points = const [],
  });

  /// Creates a visual state.
  final SceneShape shape;

  /// ARGB color (pure int — no Flutter Color in the core layer).
  final int argb;

  /// Uniform extent (sphere radius / cube edge / disc diameter).
  final double size;

  /// XYZ in world units.
  final List<double> position;

  /// Optional text label (rendered as a billboard by the sink).
  final String? label;

  /// Polyline points (shape == polyline only).
  final List<List<double>> points;

  /// A cheap change signature — the binder skips updates whose signature
  /// is unchanged (per-frame sync must be allocation-light).
  String get signature =>
      '$shape|$argb|$size|'
      '${position.map((final v) => v.toStringAsFixed(2)).join(',')}|'
      '$label|${points.length}';
}
