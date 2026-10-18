// The command line: the files to open come after the bundle in the embedder's command line
// (`Exec=… @BUNDLE@ %F`) or as `--dart-arg <path>`, and reach `main` as plain arguments.
// Options (`--something`) are not files.

/// The files named by `args`, as absolute-or-relative paths: `file://` URIs are turned into
/// paths, options are skipped, duplicates dropped.
List<String> filesFromArgs(List<String> args) {
  final out = <String>[];
  var options = true;
  for (final arg in args) {
    if (options && arg == '--') {
      options = false;
      continue;
    }
    if (options && arg.startsWith('--')) continue;
    if (arg.isEmpty) continue;
    final path = arg.startsWith('file://') ? _uriPath(arg) : arg;
    if (path != null && !out.contains(path)) out.add(path);
  }
  return out;
}

String? _uriPath(String uri) {
  try {
    return Uri.parse(uri).toFilePath();
  } on FormatException {
    return null;
  } on UnsupportedError {
    return null;
  }
}
