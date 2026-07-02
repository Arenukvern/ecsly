import 'columns/data_column.dart';

/// Factory for creating component facades.
abstract class ComponentFacadeFactory<T> {
  /// Create facade instance.
  T create(final int index);

  /// Initialize static column reference.
  void initialize(final DataColumn column);
}
