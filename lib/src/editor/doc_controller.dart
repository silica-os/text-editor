// The editing controller of a document: a TextEditingController that keeps the character
// styles of rich text through every change (found by comparing the old and the new text), its
// own undo history (styles included), the rich clipboard, the format commands, list markers
// that go on with Return, and the find matches it draws.

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/styled.dart';

/// The paragraph styles of the format bar: shortcuts that set the size, weight and font of
/// whole paragraphs.
enum ParaPreset { title, heading, subheading, body, mono }

/// How text is drawn: the defaults and the colours.
class DocLook {
  const DocLook({
    required this.font,
    required this.size,
    required this.text,
    required this.match,
    required this.currentMatch,
    this.package,
    this.zoom = 1,
  });

  /// The default font family and size.
  final String font;
  final double size;

  /// The package serving [font] (silica_ui's Inter and JetBrains Mono), null for system fonts.
  final String? package;
  final Color text;
  final Color match;
  final Color currentMatch;

  /// View › Zoom.
  final double zoom;
}

/// The family of the monospaced font served by silica_ui.
const String monoFont = 'JetBrains Mono';

/// The interface font served by silica_ui.
const String uiFont = 'Inter';

/// Fonts silica_ui serves; others come from the system.
const Set<String> bundledFonts = {uiFont, monoFont};

/// Distance between tab stops in rich text, in points (kit: list text 24 after the bullet).
const double richTabStop = 24;

/// Tab stops of plain text, in characters.
const int plainTabStop = 4;

class _Snapshot {
  const _Snapshot(this.doc, this.selection);
  final StyledText doc;
  final TextSelection selection;
}

class _Clip {
  const _Clip(this.plain, this.runs);
  final String plain;
  final List<Run> runs;
}

enum _EditKind { typing, deleting, other }

/// A list marker at the start of a line: tabs, then a bullet or a number, then a tab.
final RegExp listMarker = RegExp(r'^(\t*)(•|◦|–|\d+[.)])\t');

class DocController extends TextEditingController {
  DocController({StyledText? doc, bool rich = true})
    : this._(doc ?? StyledText.plain(''), rich);

  DocController._(StyledText doc, this._rich)
    : _doc = doc,
      super.fromValue(
        TextEditingValue(
          text: doc.text,
          selection: const TextSelection.collapsed(offset: 0),
        ),
      );

  StyledText _doc;
  bool _rich;
  bool _internal = false;

  StyledText get doc => _doc;

  /// Rich text (styles kept) or plain text (one style, monospaced).
  bool get rich => _rich;

  CharStyle? _pending;
  int? _pendingAt;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  _EditKind _lastKind = _EditKind.other;
  int _lastEnd = -1;
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const int undoLimit = 500;

  static _Clip? _clip;

  /// Called after every change of the text or its styles (not the selection).
  VoidCallback? onEdited;

  /// How the text is drawn; set by the editor before it builds.
  DocLook? look;

  // Find.
  String _find = '';
  bool _matchCase = false;
  List<(int, int)> _matches = const [];
  int _current = -1;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Replaces the document (open, revert): the undo history starts again.
  void load(StyledText doc, {bool? rich}) {
    _doc = doc;
    if (rich != null) _rich = rich;
    _undo.clear();
    _redo.clear();
    _pending = null;
    _set(const TextSelection.collapsed(offset: 0));
    _refind();
  }

  void _set(TextSelection selection, {TextRange composing = TextRange.empty}) {
    _internal = true;
    try {
      final len = _doc.text.length;
      super.value = TextEditingValue(
        text: _doc.text,
        selection: selection.isValid
            ? selection.copyWith(
                baseOffset: selection.baseOffset.clamp(0, len),
                extentOffset: selection.extentOffset.clamp(0, len),
              )
            : TextSelection.collapsed(offset: len),
        composing: composing,
      );
    } finally {
      _internal = false;
    }
  }

  @override
  set value(TextEditingValue v) {
    if (_internal) {
      super.value = v;
      return;
    }
    final old = _doc;
    if (v.text == old.text) {
      if (v.selection != value.selection) _pending = null;
      _internal = true;
      try {
        super.value = v;
      } finally {
        _internal = false;
      }
      return;
    }
    final oldText = old.text;
    final newText = v.text;
    final minLen = min(oldText.length, newText.length);
    final grow = newText.length - oldText.length;
    var limit = minLen;
    if (v.selection.isValid && v.selection.isCollapsed) {
      final hint = v.selection.baseOffset - max<int>(0, grow);
      if (hint >= 0) limit = min(limit, hint);
    }
    var p = 0;
    while (p < limit && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < minLen - p &&
        oldText.codeUnitAt(oldText.length - 1 - s) ==
            newText.codeUnitAt(newText.length - 1 - s)) {
      s++;
    }
    final oldEnd = oldText.length - s;
    final inserted = newText.substring(p, newText.length - s);
    // Return in a list: the next line gets a marker, or an empty item ends the list.
    if (_rich && inserted == '\n' && oldEnd == p) {
      final lineStart = oldText.lastIndexOf('\n', p - 1) + 1;
      final lineEndAt = oldText.indexOf('\n', p);
      final lineEnd = lineEndAt < 0 ? oldText.length : lineEndAt;
      final line = oldText.substring(lineStart, lineEnd);
      final m = listMarker.firstMatch(line);
      if (m != null && p >= lineStart + m.end) {
        if (line.length == m.end && p == lineEnd) {
          _replace(
            lineStart,
            lineEnd,
            '',
            const [],
            kind: _EditKind.other,
            caret: lineStart,
          );
          return;
        }
        final marker = _nextMarker(m);
        final text = '\n$marker';
        _replace(
          p,
          p,
          text,
          Runs.of(text.length, _typingStyle(old, p, p)),
          kind: _EditKind.other,
        );
        return;
      }
    }
    final clip = _clip;
    final runs = clip != null && clip.plain == inserted && _rich
        ? clip.runs
        : Runs.of(inserted.length, _typingStyle(old, p, oldEnd));
    _replace(
      p,
      oldEnd,
      inserted,
      runs,
      selection: v.selection,
      composing: v.composing,
    );
  }

  static String _nextMarker(RegExpMatch m) {
    final tabs = m.group(1) ?? '';
    final mark = m.group(2) ?? '•';
    final n = int.tryParse(mark.substring(0, max(0, mark.length - 1)));
    final next = n == null ? mark : '${n + 1}${mark[mark.length - 1]}';
    return '$tabs$next\t';
  }

  CharStyle _typingStyle(StyledText old, int p, int end) {
    if (!_rich) return CharStyle.plain;
    if (_pending != null && _pendingAt == p) return _pending!;
    if (end > p) return Runs.at(old.runs, p);
    if (p > 0) return Runs.at(old.runs, p - 1);
    if (old.text.isNotEmpty) return Runs.at(old.runs, 0);
    return CharStyle.plain;
  }

  void _replace(
    int p,
    int oldEnd,
    String inserted,
    List<Run> runs, {
    TextSelection? selection,
    TextRange composing = TextRange.empty,
    _EditKind? kind,
    int? caret,
  }) {
    final old = _doc;
    final before = value.selection;
    final text = old.text.replaceRange(p, oldEnd, inserted);
    final newRuns = _rich
        ? Runs.replace(old.runs, p, oldEnd, runs)
        : Runs.of(text.length, CharStyle.plain);
    final editKind =
        kind ??
        (oldEnd == p && inserted.length == 1 && inserted != '\n'
            ? _EditKind.typing
            : inserted.isEmpty && oldEnd - p == 1
            ? _EditKind.deleting
            : _EditKind.other);
    _recordEdit(old, before, editKind, p, p + inserted.length);
    _doc = StyledText(text, newRuns);
    _pending = null;
    _set(
      caret != null
          ? TextSelection.collapsed(offset: caret)
          : selection ?? TextSelection.collapsed(offset: p + inserted.length),
      composing: composing,
    );
    _refind();
    onEdited?.call();
  }

  // MARK: undo

  void _recordEdit(
    StyledText old,
    TextSelection selection,
    _EditKind kind,
    int start,
    int end,
  ) {
    final now = DateTime.now();
    final merge =
        kind != _EditKind.other &&
        kind == _lastKind &&
        now.difference(_lastTime) < const Duration(seconds: 2) &&
        (kind == _EditKind.typing
            ? start == _lastEnd
            : end == _lastEnd || start == _lastEnd - 1);
    if (!merge) {
      _undo.add(_Snapshot(old, selection));
      if (_undo.length > undoLimit) _undo.removeAt(0);
    }
    _lastKind = kind;
    _lastEnd = kind == _EditKind.deleting ? start : end;
    _lastTime = now;
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_doc, value.selection));
    final s = _undo.removeLast();
    _doc = s.doc;
    _lastKind = _EditKind.other;
    _set(s.selection);
    _refind();
    onEdited?.call();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_doc, value.selection));
    final s = _redo.removeLast();
    _doc = s.doc;
    _lastKind = _EditKind.other;
    _set(s.selection);
    _refind();
    onEdited?.call();
  }

  void _commit(StyledText doc, TextSelection selection) {
    if (doc == _doc) {
      _set(selection);
      return;
    }
    _recordEdit(_doc, value.selection, _EditKind.other, -1, -1);
    _doc = doc;
    _set(selection);
    _refind();
    onEdited?.call();
  }

  // MARK: clipboard

  Future<void> copy({bool cut = false}) async {
    final sel = value.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final plain = _doc.text.substring(sel.start, sel.end);
    _clip = _Clip(plain, Runs.slice(_doc.runs, sel.start, sel.end));
    await Clipboard.setData(ClipboardData(text: plain));
    if (cut) _replace(sel.start, sel.end, '', const [], kind: _EditKind.other);
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    final sel = value.selection;
    if (text == null || !sel.isValid) return;
    final clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final clip = _clip;
    final runs = clip != null && clip.plain == clean && _rich
        ? clip.runs
        : Runs.of(clean.length, _typingStyle(_doc, sel.start, sel.end));
    _replace(sel.start, sel.end, clean, runs, kind: _EditKind.other);
  }

  /// Inserts [text] over the selection.
  void insertText(String text) {
    final sel = value.selection;
    final start = sel.isValid ? sel.start : _doc.text.length;
    final end = sel.isValid ? sel.end : _doc.text.length;
    _replace(
      start,
      end,
      text,
      Runs.of(text.length, _typingStyle(_doc, start, end)),
    );
  }

  void select(int start, int end) =>
      _set(TextSelection(baseOffset: start, extentOffset: end));

  // MARK: format

  /// The style the next typed text takes, or the style of the selection's first character.
  CharStyle get currentStyle {
    final sel = value.selection;
    if (!sel.isValid || !_rich) return CharStyle.plain;
    if (sel.isCollapsed) {
      if (_pending != null && _pendingAt == sel.baseOffset) return _pending!;
      return _typingStyle(_doc, sel.baseOffset, sel.baseOffset);
    }
    return Runs.at(_doc.runs, sel.start);
  }

  bool hasTrait(Trait t) {
    final sel = value.selection;
    if (!sel.isValid || !_rich) return false;
    if (sel.isCollapsed) return currentStyle.has(t);
    final runs = Runs.slice(_doc.runs, sel.start, sel.end);
    return runs.isNotEmpty && runs.every((r) => r.style.has(t));
  }

  /// Changes the style of the selection, or of the next typed text when nothing is selected.
  void restyle(CharStyle Function(CharStyle) f) {
    final sel = value.selection;
    if (!sel.isValid || !_rich) return;
    if (sel.isCollapsed) {
      _pending = f(currentStyle);
      _pendingAt = sel.baseOffset;
      notifyListeners();
      return;
    }
    _commit(
      StyledText(_doc.text, Runs.map(_doc.runs, sel.start, sel.end, f)),
      sel,
    );
  }

  void toggleTrait(Trait t) {
    final on = !hasTrait(t);
    restyle((s) => s.withTrait(t, on));
  }

  void setFont(String font) => restyle(
    (s) => font == look?.font
        ? s.copyWith(clearFont: true)
        : s.copyWith(font: font),
  );

  void setSize(double size) => restyle(
    (s) => size == look?.size
        ? s.copyWith(clearSize: true)
        : s.copyWith(size: size),
  );

  /// Null: automatic colour.
  void setColor(int? color) => restyle(
    (s) =>
        color == null ? s.copyWith(clearColor: true) : s.copyWith(color: color),
  );

  /// Format › Font › Bigger / Smaller: one point at a time, 1 to 288.
  void changeSize(int delta) {
    final base = look?.size ?? 13;
    restyle((s) {
      final next = ((s.size ?? base) + delta).clamp(1, 288).toDouble();
      return next == base
          ? s.copyWith(clearSize: true)
          : s.copyWith(size: next);
    });
  }

  /// The lines the selection touches, as offsets: the start of the first, the end of the last.
  (int, int) get _selectedLines {
    final sel = value.selection;
    final text = _doc.text;
    final a = sel.isValid ? sel.start : 0;
    final b = sel.isValid ? sel.end : 0;
    final lineStart = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
    final endAt = text.indexOf('\n', b);
    return (lineStart, endAt < 0 ? text.length : endAt);
  }

  /// [preset] on the selected paragraphs.
  void setPreset(ParaPreset preset) {
    if (!_rich) return;
    final (start, end) = _selectedLines;
    CharStyle apply(CharStyle s) => switch (preset) {
      ParaPreset.title => s.copyWith(bold: true, size: 26, clearFont: true),
      ParaPreset.heading => s.copyWith(bold: true, size: 20, clearFont: true),
      ParaPreset.subheading => s.copyWith(
        bold: true,
        size: 16,
        clearFont: true,
      ),
      ParaPreset.body => s.copyWith(
        bold: false,
        clearSize: true,
        clearFont: true,
      ),
      ParaPreset.mono => s.copyWith(bold: false, size: 12, font: monoFont),
    };
    if (start == end) {
      _pending = apply(currentStyle);
      _pendingAt = value.selection.baseOffset;
      notifyListeners();
      return;
    }
    _commit(
      StyledText(_doc.text, Runs.map(_doc.runs, start, end, apply)),
      value.selection,
    );
  }

  /// The preset the caret's paragraph matches; null when none does.
  ParaPreset? get currentPreset {
    final s = currentStyle;
    if (s.font == monoFont && s.size == 12 && !s.bold) return ParaPreset.mono;
    if (s.font != null) return null;
    if (s.bold && s.size == 26) return ParaPreset.title;
    if (s.bold && s.size == 20) return ParaPreset.heading;
    if (s.bold && s.size == 16) return ParaPreset.subheading;
    if (!s.bold && s.size == null) return ParaPreset.body;
    return null;
  }

  /// Whether the caret's line is a list item.
  bool get inList {
    final (start, end) = _selectedLines;
    return listMarker.hasMatch(_doc.text.substring(start, end));
  }

  /// Bullets on the selected lines, or off when they all have one.
  void toggleList({bool numbered = false}) {
    final (start, end) = _selectedLines;
    final lines = _doc.text.substring(start, end).split('\n');
    final all = lines.every(listMarker.hasMatch);
    final out = <String>[];
    var n = 1;
    for (final l in lines) {
      final m = listMarker.firstMatch(l);
      final rest = m == null ? l : l.substring(m.end);
      final tabs = m?.group(1) ?? '';
      out.add(all ? '$tabs$rest' : '$tabs${numbered ? '${n++}.' : '•'}\t$rest');
    }
    _rewriteLines(start, end, out.join('\n'));
  }

  /// Moves the selected lines in (one tab more) or out (one tab less).
  void indent(int delta) {
    final (start, end) = _selectedLines;
    final lines = _doc.text.substring(start, end).split('\n');
    final out = [
      for (final l in lines)
        delta > 0 ? '\t$l' : (l.startsWith('\t') ? l.substring(1) : l),
    ];
    _rewriteLines(start, end, out.join('\n'));
  }

  /// Lines [start, end) replaced by [text], keeping each line's style.
  void _rewriteLines(int start, int end, String text) {
    final old = _doc.text.substring(start, end);
    if (old == text) return;
    final style = Runs.at(
      _doc.runs,
      start < _doc.text.length ? start : start - 1,
    );
    // Keep the styles of the text after the markers: map old lines to new.
    final oldLines = old.split('\n');
    final newLines = text.split('\n');
    final runs = <Run>[];
    var at = start;
    for (var i = 0; i < newLines.length; i++) {
      final ol = i < oldLines.length ? oldLines[i] : '';
      final nl = newLines[i];
      // The common tail of the line keeps its runs; the new head takes the line's style.
      var tail = 0;
      while (tail < ol.length &&
          tail < nl.length &&
          ol[ol.length - 1 - tail] == nl[nl.length - 1 - tail]) {
        tail++;
      }
      final head = nl.length - tail;
      final lineStyle = ol.isEmpty ? style : Runs.at(_doc.runs, at);
      runs.addAll(Runs.of(head, lineStyle));
      runs.addAll(Runs.slice(_doc.runs, at + ol.length - tail, at + ol.length));
      if (i < newLines.length - 1) runs.add(Run(1, lineStyle));
      at += ol.length + 1;
    }
    final doc = StyledText(
      _doc.text.replaceRange(start, end, text),
      _rich
          ? Runs.replace(_doc.runs, start, end, runs)
          : Runs.of(
              _doc.text.length - (end - start) + text.length,
              CharStyle.plain,
            ),
    );
    _commit(
      doc,
      TextSelection(baseOffset: start, extentOffset: start + text.length),
    );
  }

  /// Format › Make Plain Text / Make Rich Text.
  void setRich(bool rich) {
    if (rich == _rich) return;
    _recordEdit(_doc, value.selection, _EditKind.other, -1, -1);
    _rich = rich;
    if (!rich) _doc = StyledText.plain(_doc.text);
    _pending = null;
    _set(value.selection);
    onEdited?.call();
  }

  // MARK: find

  String get findText => _find;
  bool get matchCase => _matchCase;
  int get matchCount => _matches.length;

  /// The match the selection is on (0-based), -1 when none.
  int get currentMatch => _current;

  /// Searches for [text]; the matches are drawn and [findNext] goes through them.
  void setFind(String text, {bool? matchCase}) {
    _find = text;
    if (matchCase != null) _matchCase = matchCase;
    _refind();
    notifyListeners();
  }

  void _refind() {
    final q = _find;
    if (q.isEmpty) {
      _matches = const [];
      _current = -1;
      return;
    }
    final hay = _matchCase ? _doc.text : _doc.text.toLowerCase();
    final needle = _matchCase ? q : q.toLowerCase();
    final out = <(int, int)>[];
    if (hay.length == _doc.text.length) {
      var at = 0;
      while (true) {
        final hit = hay.indexOf(needle, at);
        if (hit < 0) break;
        out.add((hit, hit + q.length));
        at = hit + max(1, q.length);
      }
    }
    _matches = out;
    final sel = value.selection;
    _current = out.indexWhere((m) => m.$1 == sel.start && m.$2 == sel.end);
  }

  /// Selects the next match after the selection (or the previous); false when there is none.
  bool findNext({bool backwards = false}) {
    if (_matches.isEmpty) return false;
    final sel = value.selection;
    final from = sel.isValid ? (backwards ? sel.start : sel.end) : 0;
    int index;
    if (backwards) {
      index = _matches.lastIndexWhere((m) => m.$2 <= from && m.$1 < from);
      if (index < 0) index = _matches.length - 1;
    } else {
      index = _matches.indexWhere((m) => m.$1 >= from);
      if (index < 0) index = 0;
    }
    _current = index;
    final (a, b) = _matches[index];
    _set(TextSelection(baseOffset: a, extentOffset: b));
    return true;
  }

  /// Replaces the selected match with [replacement] and goes to the next one.
  void replaceCurrent(String replacement) {
    final sel = value.selection;
    final on = _matches.any((m) => m.$1 == sel.start && m.$2 == sel.end);
    if (!on) {
      findNext();
      return;
    }
    _replace(
      sel.start,
      sel.end,
      replacement,
      Runs.of(replacement.length, Runs.at(_doc.runs, sel.start)),
      kind: _EditKind.other,
    );
    findNext();
  }

  /// Replaces every match; returns how many.
  int replaceAll(String replacement) {
    if (_matches.isEmpty) return 0;
    final count = _matches.length;
    final text = StringBuffer();
    final runs = <Run>[];
    var at = 0;
    for (final (a, b) in _matches) {
      text.write(_doc.text.substring(at, a));
      runs.addAll(Runs.slice(_doc.runs, at, a));
      text.write(replacement);
      runs.addAll(Runs.of(replacement.length, Runs.at(_doc.runs, a)));
      at = b;
    }
    text.write(_doc.text.substring(at));
    runs.addAll(Runs.slice(_doc.runs, at, _doc.text.length));
    final s = text.toString();
    _commit(
      StyledText(
        s,
        _rich ? Runs.merged(runs) : Runs.of(s.length, CharStyle.plain),
      ),
      TextSelection.collapsed(offset: min(value.selection.start, s.length)),
    );
    return count;
  }

  // MARK: position

  /// The caret's line and column, from 1.
  (int, int) get lineColumn {
    final sel = value.selection;
    final o = sel.isValid ? sel.extentOffset.clamp(0, _doc.text.length) : 0;
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < o; i++) {
      if (_doc.text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    return (line, o - lineStart + 1);
  }

  // MARK: drawing

  /// The text style of [s] with the document defaults.
  TextStyle styleOf(CharStyle s) {
    final look = this.look;
    final font = s.font ?? look?.font ?? uiFont;
    final size = (s.size ?? look?.size ?? 13) * (look?.zoom ?? 1);
    return TextStyle(
      fontFamily: font,
      package: bundledFonts.contains(font) ? 'silica_ui' : null,
      fontSize: size,
      height: font == monoFont ? 16 / 12 : 18 / 13,
      fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
      decoration: s.underline || s.strike
          ? TextDecoration.combine([
              if (s.underline) TextDecoration.underline,
              if (s.strike) TextDecoration.lineThrough,
            ])
          : TextDecoration.none,
      color: s.color == null ? look?.text : Color(s.color!),
    );
  }

  final Map<TextStyle, double> _spaceWidths = {};

  double _spaceWidth(TextStyle style) => _spaceWidths.putIfAbsent(style, () {
    final tp = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  });

  /// The width of [spans] on one line.
  double _lineWidth(List<InlineSpan> spans) {
    if (spans.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  /// Over this many characters, plain text is drawn as one span (tabs as they come).
  static const int _bigText = 200000;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final look = this.look;
    final doc = _doc;
    if (look == null || doc.text != text) {
      return TextSpan(style: style, text: text);
    }
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final big = !_rich && doc.text.length > _bigText;
    if (big && _matches.isEmpty && !composing.isValid) {
      return TextSpan(text: doc.text, style: styleOf(CharStyle.plain));
    }
    // Cut points: style runs, matches and the composing range.
    final cuts = <int>{0, doc.text.length};
    var at = 0;
    for (final r in doc.runs) {
      cuts.add(at);
      at += r.length;
    }
    for (final (a, b) in _matches) {
      cuts
        ..add(a)
        ..add(b);
    }
    if (composing.isValid) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final points = cuts.where((c) => c >= 0 && c <= doc.text.length).toList()
      ..sort();
    final children = <InlineSpan>[];
    // Where the current line starts in [children], to measure the way to a tab stop.
    var lineFrom = 0;
    var m = 0;
    var col = 0;
    final plainStyle = styleOf(CharStyle.plain);
    final charWidth = _rich ? 0.0 : _spaceWidth(plainStyle);
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a == b) continue;
      while (m < _matches.length && _matches[m].$2 <= a) {
        m++;
      }
      final inMatch = m < _matches.length && _matches[m].$1 <= a;
      var st = _rich ? styleOf(Runs.at(doc.runs, a)) : plainStyle;
      if (inMatch) {
        st = st.copyWith(
          backgroundColor: m == _current ? look.currentMatch : look.match,
          color: m == _current ? const Color(0xFF1D1E21) : null,
        );
      }
      if (composing.isValid && a >= composing.start && b <= composing.end) {
        st = st.copyWith(decoration: TextDecoration.underline);
      }
      final chunk = doc.text.substring(a, b);
      if (big || !chunk.contains('\t')) {
        children.add(TextSpan(text: chunk, style: st));
        if (chunk.contains('\n')) lineFrom = children.length;
        if (!_rich) {
          final nl = chunk.lastIndexOf('\n');
          col = nl < 0 ? col + chunk.length : chunk.length - nl - 1;
        }
        continue;
      }
      // Tabs: as wide as the way to the next stop.
      var from = 0;
      for (var j = 0; j < chunk.length; j++) {
        final c = chunk.codeUnitAt(j);
        if (c == 0x0A) {
          col = 0;
          children.add(TextSpan(text: chunk.substring(from, j + 1), style: st));
          from = j + 1;
          lineFrom = children.length;
          continue;
        }
        if (c != 0x09) {
          col++;
          continue;
        }
        if (j > from) {
          children.add(TextSpan(text: chunk.substring(from, j), style: st));
        }
        final space = _spaceWidth(st);
        final double width;
        if (_rich) {
          final stop = richTabStop * look.zoom;
          final x = _lineWidth(children.sublist(lineFrom));
          width = stop - x % stop;
        } else {
          final stops = plainTabStop - col % plainTabStop;
          width = stops * charWidth;
          col += stops;
        }
        children.add(
          TextSpan(
            text: '\t',
            style: st.copyWith(letterSpacing: max(0.0, width - space)),
          ),
        );
        from = j + 1;
      }
      if (from < chunk.length) {
        children.add(TextSpan(text: chunk.substring(from), style: st));
      }
    }
    return TextSpan(style: style ?? plainStyle, children: children);
  }
}
