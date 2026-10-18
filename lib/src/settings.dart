// Text Editor's settings, in `$XDG_CONFIG_HOME/text-editor/settings`, one `key=value` per line:
// the format of new documents, the fonts, the encodings for opening and saving plain text,
// and whether changes are saved by themselves. Under `flutter test` nothing is written.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'editor/doc_controller.dart';
import 'model/document.dart';
import 'model/text_codec.dart';

class EditorSettings extends ChangeNotifier {
  EditorSettings(this.path);

  factory EditorSettings.forUser(Map<String, String> env) {
    final home = env['HOME'] ?? '.';
    final config = env['XDG_CONFIG_HOME'] ?? '$home/.config';
    return EditorSettings(
      env.containsKey('FLUTTER_TEST') ? null : '$config/text-editor/settings',
    )..load();
  }

  final String? path;

  DocFormat _newFormat = DocFormat.rich;
  String _richFont = uiFont;
  double _richSize = 13;
  double _plainSize = 12;
  TextEncoding? _openEncoding;
  TextEncoding? _saveEncoding;
  bool _autosave = true;

  /// The format of a new document.
  DocFormat get newFormat => _newFormat;
  set newFormat(DocFormat v) => _set(() => _newFormat = v);

  /// The default font of rich text.
  String get richFont => _richFont;
  set richFont(String v) => _set(() => _richFont = v);

  double get richSize => _richSize;
  set richSize(double v) => _set(() => _richSize = v.clamp(6, 96));

  /// The size of plain text (always JetBrains Mono).
  double get plainSize => _plainSize;
  set plainSize(double v) => _set(() => _plainSize = v.clamp(6, 96));

  /// The encoding plain text files are read in; null: found from the file.
  TextEncoding? get openEncoding => _openEncoding;
  set openEncoding(TextEncoding? v) => _set(() => _openEncoding = v);

  /// The encoding new plain text files are written in; null: UTF-8 (files keep theirs).
  TextEncoding? get saveEncoding => _saveEncoding;
  set saveEncoding(TextEncoding? v) => _set(() => _saveEncoding = v);

  /// Whether a document with a file is saved by itself while editing and on closing.
  bool get autosave => _autosave;
  set autosave(bool v) => _set(() => _autosave = v);

  RichDefaults get richDefaults =>
      RichDefaults(font: _richFont, size: _richSize);

  void _set(VoidCallback f) {
    f();
    save();
    notifyListeners();
  }

  void load() {
    final p = path;
    if (p == null) return;
    try {
      final file = File(p);
      if (!file.existsSync()) return;
      for (final line in file.readAsLinesSync()) {
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        final value = line.substring(eq + 1).trim();
        switch (key) {
          case 'new-format':
            _newFormat = DocFormat.values.asNameMap()[value] ?? _newFormat;
          case 'rich-font':
            if (value.isNotEmpty) _richFont = value;
          case 'rich-size':
            _richSize = (double.tryParse(value) ?? _richSize).clamp(6, 96);
          case 'plain-size':
            _plainSize = (double.tryParse(value) ?? _plainSize).clamp(6, 96);
          case 'open-encoding':
            _openEncoding = TextEncoding.values.asNameMap()[value];
          case 'save-encoding':
            _saveEncoding = TextEncoding.values.asNameMap()[value];
          case 'autosave':
            _autosave = value != 'false';
        }
      }
    } on FileSystemException {
      // The defaults.
    } on FormatException {
      // Rewritten on the next change.
    }
  }

  void save() {
    final p = path;
    if (p == null) return;
    try {
      final file = File(p);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        'new-format=${_newFormat.name}\n'
        'rich-font=$_richFont\n'
        'rich-size=$_richSize\n'
        'plain-size=$_plainSize\n'
        'open-encoding=${_openEncoding?.name ?? 'auto'}\n'
        'save-encoding=${_saveEncoding?.name ?? 'auto'}\n'
        'autosave=$_autosave\n',
      );
    } on FileSystemException {
      // A read-only home: the app keeps working.
    }
  }
}
