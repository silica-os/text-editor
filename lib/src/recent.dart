// The files opened lately (File › Open Recent), kept in `$XDG_STATE_HOME/text-editor/recent`, one
// path per line, the latest first. Under `flutter test` they stay in memory.

import 'dart:io';

/// The recent files of Text Editor.
class RecentFiles {
  RecentFiles._();

  /// How many files the menu keeps.
  static const limit = 10;

  static List<String>? _paths;

  static File? get _file {
    final env = Platform.environment;
    if (env.containsKey('FLUTTER_TEST')) return null;
    final home = env['HOME'];
    final state =
        env['XDG_STATE_HOME'] ?? (home == null ? null : '$home/.local/state');
    return state == null ? null : File('$state/text-editor/recent');
  }

  /// The paths, the latest first.
  static List<String> get paths {
    final known = _paths;
    if (known != null) return List.unmodifiable(known);
    var read = <String>[];
    try {
      read = _file?.readAsLinesSync().where((p) => p.isNotEmpty).toList() ?? [];
    } on FileSystemException {
      // No list yet.
    }
    _paths = read.take(limit).toList();
    return List.unmodifiable(_paths!);
  }

  /// Puts `path` first.
  static void add(String path) {
    final list = [path, ...paths.where((p) => p != path)];
    _paths = list.take(limit).toList();
    _save();
  }

  /// Forgets every file (Clear Menu).
  static void clear() {
    _paths = [];
    _save();
  }

  /// Forgets all and the stored list, for tests.
  static void reset() => _paths = [];

  static void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(_paths!.map((p) => '$p\n').join());
    } on FileSystemException {
      // The list stays in memory.
    }
  }
}
