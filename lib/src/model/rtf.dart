// Rich Text Format, read and written from the specification (RTF 1.9.1): the character styles
// Text Editor keeps (bold, italic, underline, strikethrough, font, size, colour), paragraphs,
// tabs and Unicode. Destinations it does not use (pictures, style sheets, document info,
// headers) are skipped; the text of list markers (`\listtext`) and field results is kept.

import 'dart:convert';

import 'styled.dart';

/// The default size of RTF text when a file gives none: 12 pt (`\fs24`).
const double rtfDefaultSize = 12;

// MARK: writing

/// [doc] as RTF. Characters with a null font or size are written with [defaultFont] and
/// [defaultSize] so that other programs show them the same.
String writeRtf(
  StyledText doc, {
  required String defaultFont,
  required double defaultSize,
}) {
  final fonts = <String>[defaultFont];
  final colors = <int>[];
  for (final r in doc.runs) {
    final f = r.style.font;
    if (f != null && !fonts.contains(f)) fonts.add(f);
    final c = r.style.color;
    if (c != null && !colors.contains(c & 0xFFFFFF)) colors.add(c & 0xFFFFFF);
  }
  final b = StringBuffer()
    ..write(r'{\rtf1\ansi\ansicpg1252\deff0\uc1')
    ..write(r'{\fonttbl');
  for (var i = 0; i < fonts.length; i++) {
    b.write('{\\f$i\\fnil ${_escapeText(fonts[i])};}');
  }
  b.write('}');
  if (colors.isNotEmpty) {
    b.write(r'{\colortbl;');
    for (final c in colors) {
      b.write(
        '\\red${(c >> 16) & 0xFF}\\green${(c >> 8) & 0xFF}\\blue${c & 0xFF};',
      );
    }
    b.write('}');
  }
  b.write('\n\\pard\\f0\\fs${(defaultSize * 2).round()}\\cf0 ');

  var cur = CharStyle(font: defaultFont, size: defaultSize);
  var at = 0;
  for (final run in doc.runs) {
    final s = run.style;
    final font = s.font ?? defaultFont;
    final size = s.size ?? defaultSize;
    final words = StringBuffer();
    if (s.bold != cur.bold) words.write(s.bold ? r'\b' : r'\b0');
    if (s.italic != cur.italic) words.write(s.italic ? r'\i' : r'\i0');
    if (s.underline != cur.underline) {
      words.write(s.underline ? r'\ul' : r'\ulnone');
    }
    if (s.strike != cur.strike)
      words.write(s.strike ? r'\strike' : r'\strike0');
    if (font != cur.font) words.write('\\f${fonts.indexOf(font)}');
    if (size != cur.size) words.write('\\fs${(size * 2).round()}');
    if (s.color != cur.color) {
      final c = s.color;
      words.write('\\cf${c == null ? 0 : colors.indexOf(c & 0xFFFFFF) + 1}');
    }
    if (words.isNotEmpty) b.write('$words ');
    cur = CharStyle(
      bold: s.bold,
      italic: s.italic,
      underline: s.underline,
      strike: s.strike,
      font: font,
      size: size,
      color: s.color,
    );
    b.write(_escapeText(doc.text.substring(at, at + run.length)));
    at += run.length;
  }
  b.write('}\n');
  return b.toString();
}

String _escapeText(String s) {
  final b = StringBuffer();
  for (final rune in s.runes) {
    switch (rune) {
      case 0x5C:
        b.write(r'\\');
      case 0x7B:
        b.write(r'\{');
      case 0x7D:
        b.write(r'\}');
      case 0x0A:
        b.write('\\par\n');
      case 0x09:
        b.write(r'\tab ');
      case 0x0D:
        break;
      default:
        if (rune < 0x80) {
          b.writeCharCode(rune);
        } else if (rune <= 0xFFFF) {
          b.write('\\u${rune > 0x7FFF ? rune - 0x10000 : rune}?');
        } else {
          // Outside the BMP: a surrogate pair, each as a signed 16-bit \u.
          final v = rune - 0x10000;
          final hi = 0xD800 + (v >> 10);
          final lo = 0xDC00 + (v & 0x3FF);
          b.write('\\u${hi - 0x10000}?\\u${lo - 0x10000}?');
        }
    }
  }
  return b.toString();
}

// MARK: reading

/// The file is not RTF.
class RtfFormatException implements Exception {
  const RtfFormatException(this.message);
  final String message;
  @override
  String toString() => 'RtfFormatException($message)';
}

/// Whether [bytes] start like an RTF file.
bool looksLikeRtf(List<int> bytes) {
  const magic = r'{\rtf';
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic.codeUnitAt(i)) return false;
  }
  return true;
}

class _State {
  _State();
  _State.from(_State o)
    : bold = o.bold,
      italic = o.italic,
      underline = o.underline,
      strike = o.strike,
      font = o.font,
      size = o.size,
      color = o.color,
      uc = o.uc,
      skip = o.skip,
      dest = o.dest;

  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  int? font;
  double size = rtfDefaultSize;
  int color = 0;

  /// How many characters stand for each `\u` in readers without Unicode.
  int uc = 1;

  /// Inside a destination whose text is dropped.
  bool skip = false;

  /// The destination being read: '' the document, 'fonttbl', 'colortbl', 'font'.
  String dest = '';
}

/// Destinations whose text is not part of the document.
const Set<String> _skipped = {
  'author',
  'buptim',
  'colorschememapping',
  'comment',
  'company',
  'creatim',
  'datastore',
  'datafield',
  'doccomm',
  'docvar',
  'expandedcolortbl',
  'falt',
  'fldinst',
  'footer',
  'footerf',
  'footerl',
  'footerr',
  'footnote',
  'ftncn',
  'ftnsep',
  'ftnsepc',
  'generator',
  'header',
  'headerf',
  'headerl',
  'headerr',
  'info',
  'keywords',
  'latentstyles',
  'listoverridetable',
  'listtable',
  'manager',
  'nonshppict',
  'object',
  'operator',
  'panose',
  'pict',
  'printim',
  'revtbl',
  'revtim',
  'rsidtbl',
  'stylesheet',
  'subject',
  'template',
  'themedata',
  'title',
  'xmlnstbl',
  'shppict',
  'bkmkstart',
  'bkmkend',
  'pgdsctbl',
  'protusertbl',
  'fchars',
  'lchars',
  'xe',
  'tc',
  'pn',
  'pnseclvl',
  'listpicture',
  'background',
  'userprops',
};

/// The text and styles of RTF [source]. [defaultFont] and [defaultSize] replace the file's
/// own when they are the same (so the default style stays the default).
StyledText readRtf(
  String source, {
  required String defaultFont,
  required double defaultSize,
}) {
  if (!source.startsWith(r'{\rtf')) {
    throw const RtfFormatException('not RTF');
  }
  final fonts = <int, String>{};
  final colors = <int?>[];
  var colorR = 0, colorG = 0, colorB = 0;
  var colorSet = false;
  final fontName = StringBuffer();
  int? fontIndex;
  var deff = 0;
  var codePage = 1252;

  final text = StringBuffer();
  final styles = <Run>[];
  var state = _State();
  final stack = <_State>[];
  var ucSkip = 0;
  final pendingBytes = <int>[];

  CharStyle styleOf(_State s) {
    final name = fonts[s.font ?? deff];
    final color = s.color > 0 && s.color < colors.length
        ? colors[s.color]
        : null;
    return CharStyle(
      bold: s.bold,
      italic: s.italic,
      underline: s.underline,
      strike: s.strike,
      font: name == null || name == defaultFont ? null : name,
      size: s.size == defaultSize ? null : s.size,
      color: color,
    );
  }

  void endFont() {
    if (fontIndex != null) {
      var name = fontName.toString().trim();
      if (name.endsWith(';')) name = name.substring(0, name.length - 1).trim();
      if (name.isNotEmpty) fonts[fontIndex!] = name;
    }
    fontName.clear();
    fontIndex = null;
  }

  void emit(String chars) {
    if (chars.isEmpty) return;
    if (state.skip) return;
    switch (state.dest) {
      case 'fonttbl':
      case 'font':
        // Fonts end at their semicolon (several may share one group).
        for (final c in chars.split('')) {
          if (c == ';') {
            endFont();
          } else {
            fontName.write(c);
          }
        }
        return;
      case 'colortbl':
        for (final c in chars.split('')) {
          if (c == ';') {
            colors.add(
              colorSet
                  ? 0xFF000000 | (colorR << 16) | (colorG << 8) | colorB
                  : null,
            );
            colorR = colorG = colorB = 0;
            colorSet = false;
          }
        }
        return;
    }
    text.write(chars);
    final style = styleOf(state);
    if (styles.isNotEmpty && styles.last.style == style) {
      styles[styles.length - 1] = Run(styles.last.length + chars.length, style);
    } else {
      styles.add(Run(chars.length, style));
    }
  }

  void flushBytes() {
    if (pendingBytes.isEmpty) return;
    final decoded = codePage == 65001
        ? utf8.decode(pendingBytes, allowMalformed: true)
        : _decodeCodePage(pendingBytes, codePage);
    pendingBytes.clear();
    emit(decoded);
  }

  var i = 0;
  final n = source.length;
  // A destination's first control word decides what the group holds.
  var groupStart = false;
  while (i < n) {
    final c = source[i];
    if (c == '{') {
      flushBytes();
      stack.add(_State.from(state));
      if (state.dest == 'fonttbl') state.dest = 'font';
      groupStart = true;
      i++;
      continue;
    }
    if (c == '}') {
      flushBytes();
      if (state.dest == 'font') endFont();
      if (stack.isEmpty) break;
      state = stack.removeLast();
      groupStart = false;
      i++;
      continue;
    }
    if (c == '\\') {
      if (i + 1 >= n) break;
      final next = source[i + 1];
      // Control symbols.
      if (!_isLetter(next)) {
        i += 2;
        switch (next) {
          case '\\':
          case '{':
          case '}':
            flushBytes();
            if (ucSkip > 0) {
              ucSkip--;
            } else {
              emit(next);
            }
          case "'":
            final hex = i + 2 <= n ? source.substring(i, i + 2) : '';
            i += 2;
            final v = int.tryParse(hex, radix: 16);
            if (v == null) break;
            if (ucSkip > 0) {
              ucSkip--;
            } else {
              pendingBytes.add(v);
            }
          case '~':
            flushBytes();
            emit('\u00A0');
          case '_':
            flushBytes();
            emit('\u2011');
          case '-':
            break;
          case '*':
            state.skip = true;
          case '\n':
          case '\r':
            flushBytes();
            emit('\n');
        }
        groupStart = false;
        continue;
      }
      // A control word: letters, an optional signed number, an optional space.
      var j = i + 1;
      while (j < n && _isLetter(source[j])) {
        j++;
      }
      final word = source.substring(i + 1, j);
      var k = j;
      if (k < n && (source[k] == '-' || _isDigit(source[k]))) {
        k++;
        while (k < n && _isDigit(source[k])) {
          k++;
        }
      }
      final param = k > j ? int.tryParse(source.substring(j, k)) : null;
      if (k < n && source[k] == ' ') k++;
      i = k;
      final first = groupStart;
      groupStart = false;
      if (word != 'u' && word != 'uc') flushBytes();
      if (ucSkip > 0 && word != 'u') {
        // A control word counts as one replacement character.
        ucSkip--;
        continue;
      }
      if (first && _skipped.contains(word)) {
        state.skip = true;
        continue;
      }
      switch (word) {
        case 'ansicpg':
          codePage = param ?? codePage;
        case 'mac':
          codePage = 10000;
        case 'deff':
          deff = param ?? 0;
        case 'fonttbl':
          state.dest = 'fonttbl';
        case 'colortbl':
          state.dest = 'colortbl';
        case 'f':
          if (state.dest == 'font' || state.dest == 'fonttbl') {
            fontIndex = param;
            if (state.dest == 'fonttbl') state.dest = 'font';
          } else {
            state.font = param;
          }
        case 'red':
          colorR = (param ?? 0).clamp(0, 255);
          colorSet = true;
        case 'green':
          colorG = (param ?? 0).clamp(0, 255);
          colorSet = true;
        case 'blue':
          colorB = (param ?? 0).clamp(0, 255);
          colorSet = true;
        case 'b':
          state.bold = param != 0;
        case 'i':
          state.italic = param != 0;
        case 'ul':
          state.underline = param != 0;
        case 'ulnone':
          state.underline = false;
        case 'strike':
          state.strike = param != 0;
        case 'fs':
          final half = param ?? 24;
          state.size = half <= 0 ? rtfDefaultSize : half / 2;
        case 'cf':
          state.color = param ?? 0;
        case 'plain':
          state
            ..bold = false
            ..italic = false
            ..underline = false
            ..strike = false
            ..font = null
            ..size = rtfDefaultSize
            ..color = 0;
        case 'uc':
          state.uc = param ?? 1;
        case 'u':
          flushBytes();
          var v = param ?? 0;
          if (v < 0) v += 0x10000;
          emit(String.fromCharCode(v));
          ucSkip = state.uc;
        case 'par':
        case 'line':
        case 'sect':
        case 'page':
          emit('\n');
        case 'tab':
          emit('\t');
        case 'emdash':
          emit('—');
        case 'endash':
          emit('–');
        case 'bullet':
          emit('•');
        case 'lquote':
          emit('‘');
        case 'rquote':
          emit('’');
        case 'ldblquote':
          emit('“');
        case 'rdblquote':
          emit('”');
        case 'emspace':
        case 'enspace':
        case 'qmspace':
          emit(' ');
        case 'pard':
        case 'sectd':
          break;
      }
      continue;
    }
    if (c == '\r' || c == '\n') {
      i++;
      continue;
    }
    // Plain text: every character counts against a pending \u replacement.
    if (ucSkip > 0) {
      ucSkip--;
      i++;
      continue;
    }
    flushBytes();
    var j = i;
    while (j < n &&
        source[j] != '\\' &&
        source[j] != '{' &&
        source[j] != '}' &&
        source[j] != '\r' &&
        source[j] != '\n') {
      j++;
    }
    emit(source.substring(i, j));
    groupStart = false;
    i = j;
  }
  flushBytes();
  var out = text.toString();
  var runs = styles;
  // The paragraph mark that ends the last paragraph is not a line of its own.
  if (out.endsWith('\n')) {
    out = out.substring(0, out.length - 1);
    runs = Runs.slice(runs, 0, out.length);
  }
  return StyledText(out, Runs.merged(runs));
}

bool _isLetter(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

/// Windows-1252 and Mac Roman bytes; other code pages read as Latin-1.
String _decodeCodePage(List<int> bytes, int codePage) {
  final b = StringBuffer();
  for (final v in bytes) {
    if (codePage == 1252 && v >= 0x80 && v < 0xA0) {
      b.writeCharCode(_cp1252[v - 0x80]);
    } else if (codePage == 10000 && v >= 0x80) {
      b.writeCharCode(_macRoman[v - 0x80]);
    } else {
      b.writeCharCode(v);
    }
  }
  return b.toString();
}

const List<int> _cp1252 = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];

const List<int> _macRoman = [
  0xC4, 0xC5, 0xC7, 0xC9, 0xD1, 0xD6, 0xDC, 0xE1, 0xE0, 0xE2, 0xE4, 0xE3, //
  0xE5, 0xE7, 0xE9, 0xE8, 0xEA, 0xEB, 0xED, 0xEC, 0xEE, 0xEF, 0xF1, 0xF3,
  0xF2, 0xF4, 0xF6, 0xF5, 0xFA, 0xF9, 0xFB, 0xFC, 0x2020, 0xB0, 0xA2, 0xA3,
  0xA7, 0x2022, 0xB6, 0xDF, 0xAE, 0xA9, 0x2122, 0xB4, 0xA8, 0x2260, 0xC6,
  0xD8, 0x221E, 0xB1, 0x2264, 0x2265, 0xA5, 0xB5, 0x2202, 0x2211, 0x220F,
  0x3C0, 0x222B, 0xAA, 0xBA, 0x3A9, 0xE6, 0xF8, 0xBF, 0xA1, 0xAC, 0x221A,
  0x192, 0x2248, 0x2206, 0xAB, 0xBB, 0x2026, 0xA0, 0xC0, 0xC3, 0xD5, 0x152,
  0x153, 0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0xF7, 0x25CA, 0xFF,
  0x178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02, 0x2021, 0xB7,
  0x201A, 0x201E, 0x2030, 0xC2, 0xCA, 0xC1, 0xCB, 0xC8, 0xCD, 0xCE, 0xCF,
  0xCC, 0xD3, 0xD4, 0xF8FF, 0xD2, 0xDA, 0xDB, 0xD9, 0x131, 0x2C6, 0x2DC,
  0xAF, 0x2D8, 0x2D9, 0x2DA, 0xB8, 0x2DD, 0x2DB, 0x2C7,
];
