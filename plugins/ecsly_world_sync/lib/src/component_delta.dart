import 'package:meta/meta.dart';

/// One keyed piece of world state that changed (ecsly world sync).
///
/// A [ComponentDelta] names state by stable identity — never by runtime
/// `Entity` handles, which are world-local and disposable (the same identity
/// model as `ecsly_serialization`'s `PersistentId`).
///
/// Each delta becomes exactly one kernel op: one op per keyed piece of
/// state, folded under the kernel's LWW map strategy.
@immutable
final class ComponentDelta {
  /// Creates a component delta for [entityKey]/[component]/[field].
  const ComponentDelta({
    required this.entityKey,
    required this.component,
    required this.field,
    required this.value,
  });

  /// Stable cross-session identity of the owning entity (for example the
  /// string form of a `PersistentId`). Never a runtime entity handle.
  final String entityKey;

  /// Component type name.
  final String component;

  /// Field (column or object-member key) within the component.
  final String field;

  /// JSON-encodable new value. `null` is a legal value and is distinct from
  /// a removal ([WorldSync.removeDelta]).
  final Object? value;

  /// Sync key this delta folds under: `<entityKey>/<component>/<field>`.
  String get syncKey => '$entityKey/$component/$field';

  /// JSON round-trip form.
  Map<String, Object?> toJson() => {
    'entity_key': entityKey,
    'component': component,
    'field': field,
    'value': value,
  };

  @override
  String toString() => 'ComponentDelta($syncKey = $value)';
}
