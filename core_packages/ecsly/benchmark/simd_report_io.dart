import 'dart:io';

/// VM and AOT host facts. Matches the fields required by ADR 0001.
Map<String, Object?> reportEnvironment() => {
  'os': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'dartVersion': Platform.version,
  'processors': Platform.numberOfProcessors,
  'executable': Platform.executable,
  'gitCommit': _git(['rev-parse', '--short=12', 'HEAD']),
  'gitDirty': _git(['status', '--porcelain']).isNotEmpty,
};

void writeReport(String? path, String text) {
  if (path == null) {
    stdout.writeln(text);
    return;
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$text\n');
}

String _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) return '';
  return (result.stdout as String).trim();
}
