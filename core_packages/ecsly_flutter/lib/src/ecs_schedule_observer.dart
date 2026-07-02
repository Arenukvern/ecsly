import 'package:flutter/foundation.dart';

enum EcsFlutterScheduleReason { onMount, afterAction, onResume, onPause, frame }

typedef EcsScheduleRunObserver = void Function(EcsScheduleRunEvent event);

@immutable
class EcsScheduleRunEvent {
  const EcsScheduleRunEvent({
    required this.scheduleName,
    required this.reason,
    required this.elapsed,
    this.error,
    this.stackTrace,
  });

  final String scheduleName;
  final EcsFlutterScheduleReason reason;
  final Duration elapsed;
  final Object? error;
  final StackTrace? stackTrace;

  bool get succeeded => error == null;
}
