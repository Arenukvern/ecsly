import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_scope.dart';
import 'ecs_selector_dependencies.dart';

typedef EcsWorldSelect<R> = R Function(World world);

typedef EcsSelectedWorldWidgetBuilder<R> =
    Widget Function(BuildContext context, R value);

/// Rebuilds only when a selected value from the ECS [World] changes.
///
/// Use this when UI state is derived from more than one component/resource
/// slice. Prefer resource/component selectors when one slice is enough.
class EcsWorldSelector<R> extends StatefulWidget {
  const EcsWorldSelector({
    required this.select,
    required this.builder,
    super.key,
    this.world,
    this.controller,
    this.dependencies,
    this.equals,
  });

  final World? world;
  final EcsController? controller;
  final EcsWorldSelectorDependencies? dependencies;
  final EcsWorldSelect<R> select;
  // ignore: unsafe_variance, callback consumes R only within this widget.
  final EcsSelectedWorldWidgetBuilder<R> builder;
  // ignore: unsafe_variance, callbacks consume R only within this widget.
  final bool Function(R previous, R next)? equals;

  @override
  State<EcsWorldSelector<R>> createState() => _EcsWorldSelectorState<R>();
}

class _EcsWorldSelectorState<R> extends State<EcsWorldSelector<R>> {
  EcsController? _controller;
  R? _lastValue;
  Widget? _lastChild;
  bool _hasValue = false;

  @override
  Widget build(final BuildContext context) {
    if (!_hasValue) {
      _refresh(notify: false);
    }
    return _lastChild ??= widget.builder(context, _lastValue as R);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller == null && EcsScope.hasAspectModel(context)) {
      EcsScope.dependOnWorld(context, widget.dependencies);
    }
    _syncController();
    _refresh(notify: false);
  }

  @override
  void didUpdateWidget(covariant final EcsWorldSelector<R> oldWidget) {
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
        ErrorSummary('EcsWorldSelector could not find an ECS world.'),
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
    if (_controller?.shouldRefreshWorld(widget.dependencies) == false) return;
    _refresh();
  }

  void _refresh({final bool notify = true}) {
    if (!mounted) return;
    final selected = widget.select(_world);
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
