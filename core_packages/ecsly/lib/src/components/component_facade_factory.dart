import 'columns/data_column.dart';

/// Factory for creating component facades.
abstract class ComponentFacadeFactory<T> {
  /// Create facade instance.
  T create(int index);

  /// Initialize static column reference.
  void initialize(DataColumn column);
}
