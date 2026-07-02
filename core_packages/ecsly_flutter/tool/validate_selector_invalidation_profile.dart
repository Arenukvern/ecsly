import 'dart:convert';
import 'dart:io';

void main(final List<String> args) {
  final path = args.isEmpty
      ? 'build/reports/selector_invalidation_profile.v1.json'
      : args.single;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing selector invalidation profile: $path');
    exit(66);
  }

  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('Profile root must be a JSON object.');
    exit(65);
  }
  if (decoded['schemaVersion'] != 1) {
    stderr.writeln('Unsupported schemaVersion: ${decoded['schemaVersion']}');
    exit(65);
  }
  _requireString(decoded, 'package');
  _requireString(decoded, 'generatedAt');
  _requireString(decoded, 'command');
  final environment = _requireMap(decoded, 'environment');
  _requireString(environment, 'dartVersion');
  _requireString(environment, 'flutterVersion');
  _requireString(environment, 'gitCommit');
  _requireBool(environment, 'gitDirty');

  final scenarios = decoded['scenarios'];
  if (scenarios is! List || scenarios.isEmpty) {
    stderr.writeln('Profile must contain at least one scenario.');
    exit(65);
  }

  for (final rawScenario in scenarios) {
    if (rawScenario is! Map<String, Object?>) {
      stderr.writeln('Each scenario must be a JSON object.');
      exit(65);
    }
    _requireString(rawScenario, 'scenario');
    _requireString(rawScenario, 'subscriptionMode');
    _requireString(rawScenario, 'selectorKind');
    _requireString(rawScenario, 'invalidationKind');
    _requireInt(rawScenario, 'controllerNotificationCount');
    final selectorDelta = _requireInt(rawScenario, 'selectorCallDelta');
    final builderDelta = _requireIntWithFallback(
      rawScenario,
      'selectorBuilderCallDelta',
      'widgetBuildDelta',
    );
    final expectedInvalidated = _requireBool(
      rawScenario,
      'expectedInvalidated',
    );
    final selectedValueChanged = _requireBool(
      rawScenario,
      'selectedValueChanged',
    );
    final expectedSelectorDelta =
        _optionalInt(rawScenario, 'expectedSelectorCallDelta') ??
        (expectedInvalidated ? 1 : 0);
    final expectedBuilderDelta =
        _optionalInt(rawScenario, 'expectedSelectorBuilderCallDelta') ??
        (selectedValueChanged ? 1 : 0);
    final requiredSelectorDelta = expectedInvalidated ? 1 : 0;
    final requiredBuilderDelta = selectedValueChanged ? 1 : 0;
    if (expectedSelectorDelta != requiredSelectorDelta) {
      stderr.writeln(
        'Expected selector call delta must be $requiredSelectorDelta for '
        '${rawScenario['scenario']}, got $expectedSelectorDelta',
      );
      exit(65);
    }
    if (expectedBuilderDelta != requiredBuilderDelta) {
      stderr.writeln(
        'Expected selector builder call delta must be $requiredBuilderDelta '
        'for ${rawScenario['scenario']}, got $expectedBuilderDelta',
      );
      exit(65);
    }
    if (selectorDelta != expectedSelectorDelta) {
      stderr.writeln(
        'Unexpected selector call delta for ${rawScenario['scenario']}: '
        'actual=$selectorDelta expected=$expectedSelectorDelta',
      );
      exit(65);
    }
    if (builderDelta != expectedBuilderDelta) {
      stderr.writeln(
        'Unexpected selector builder call delta for '
        '${rawScenario['scenario']}: actual=$builderDelta '
        'expected=$expectedBuilderDelta',
      );
      exit(65);
    }
  }
}

String _requireString(final Map<String, Object?> object, final String key) {
  final value = object[key];
  if (value is String && value.isNotEmpty) return value;
  stderr.writeln('Scenario field `$key` must be a non-empty string.');
  exit(65);
}

int _requireInt(final Map<String, Object?> object, final String key) {
  final value = object[key];
  if (value is int && value >= 0) return value;
  stderr.writeln('Scenario field `$key` must be a non-negative integer.');
  exit(65);
}

int _requireIntWithFallback(
  final Map<String, Object?> object,
  final String preferredKey,
  final String fallbackKey,
) => _optionalInt(object, preferredKey) ?? _requireInt(object, fallbackKey);

int? _optionalInt(final Map<String, Object?> object, final String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is int && value >= 0) return value;
  stderr.writeln('Scenario field `$key` must be a non-negative integer.');
  exit(65);
}

bool _requireBool(final Map<String, Object?> object, final String key) {
  final value = object[key];
  if (value is bool) return value;
  stderr.writeln('Scenario field `$key` must be a boolean.');
  exit(65);
}

Map<String, Object?> _requireMap(
  final Map<String, Object?> object,
  final String key,
) {
  final value = object[key];
  if (value is Map<String, Object?>) return value;
  stderr.writeln('Scenario field `$key` must be a JSON object.');
  exit(65);
}
