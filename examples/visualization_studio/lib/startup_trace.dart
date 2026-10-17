import 'package:ecsly_flutter/ecsly_flutter.dart';

/// Per-world monotonic timings. Marks describe owner work, not screen delivery.
class StartupTrace extends Resource {
  final Stopwatch _clock = Stopwatch()..start();
  final Map<String, int> _marks = {};
  String? _failure;
  void fail(Object error) {
    _failure = '$error';
    mark('initializationFailed');
  }

  void mark(String name) =>
      _marks.putIfAbsent(name, () => _clock.elapsedMicroseconds);
  Map<String, Object?> toJson() => {
    'origin': 'world creation; monotonic microseconds',
    'marksUs': Map<String, int>.of(_marks),
    'presentationVerified': false,
    'failure': _failure,
  };
}
