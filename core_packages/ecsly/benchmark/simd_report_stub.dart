/// Host facts for compilers without `dart:io` (`dart2js`, `dart2wasm`).
Map<String, Object?> reportEnvironment() => {
  'os': 'unknown',
  'osVersion': '',
  'dartVersion': '',
  'processors': 0,
  'executable': '',
  'gitCommit': '',
  'gitDirty': false,
};

/// JS and Wasm hosts have no filesystem, so they print the report and
/// ignore [path].
void writeReport(String? path, String text) {
  // ignore: avoid_print
  print(text);
}
