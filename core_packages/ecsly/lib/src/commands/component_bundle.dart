// ignore_for_file: avoid_returning_this

import '../components/components.dart';

/// Bundle of class based components to be added to an entity atomically.
///
/// Allows efficient spawning of entities with multiple components
/// by reducing command queue overhead and enabling batch processing.
class ComponentBundle {
  ComponentBundle(this.components, this.extensionComponents);

  /// Create a bundle from a list of extension components.
  factory ComponentBundle.fromExtensionList(
    final List<(Type, Type)> extensionComponents,
  ) => ComponentBundle(
    const ComponentsBatchList([]),
    ComponentsBatchListExt(extensionComponents),
  );

  /// Create a bundle from a list of components.
  factory ComponentBundle.fromLists(
    final List<Component> components, [
    final List<(Type, Type)> extensionComponents = const [],
  ]) {
    final items = components.map((final c) => (c.runtimeType, c)).toList();
    return ComponentBundle(
      ComponentsBatchList(items),
      ComponentsBatchListExt(extensionComponents),
    );
  }

  final ComponentsBatchList components;
  final ComponentsBatchListExt extensionComponents;

  /// Add a component to the bundle.
  ComponentBundle add<T extends Component>(final T component) {
    components.items.add((T, component));
    return this;
  }

  ComponentBundle addExtension<T extends Component, TExtension>() {
    extensionComponents.items.add((T, TExtension));
    return this;
  }
}

extension type const ComponentsBatchList(List<(Type, Component)> items) {}
extension type const ComponentsBatchList2<
  T extends Component,
  T2 extends Component
>._(List<(Type, Component)> components)
    implements ComponentsBatchList {
  factory ComponentsBatchList2({
    required final T component1,
    required final T2 component2,
  }) => ComponentsBatchList2<T, T2>._([(T, component1), (T2, component2)]);

  T get component1 => components[0] as T;
  Type get component1Type => T;
  T2 get component2 => components[1] as T2;
  Type get component2Type => T2;
}

extension type const ComponentsBatchList3<
  T extends Component,
  T2 extends Component,
  T3 extends Component
>._(List<(Type, Component)> components)
    implements ComponentsBatchList {
  factory ComponentsBatchList3({
    required final T component1,
    required final T2 component2,
    required final T3 component3,
  }) => ComponentsBatchList3<T, T2, T3>._([
    (T, component1),
    (T2, component2),
    (T3, component3),
  ]);

  T get component1 => components[0] as T;
  Type get component1Type => T;
  T2 get component2 => components[1] as T2;
  Type get component2Type => T2;
  T3 get component3 => components[2] as T3;
  Type get component3Type => T3;
}

extension type const ComponentsBatchListExt(List<(Type, Type)> items) {}
