import 'package:ecsly_app/ecsly_app.dart';
import 'package:flutter/widgets.dart';

import 'ecs_controller.dart';
import 'ecs_resource_builder.dart';
import 'ecs_scope.dart';

typedef EcsActionRunCallback<T> = Future<T> Function();

typedef EcsActionStatusWidgetBuilder =
    Widget Function(BuildContext context, EcsActionStatus status);

typedef EcsActionWidgetBuilder<T> =
    Widget Function(
      BuildContext context,
      EcsActionStatus status,
      EcsActionRunCallback<T>? run,
    );

/// Builds UI from an [EcsAction] status and exposes a safe run callback.
///
/// This is intentionally widget-toolkit neutral. Material/Cupertino apps can
/// wrap [run] in their own button while sharing duplicate-submit prevention and
/// ECS-backed status state.
class EcsActionBuilder<T> extends StatelessWidget {
  const EcsActionBuilder({
    required this.action,
    required this.builder,
    super.key,
    this.world,
    this.controller,
    this.disableWhileRunning = true,
  });

  final EcsAction<T> action;
  final World? world;
  final EcsController? controller;
  final bool disableWhileRunning;
  // ignore: unsafe_variance, callback consumes T only through run result.
  final EcsActionWidgetBuilder<T> builder;

  @override
  Widget build(final BuildContext context) {
    final resolvedWorld =
        world ?? EcsScope.maybeOf(context, listen: false)?.world;
    final resolvedController = controller ?? EcsScope.controllerOf(context);
    if (resolvedWorld == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('EcsActionBuilder could not find an ECS world.'),
        ErrorDescription(
          'Pass world: directly or wrap this widget in EcsScope.',
        ),
      ]);
    }

    EcsActionRunCallback<T>? run;
    if (resolvedController != null) {
      run = () => resolvedController.runAction(action);
    }

    Widget buildForStatus(
      final BuildContext context,
      final EcsActionStatus status,
    ) {
      final canRun = run != null && (!disableWhileRunning || !status.isRunning);
      return builder(context, status, canRun ? run : null);
    }

    return EcsActionStatusSelector(
      statusKey: action.statusKey,
      world: resolvedWorld,
      controller: resolvedController,
      builder: buildForStatus,
    );
  }
}

/// Rebuilds from the ECS-backed status for one action key.
class EcsActionStatusSelector extends StatelessWidget {
  const EcsActionStatusSelector({
    required this.statusKey,
    required this.builder,
    super.key,
    this.world,
    this.controller,
  });

  final Object statusKey;
  final World? world;
  final EcsController? controller;
  final EcsActionStatusWidgetBuilder builder;

  @override
  Widget build(final BuildContext context) {
    final resolvedWorld =
        world ?? EcsScope.maybeOf(context, listen: false)?.world;
    final resolvedController = controller ?? EcsScope.controllerOf(context);
    if (resolvedWorld == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('EcsActionStatusSelector could not find an ECS world.'),
        ErrorDescription(
          'Pass world: directly or wrap this widget in EcsScope.',
        ),
      ]);
    }

    return EcsResourceSelector<EcsActionStatusResource, EcsActionStatus>(
      world: resolvedWorld,
      controller: resolvedController,
      select: (final resource) => resource.statusOf(statusKey),
      builder: builder,
      whenAbsent: Builder(
        builder: (final context) =>
            builder(context, const EcsActionStatus.idle()),
      ),
    );
  }
}
