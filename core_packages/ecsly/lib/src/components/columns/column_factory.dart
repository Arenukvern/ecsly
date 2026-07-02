import '../component.dart';
import 'data_column.dart';

///
/// Used to create columns for components.
/// Example:
/// ```markdown
/// - Position → FloatColumn(stride: 2)
/// - Velocity → FloatColumn(stride: 2)
/// - Health → Uint8Column (0-255 range)
/// - Complex types → ObjectColumn<T>
/// ```
///
/// See [ColumnFactoryRegistry] for the registry that manages these factories.
// ignore: one_member_abstracts
abstract class ColumnFactory {
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  });
}

class ObjectColumnFactory<T extends Object> extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => ObjectColumn<T>(initialCapacity: initialCapacity);
}
