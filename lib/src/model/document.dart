// A document: the text being edited and the file it belongs to (none while untitled). Plain
// text files keep their encoding, byte order mark and line endings; rich text is RTF.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../editor/doc_controller.dart';
import 'rtf.dart';
import 'styled.dart';
import 'text_codec.dart';

/// Plain or rich text.
enum DocFormat { plain, rich }

/// Why a file could not be opened.
enum OpenProblem { missing, notText, unreadable, directory }

class OpenFailure implements Exception {
  const OpenFailure(this.problem, this.path);
  final OpenProblem problem;
  final String path;
}

/// The defaults of rich text: the font and size of characters that have none of their own.
@immutable
class RichDefaults {
  const RichDefaults({this.font = uiFont, this.size = 13});
  final String font;
  final double size;
}

/// The file name of [path].
String baseName(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// The extension of [path], lower case, without the dot ('' when none).
String extensionOf(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// [path] with its extension replaced by [ext].
String withExtension(String name, String ext) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return '$stem.$ext';
}

class TextDocument extends ChangeNotifier {
  TextDocument._({
    required this.controller,
    required this.defaults,
    this.path,
    this.untitledNumber = 0,
    this.encoding = TextEncoding.utf8,
    this.bom = false,
    this.lineEnding = LineEnding.lf,
  }) : _saved = controller.doc,
       _savedRich = controller.rich,
       _opened = controller.doc,
       _openedRich = controller.rich {
    controller.onEdited = notifyListeners;
    _stat();
  }

  /// A new untitled document; [number] tells untitled documents apart (1 is "Untitled").
  factory TextDocument.untitled({
    required DocFormat format,
    required RichDefaults defaults,
    int number = 1,
  }) => TextDocument._(
    controller: DocController(rich: format == DocFormat.rich),
    defaults: defaults,
    untitledNumber: number,
  );

  /// The file at [path]. RTF files open as rich text, the rest as plain text in the
  /// encoding found in the file ([encoding] forces one). Throws [OpenFailure].
  factory TextDocument.open(
    String path, {
    required RichDefaults defaults,
    TextEncoding? encoding,
  }) {
    final loaded = _load(path, defaults, encoding);
    return TextDocument._(
      controller: DocController(doc: loaded.doc, rich: loaded.rich),
      defaults: defaults,
      path: path,
      encoding: loaded.encoding,
      bom: loaded.bom,
      lineEnding: loaded.lineEnding,
    );
  }

  final DocController controller;
  final RichDefaults defaults;

  /// The file; null while untitled.
  String? path;
  final int untitledNumber;
  TextEncoding encoding;
  bool bom;
  LineEnding lineEnding;

  StyledText _saved;
  bool _savedRich;
  final StyledText _opened;
  final bool _openedRich;

  /// The file's modification time and size when it was last read or written.
  DateTime? fileModified;
  int? fileSize;

  DocFormat get format => controller.rich ? DocFormat.rich : DocFormat.plain;

  /// Whether there are changes not written to the file.
  bool get edited => controller.doc != _saved || controller.rich != _savedRich;

  /// Whether the text differs from when the file was opened.
  bool get changedSinceOpened =>
      controller.doc != _opened || controller.rich != _openedRich;

  bool get isUntitled => path == null;

  /// An untitled document with nothing in it: Open replaces it.
  bool get isBlank => path == null && !edited && controller.text.isEmpty;

  /// The file's extension does not match the format (rich text in a .txt file), or there is
  /// no file: Save asks where.
  bool get needsSaveAs {
    final p = path;
    if (p == null) return true;
    final rtf = extensionOf(p) == 'rtf';
    return controller.rich != rtf;
  }

  void _stat() {
    final p = path;
    if (p == null) return;
    try {
      final st = File(p).statSync();
      if (st.type == FileSystemEntityType.notFound) return;
      fileModified = st.modified;
      fileSize = st.size;
    } on FileSystemException {
      // Unknown.
    }
  }

  /// Whether the file changed on disk since it was read or written here.
  bool get changedOnDisk {
    final p = path;
    final known = fileModified;
    if (p == null || known == null) return false;
    try {
      final st = File(p).statSync();
      if (st.type == FileSystemEntityType.notFound) return false;
      return st.modified != known;
    } on FileSystemException {
      return false;
    }
  }

  /// The bytes the document is written as.
  Uint8List bytes({TextEncoding? encoding}) {
    if (controller.rich) {
      return Uint8List.fromList(
        writeRtf(
          controller.doc,
          defaultFont: defaults.font,
          defaultSize: defaults.size,
        ).codeUnits,
      );
    }
    return encodeText(
      controller.text,
      encoding ?? this.encoding,
      bom: bom && (encoding ?? this.encoding) != TextEncoding.latin1,
      lineEnding: lineEnding,
    );
  }

  /// Writes the document to [to] (its own file when null), in [encoding] for plain text.
  /// Throws [FileSystemException] or [UnencodableException].
  void save({String? to, TextEncoding? encoding}) {
    final target = to ?? path;
    if (target == null) throw const FileSystemException('no file');
    final data = bytes(encoding: encoding);
    final file = File(target);
    if (!file.existsSync()) {
      // A new file: written aside and renamed into place, never half a file.
      final staged = File('$target.saving');
      staged.writeAsBytesSync(data, flush: true);
      staged.renameSync(target);
    } else {
      // An existing file is written in place, keeping its permissions and links; a copy is
      // written first, so a failure (a full disk) leaves the new text next to it.
      File? copy = File('${file.resolveSymbolicLinksSync()}.saving');
      try {
        copy.writeAsBytesSync(data, flush: true);
      } on FileSystemException {
        // A folder that takes no new files: the file is written directly.
        copy = null;
      }
      file.writeAsBytesSync(data, flush: true);
      copy?.deleteSync();
    }
    path = target;
    if (encoding != null) this.encoding = encoding;
    _saved = controller.doc;
    _savedRich = controller.rich;
    _stat();
    notifyListeners();
  }

  /// Back to the text as it was last saved (or opened).
  void revertToSaved() {
    controller.load(_saved, rich: _savedRich);
    notifyListeners();
  }

  /// Back to the text as it was when the file was opened.
  void revertToOpened() {
    controller.load(_opened, rich: _openedRich);
    notifyListeners();
  }

  /// Reads the file again in [encoding] (plain text only). Throws [OpenFailure].
  void reopen(TextEncoding encoding) {
    final p = path;
    if (p == null || controller.rich) return;
    final loaded = _load(p, defaults, encoding);
    this.encoding = loaded.encoding;
    bom = loaded.bom;
    lineEnding = loaded.lineEnding;
    _saved = loaded.doc;
    _savedRich = loaded.rich;
    controller.load(loaded.doc, rich: loaded.rich);
    _stat();
    notifyListeners();
  }

  /// Renames the file to [name] in the same folder. Throws [FileSystemException].
  void rename(String name) {
    final p = path;
    if (p == null) return;
    final slash = p.lastIndexOf('/');
    final target = '${slash < 0 ? '' : p.substring(0, slash + 1)}$name';
    if (target == p) return;
    if (File(target).existsSync()) {
      throw FileSystemException('exists', target);
    }
    File(p).renameSync(target);
    path = target;
    notifyListeners();
  }

  /// Counts for Document Info.
  ({int words, int characters, int paragraphs}) get counts {
    final text = controller.text;
    final words = RegExp(
      r"[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*",
      unicode: true,
    ).allMatches(text).length;
    final characters = text.runes.where((r) => r != 0x0A).length;
    final paragraphs = text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;
    return (words: words, characters: characters, paragraphs: paragraphs);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _Loaded {
  const _Loaded(this.doc, this.rich, this.encoding, this.bom, this.lineEnding);
  final StyledText doc;
  final bool rich;
  final TextEncoding encoding;
  final bool bom;
  final LineEnding lineEnding;
}

_Loaded _load(String path, RichDefaults defaults, TextEncoding? forced) {
  final file = File(path);
  final Uint8List bytes;
  try {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      throw OpenFailure(OpenProblem.missing, path);
    }
    if (type == FileSystemEntityType.directory) {
      throw OpenFailure(OpenProblem.directory, path);
    }
    bytes = file.readAsBytesSync();
  } on FileSystemException {
    throw OpenFailure(OpenProblem.unreadable, path);
  }
  if (forced == null && looksLikeRtf(bytes)) {
    try {
      final source = String.fromCharCodes(bytes);
      final doc = readRtf(
        source,
        defaultFont: defaults.font,
        defaultSize: defaults.size,
      );
      return _Loaded(doc, true, TextEncoding.utf8, false, LineEnding.lf);
    } on RtfFormatException {
      // Read as plain text below.
    }
  }
  try {
    final decoded = decodeText(bytes, forced: forced);
    return _Loaded(
      StyledText.plain(decoded.text),
      false,
      decoded.encoding,
      decoded.bom,
      decoded.lineEnding,
    );
  } on NotTextException {
    throw OpenFailure(OpenProblem.notText, path);
  }
}
