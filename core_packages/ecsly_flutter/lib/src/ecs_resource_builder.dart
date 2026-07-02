import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_scope.dart';

typedef EcsResourceWidgetBuilder<T extends Resource> =
    Widget Function(BuildContext context, T resource);

typedef EcsSelectedResourceWidgetBuilder<R> =
    Widget Function(BuildContext context, R value);

/// Rebuilds when an ECS resource is present and the controller notifies.
class EcsResourceBuilder<T extends Resource> extends StatelessWidget {
  const EcsResourceBuilder({
    required this.builder,
    super.key,
    this.world,
    this.controller,
    this.whenAbsent,
  });

  final World? world;
  final EcsController? controller;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final EcsResourceWidgetBuilder<T> builder;
  final Widget? whenAbsent;

  @override
  Widget build(final BuildContext context) => EcsResourceSelector<T, T>(
    world: world,
    controller: controller,
    select: (final resource) => resource,
    builder: builder,
    whenAbsent: whenAbsent,
  );
}

/// Familiar alias for resource-backed UI.
class EcsConsumer<T extends Resource> extends EcsResourceBuilder<T> {
  const EcsConsumer({
    required super.builder,
    super.key,
    super.world,
    super.controller,
    super.whenAbsent,
  });
}

/// Rebuilds only when the selected value from resource [T] changes.
class EcsResourceSelector<T extends Resource, R> extends StatefulWidget {
  const EcsResourceSelector({
    required this.select,
    required this.builder,
    super.key,
    this.world,
    this.controller,
    this.equals,
    this.whenAbsent,
  });

  final World? world;
  final EcsController? controller;
  // ignore: unsafe_variance, callbacks consume T only within this widget.
  final R Function(T resource) select;
  // ignore: unsafe_variance, callbacks consume R only within this widget.
  final EcsSelectedResourceWidgetBuilder<R> builder;
  // ignore: unsafe_variance, callbacks consume R only within this widget.
  final bool Function(R previous, R next)? equals;
  final Widget? whenAbsent;

  @override
  State<EcsResourceSelector<T, R>> createState() =>
      _EcsResourceSelectorState<T, R>();
}

class _EcsResourceSelectorState<T extends Resource, R>
    extends State<EcsResourceSelector<T, R>> {
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
      EcsScope.dependOnResource<T>(context);
    }
    _syncController();
    _refresh(notify: false);
  }

  @override
  void didUpdateWidget(covariant final EcsResourceSelector<T, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.world != widget.world) {
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
        ErrorSummary('EcsResourceSelector could not find an ECS world.'),
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
    if (_controller?.shouldRefreshResource<T>() == false) return;
    _refresh();
  }

  void _refresh({final bool notify = true}) {
    if (!mounted) return;
    final world = _world;
    final resource = world.maybeGetResource<T>();
    if (resource == null) {
      if (_hasValue && notify) {
        setState(() {
          _hasValue = false;
          _lastValue = null;
          _lastChild = null;
        });
      } else if (!notify) {
        _hasValue = false;
        _lastValue = null;
        _lastChild = null;
      }
      return;
    }

    final selected = widget.select(resource);
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

  void _syncController() {
    final next = _nextController;
    if (identical(next, _controller)) return;
    _controller?.removeListener(_onChanged);
    _controller = next;
    _controller?.addListener(_onChanged);
  }
}
