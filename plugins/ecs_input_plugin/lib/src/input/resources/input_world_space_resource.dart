import 'package:ecsly/ecsly.dart';

/// Pure-Dart world-space context for input (zoom, optional inverse transform).
///
/// Input systems read this only. Camera/control plugins or the host write it.
/// When absent, input uses zoom = 1 and allowsEntitySelection = true.
class InputWorldSpaceResource extends Resource {
  /// Current zoom (e.g. from active camera). Default 1.
  double zoom;

  /// Whether entity selection is allowed in current mode. Default true.
  bool allowsEntitySelection;

  /// Optional screen-to-world transform (inverse scale).
  double? invScale;

  /// Optional screen-to-world transform (inverse tx).
  double? invTx;

  /// Optional screen-to-world transform (inverse ty).
  double? invTy;

  InputWorldSpaceResource({
    this.zoom = 1.0,
    this.allowsEntitySelection = true,
    this.invScale,
    this.invTx,
    this.invTy,
  });
}
