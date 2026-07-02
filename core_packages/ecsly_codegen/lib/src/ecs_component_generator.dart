// ignore_for_file: missing_whitespace_between_adjacent_strings, deprecated_member_use

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'annotations.dart';

final _dartIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Generates ColumnFactory and FacadeFactory for @EcsComponent-annotated
/// component classes.
class EcsComponentGenerator extends GeneratorForAnnotation<EcsComponent> {
  @override
  String generateForAnnotatedElement(
    final Element element,
    final ConstantReader annotation,
    final BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@EcsComponent() can only be applied to classes.',
        element: element,
      );
    }

    if (!_extendsComponent(element)) {
      throw InvalidGenerationSourceError(
        '@EcsComponent() can only be applied to classes that extend Component.',
        element: element,
      );
    }

    final className = element.name!;
    final facade = annotation.read('facade').stringValue;
    final columnTypeIndex = annotation
        .read('column')
        .objectValue
        .getField('index')!
        .toIntValue()!;
    final columnType = EcsColumnType.values[columnTypeIndex];
    final stride = annotation.read('stride').intValue;

    final validationError = ecsComponentAnnotationError(
      facade: facade,
      columnType: columnType,
      stride: stride,
    );
    if (validationError != null) {
      throw InvalidGenerationSourceError(validationError, element: element);
    }

    return generateEcsComponentFactories(
      className: className,
      facade: facade,
      columnType: columnType,
      stride: stride,
    );
  }
}

bool _extendsComponent(final ClassElement element) =>
    element.allSupertypes.any((final type) => type.element.name == 'Component');

/// Returns a validation error message, or `null` when valid.
String? ecsComponentAnnotationError({
  required final String facade,
  required final EcsColumnType columnType,
  required final int stride,
}) {
  if (!_dartIdentifier.hasMatch(facade)) {
    return "facade must be a valid Dart identifier, got '$facade'.";
  }

  if (columnType != EcsColumnType.uint8 && stride <= 0) {
    return 'stride must be > 0 for ${columnType.name} columns, got $stride.';
  }

  return null;
}

/// Validates annotation fields shared by analyzer and unit tests.
void validateEcsComponentAnnotation({
  required final String facade,
  required final EcsColumnType columnType,
  required final int stride,
}) {
  final error = ecsComponentAnnotationError(
    facade: facade,
    columnType: columnType,
    stride: stride,
  );
  if (error != null) {
    throw ArgumentError(error);
  }
}

/// Generates the Dart source for a single `@EcsComponent` declaration.
///
/// Kept separate from analyzer/source_gen plumbing so release tests can cover
/// the emitted API shape without relying on an in-memory package resolver.
String generateEcsComponentFactories({
  required final String className,
  required final String facade,
  required final EcsColumnType columnType,
  required final int stride,
}) {
  validateEcsComponentAnnotation(
    facade: facade,
    columnType: columnType,
    stride: stride,
  );

  // Derive the base name: 'TestPositionComponent' -> 'TestPosition'
  final baseName = className.endsWith('Component')
      ? className.substring(0, className.length - 'Component'.length)
      : className;

  final columnClassName = _columnClassName(columnType);
  final columnConstructor = _columnConstructor(columnType, stride);

  final buf = StringBuffer();

  buf.writeln('class ${baseName}ColumnFactory extends ColumnFactory {');
  buf.writeln('  @override');
  buf.writeln('  DataColumn createColumn(');
  buf.writeln('    final ComponentId componentId, {');
  buf.writeln('    final int initialCapacity = 8,');
  buf.writeln('  }) => $columnConstructor;');
  buf.writeln('}');
  buf.writeln();

  buf.writeln(
    'class ${facade}FacadeFactory '
    'extends ComponentFacadeFactory<$facade> {',
  );
  buf.writeln('  late $columnClassName _column;');
  buf.writeln();
  buf.writeln('  @override');
  buf.writeln(
    '  $facade create(final int index) => $facade((index, _column));',
  );
  buf.writeln();
  buf.writeln('  @override');
  buf.writeln('  void initialize(final DataColumn column) {');
  buf.writeln('    if (column case final $columnClassName column) {');
  buf.writeln('      _column = column;');
  buf.writeln('      return;');
  buf.writeln('    }');
  buf.writeln(
    '    throw ArgumentError('
    "'$facade requires $columnClassName, "
    r"got ${column.runtimeType}.');",
  );
  buf.writeln('  }');
  buf.writeln('}');

  return buf.toString();
}

String _columnClassName(final EcsColumnType type) => switch (type) {
  EcsColumnType.float32 => 'FloatColumn',
  EcsColumnType.int32 => 'IntColumn',
  EcsColumnType.uint8 => 'Uint8Column',
};

String _columnConstructor(final EcsColumnType type, final int stride) =>
    switch (type) {
      EcsColumnType.float32 =>
        'FloatColumn(initialCapacity: initialCapacity, stride: $stride)',
      EcsColumnType.int32 =>
        'IntColumn(initialCapacity: initialCapacity, stride: $stride)',
      EcsColumnType.uint8 => 'Uint8Column(initialCapacity: initialCapacity)',
    };
