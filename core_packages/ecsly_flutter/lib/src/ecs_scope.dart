import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_selector_dependencies.dart';

/// Provides an ecsly [World] and optional [EcsController] to Flutter widgets.
class EcsScope extends StatefulWidget {
  const EcsScope({
    required this.world,
    required this.child,
    this.controller,
    super.key,
  });

  final World world;
  final EcsController? controller;
  final Widget child;

  @override
  State<EcsScope> createState() => _EcsScopeState();

  /// Returns the nearest scope, or null when no scope is available.
  static EcsScope? maybeOf(
    final BuildContext context, {
    final bool listen = true,
  }) {
    if (listen) {
      return context
          .dependOnInheritedWidgetOfExactType<_EcsIdentityScope>()
          ?.scope;
    }
    final element = context
        .getElementForInheritedWidgetOfExactType<_EcsIdentityScope>();
    return (element?.widget as _EcsIdentityScope?)?.scope;
  }

  /// Returns the nearest scope.
  static EcsScope of(final BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('No EcsScope found in this BuildContext.'),
        ErrorDescription(
          'Wrap this widget with EcsScope, or pass a World/Controller '
          'directly to the ecsly_flutter widget you are using.',
        ),
      ]);
    }
    return scope;
  }

  /// Returns the nearest world.
  static World worldOf(
    final BuildContext context, {
    final bool listen = true,
  }) => maybeOf(context, listen: listen)?.world ?? of(context).world;

  /// Returns the nearest controller, or null when the scope is read-only.
  static EcsController? controllerOf(
    final BuildContext context, {
    final bool listen = false,
  }) => maybeOf(context, listen: listen)?.controller;

  /// Returns the nearest controller or throws a helpful Flutter error.
  static EcsController requireControllerOf(final BuildContext context) {
    final controller = controllerOf(context);
    if (controller != null) return controller;
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('No EcsController found in this EcsScope.'),
      ErrorDescription(
        'Pass controller: EcsController(world: world) to EcsScope before '
        'calling context.runEcsAction or context.ecs.controller.',
      ),
    ]);
  }

  static bool hasAspectModel(final BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<_EcsAspectModel>() !=
      null;

  static void dependOnResource<T extends Resource>(final BuildContext context) {
    _dependOnAspect(context, _EcsResourceAspect(T));
  }

  static void dependOnComponent<T extends Component>(
    final BuildContext context, {
    final Entity? entity,
  }) {
    _dependOnAspect(context, _EcsComponentAspect(T, entity));
  }

  static void dependOnWorld(
    final BuildContext context,
    final EcsWorldSelectorDependencies? dependencies,
  ) {
    if (dependencies == null || dependencies.isEmpty) {
      _dependOnAspect(context, const _EcsBroadAspect());
      return;
    }
    if (dependencies.structural) {
      _dependOnAspect(context, const _EcsStructuralAspect());
    }
    for (final type in dependencies.resourceTypes) {
      _dependOnAspect(context, _EcsResourceAspect(type));
    }
    for (final type in dependencies.componentTypes) {
      _dependOnAspect(context, _EcsComponentAspect(type, null));
    }
  }

  static void _dependOnAspect(
    final BuildContext context,
    final _EcsAspect aspect,
  ) {
    InheritedModel.inheritFrom<_EcsAspectModel>(context, aspect: aspect);
  }
}

class _EcsScopeState extends State<EcsScope> {
  EcsController? _controller;
  int _revision = 0;
  EcsInvalidationBatch _invalidation = const EcsInvalidationBatch.broad();

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant final EcsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _syncController();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => _EcsIdentityScope(
    scope: widget,
    child: _EcsAspectModel(
      revision: _revision,
      invalidation: _invalidation,
      child: widget.child,
    ),
  );

  void _syncController() {
    final next = widget.controller;
    if (identical(next, _controller)) return;
    _controller?.removeListener(_handleControllerChanged);
    _controller = next;
    _controller?.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    setState(() {
      _revision = controller.notificationRevision;
      _invalidation = controller.lastInvalidation;
    });
  }
}

class _EcsIdentityScope extends InheritedWidget {
  const _EcsIdentityScope({required this.scope, required super.child});

  final EcsScope scope;

  @override
  bool updateShouldNotify(covariant final _EcsIdentityScope oldWidget) =>
      scope.world != oldWidget.scope.world ||
      scope.controller != oldWidget.scope.controller;
}

class _EcsAspectModel extends InheritedModel<_EcsAspect> {
  const _EcsAspectModel({
    required this.revision,
    required this.invalidation,
    required super.child,
  });

  final int revision;
  final EcsInvalidationBatch invalidation;

  @override
  bool updateShouldNotify(covariant final _EcsAspectModel oldWidget) =>
      revision != oldWidget.revision || invalidation != oldWidget.invalidation;

  @override
  bool updateShouldNotifyDependent(
    covariant final _EcsAspectModel oldWidget,
    final Set<_EcsAspect> dependencies,
  ) {
    if (revision == oldWidget.revision &&
        invalidation == oldWidget.invalidation) {
      return false;
    }
    for (final dependency in dependencies) {
      if (dependency.matches(invalidation)) return true;
    }
    return false;
  }
}

@immutable
sealed class _EcsAspect {
  const _EcsAspect();

  bool matches(final EcsInvalidationBatch invalidation);
}

@immutable
final class _EcsBroadAspect extends _EcsAspect {
  const _EcsBroadAspect();

  @override
  bool matches(final EcsInvalidationBatch invalidation) => true;

  @override
  int get hashCode => Object.hash(_EcsBroadAspect, null);

  @override
  bool operator ==(final Object other) => other is _EcsBroadAspect;
}

@immutable
final class _EcsStructuralAspect extends _EcsAspect {
  const _EcsStructuralAspect();

  @override
  bool matches(final EcsInvalidationBatch invalidation) =>
      invalidation.matchesStructural();

  @override
  int get hashCode => Object.hash(_EcsStructuralAspect, null);

  @override
  bool operator ==(final Object other) => other is _EcsStructuralAspect;
}

@immutable
final class _EcsResourceAspect extends _EcsAspect {
  const _EcsResourceAspect(this.type);

  final Type type;

  @override
  bool matches(final EcsInvalidationBatch invalidation) =>
      invalidation.matchesResourceType(type);

  @override
  int get hashCode => Object.hash(_EcsResourceAspect, type);

  @override
  bool operator ==(final Object other) =>
      other is _EcsResourceAspect && other.type == type;
}

@immutable
final class _EcsComponentAspect extends _EcsAspect {
  const _EcsComponentAspect(this.type, this.entity);

  final Type type;
  final Entity? entity;

  @override
  bool matches(final EcsInvalidationBatch invalidation) =>
      invalidation.matchesComponentType(type, entity: entity);

  @override
  int get hashCode => Object.hash(_EcsComponentAspect, type, entity);

  @override
  bool operator ==(final Object other) =>
      other is _EcsComponentAspect &&
      other.type == type &&
      other.entity == entity;
}
