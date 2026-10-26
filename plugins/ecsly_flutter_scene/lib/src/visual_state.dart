// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

/// The pure visual state of ONE mapped entity — no Flutter, no
/// flutter_scene. The binder diffs these; a [SceneSink] materializes
/// them. Positions are XYZ in the consumer's own layout (the adapter
/// never lays out a graph itself — the first consumer owns that).
library;

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

/// The renderable state of one scene visual — the unit the binder diffs
/// and a [SceneSink] materializes. Pure data: no Flutter, no flutter_scene.
class VisualState {
  /// Creates a visual state.
  const VisualState({
    required this.shape,
    required this.argb,
    required this.size,
    required this.position,
    this.label,
    this.pickId,
    this.points = const [],
  });

  /// The geometry the sink materializes.
  final SceneShape shape;

  /// ARGB color (pure int — no Flutter Color in the core layer).
  final int argb;

  /// Uniform extent (sphere radius / cube edge / disc diameter).
  final double size;

  /// XYZ in world units.
  final List<double> position;

  /// Optional text label — DATA for the consumer's 2D overlay, never
  /// geometry (the sinks render no text; the first consumer projects
  /// labels to screen space itself, see scene_camera_math.dart).
  final String? label;

  /// The stable id the view's pick gestures report back (tap/hold on the
  /// visual). Null = not a pick target — steps and links never intercept
  /// an actor's gesture. Pick targets must be [SceneShape.sphere].
  final String? pickId;

  /// Polyline points (shape == polyline only).
  final List<List<double>> points;

  /// A cheap change signature — the binder skips updates whose signature
  /// is unchanged (per-frame sync must be allocation-light). Includes
  /// [pickId]: a pick-target change alone must re-sync, or the view's
  /// gestures report a stale id.
  String get signature =>
      '$shape|$argb|$size|'
      '${position.map((v) => v.toStringAsFixed(2)).join(',')}|'
      '$label|$pickId|${points.length}';
}
