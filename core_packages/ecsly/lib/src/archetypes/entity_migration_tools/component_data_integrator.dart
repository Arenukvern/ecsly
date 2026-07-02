// ignore_for_file: avoid_annotating_with_dynamic

import '../../components/columns/data_column.dart';
import 'component_data_writer.dart';

/// Integration layer for writing component data during migration.
///
/// Wraps ComponentDataWriter to ensure component data is properly written
/// to columns during entity migration operations.
class ComponentDataIntegrator {
  ComponentDataIntegrator._();

  /// Writes component data to a column at the specified row index.
  ///
  /// Handles various component patterns (x/y fields, value fields, lists, primitives)
  /// and writes to the appropriate column type (FloatColumn, IntColumn, etc.).
  ///
  /// If [data] is null, skips writing (column is already zero-initialized by addBlank()).
  static void writeComponentData(
    final DataColumn column,
    final int rowIndex,
    final dynamic data,
  ) {
    // Skip writing if data is null - column is already zero-initialized
    if (data == null) {
      return;
    }
    ComponentDataWriter.writeToColumn(column, rowIndex, data);
  }
}
