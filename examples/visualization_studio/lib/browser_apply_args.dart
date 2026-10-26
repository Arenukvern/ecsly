/// Normalizes JS-number representation at the browser boundary. The resident
/// transaction still receives and validates Dart integers. JS and Wasm differ
/// in whether dartify treats an integral JS number as int or double.
Map<String, Object?> browserApplyArgs(Object? raw) {
  if (raw is! Map) throw const FormatException('Expected browser apply object');
  final values = Map<String, Object?>.from(raw);
  final revision = values['expectedRevision'];
  if (revision is! num ||
      !revision.isFinite ||
      revision < 0 ||
      revision > 9007199254740991 ||
      revision != revision.truncateToDouble()) {
    throw const FormatException('expectedRevision must be a safe integer');
  }
  values['expectedRevision'] = revision.toInt();
  return values;
}
