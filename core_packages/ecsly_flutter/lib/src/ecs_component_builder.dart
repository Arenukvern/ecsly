import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_scope.dart';

typedef EcsComponentWidgetBuilder<T extends Component> =
    Widget Function(BuildContext context, T component);

typedef EcsSelectedComponentWidgetBuilder<R> =
    Widget Function(BuildContext context, R value);

/// Rebuilds when component [T] is present on [entity] and the controller
/// notifies.
class EcsComponentBuilder<T extends Component> extends StatelessWidget {
  const EcsComponentBuilder({
    required this.builder,
    super.key,
    this.entity,
    this.where,
    this.world,
    this.controller,
    this.whenAbsent,
  });

  final Entity? entity;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final EcsComponentWhere<T>? where;
  final World? world;
  final EcsController? controller;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final EcsComponentWidgetBuilder<T> builder;
  final Widget? whenAbsent;

  @override
  Widget build(final BuildContext context) => EcsComponentSelector<T, T>(
    entity: entity,
    where: where,
    world: world,
    controller: controller,
    select: (final component) => component,
    builder: builder,
    whenAbsent: whenAbsent,
  );
}

/// Rebuilds only when the selected value from component [T] changes.
class EcsComponentSelector<T extends Component, R> extends StatefulWidget {
  const EcsComponentSelector({
    required this.builder,
    super.key,
    this.entity,
    this.where,
    this.select,
    this.selectWithEntity,
    this.world,
    this.controller,
    this.equals,
    this.whenAbsent,
  }) : assert(
         select != null || selectWithEntity != null,
         'Pass select or selectWithEntity.',
       );

  final Entity? entity;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final EcsComponentWhere<T>? where;
  final World? world;
  final EcsController? controller;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final R Function(T component)? select;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final R Function(Entity entity, T component)? selectWithEntity;
  // ignore: unsafe_variance, callbacks consume R only within this widget.
  final EcsSelectedComponentWidgetBuilder<R> builder;
  // ignore: unsafe_variance, callbacks consume R only within this widget.
  final bool Function(R previous, R next)? equals;
  final Widget? whenAbsent;

  @override
  State<EcsComponentSelector<T, R>> createState() =>
      _EcsComponentSelectorState<T, R>();
}

class _EcsComponentSelectorState<T extends Component, R>
    extends State<EcsComponentSelector<T, R>> {
  EcsController? _controller;
  R? _lastValue;
  Widget? _lastChild;
  bool _hasValue = false;

  @override
  Widget build(final BuildContext context) {
    if (!_hasValue) {
      return widget.whenAbsent ?? const SizedBox.shrink();
    }
    return _lastChild ??= widget.builder(context, _lastValue as R);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller == null && EcsScope.hasAspectModel(context)) {
      EcsScope.dependOnComponent<T>(context, entity: widget.entity);
    }
    _syncController();
    _refresh(notify: false);
  }

  @override
  void didUpdateWidget(covariant final EcsComponentSelector<T, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.world != widget.world ||
        oldWidget.entity != widget.entity ||
        oldWidget.where != widget.where) {
      _syncController();
    }
    _lastChild = null;
    _refresh(notify: false);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  World get _world {
    final world =
        widget.world ?? EcsScope.maybeOf(context, listen: false)?.world;
    if (world == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('EcsComponentSelector could not find an ECS world.'),
        ErrorDescription(
          'Pass world: directly or wrap this widget in EcsScope.',
        ),
      ]);
    }
    return world;
  }

  EcsController? get _nextController =>
      widget.controller ??
      (EcsScope.hasAspectModel(context)
          ? null
          : EcsScope.maybeOf(context, listen: false)?.controller);

  bool _equals(final R previous, final R next) =>
      widget.equals?.call(previous, next) ?? previous == next;

  void _onChanged() {
    if (_controller?.shouldRefreshComponent<T>(entity: widget.entity) ==
        false) {
      return;
    }
    _refresh();
  }

  void _refresh({final bool notify = true}) {
    if (!mounted) return;
    final world = _world;
    final resolvedEntity =
        widget.entity ??
        (widget.where == null
            ? null
            : world.maybeFindEcsEntityWithComponent<T>(where: widget.where!));
    if (resolvedEntity == null) {
      _setAbsent(notify: notify);
      return;
    }

    final component = world.maybeGetEcsComponent<T>(
      entity: resolvedEntity,
      where: widget.where,
    );
    if (component == null) {
      _setAbsent(notify: notify);
      return;
    }

    final selected =
        widget.selectWithEntity?.call(resolvedEntity, component) ??
        widget.select!(component);
    final changed = !_hasValue || !_equals(_lastValue as R, selected);
    if (!changed) return;

    if (notify) {
      setState(() {
        _lastValue = selected;
        _lastChild = null;
        _hasValue = true;
      });
      return;
    }
    _lastValue = selected;
    _lastChild = null;
    _hasValue = true;
  }

  void _setAbsent({required final bool notify}) {
    if (!_hasValue) return;
    if (notify) {
      setState(() {
        _hasValue = false;
        _lastValue = null;
        _lastChild = null;
      });
      return;
    }
    _hasValue = false;
    _lastValue = null;
    _lastChild = null;
  }

  void _syncController() {
    final next = _nextController;
    if (identical(next, _controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = next;
    _controller?.addListener(_onChanged);
  }
}
