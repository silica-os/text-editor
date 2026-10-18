// Plain text files: which encoding they are in, their line endings, and back to bytes.
//
// Reading: a byte order mark decides (UTF-8, UTF-16 little or big endian); without one the file
// is UTF-8 if it is valid UTF-8, else Western (ISO Latin 1). A file with NUL bytes and no
// UTF-16 mark is not text. Writing keeps the encoding, the mark and the line endings the
// file had.

import 'dart:convert';
import 'dart:typed_data';

/// The encodings Text Editor reads and writes.
enum TextEncoding {
  utf8('UTF-8'),
  utf16le('UTF-16LE'),
  utf16be('UTF-16BE'),
  latin1('ISO-8859-1');

  const TextEncoding(this.iana);

  /// The IANA name.
  final String iana;
}

/// Line endings.
enum LineEnding {
  lf('\n'),
  crlf('\r\n'),
  cr('\r');

  const LineEnding(this.chars);
  final String chars;
}

/// The file is not text (binary data).
class NotTextException implements Exception {
  const NotTextException();
}

/// The text cannot be written in the encoding (a character it does not have).
class UnencodableException implements Exception {
  const UnencodableException(this.character);

  /// The first character that does not fit.
  final String character;
}

/// A decoded file: its text with `\n` line ends, and how it was stored.
class DecodedText {
  const DecodedText(this.text, this.encoding, this.bom, this.lineEnding);
  final String text;
  final TextEncoding encoding;
  final bool bom;
  final LineEnding lineEnding;
}

/// [bytes] as text; [forced] reads them in that encoding instead of detecting it.
DecodedText decodeText(Uint8List bytes, {TextEncoding? forced}) {
  var encoding = forced;
  var bom = false;
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF &&
      (forced == null || forced == TextEncoding.utf8)) {
    encoding = TextEncoding.utf8;
    bom = true;
    start = 3;
  } else if (bytes.length >= 2 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xFE &&
      (forced == null || forced == TextEncoding.utf16le)) {
    encoding = TextEncoding.utf16le;
    bom = true;
    start = 2;
  } else if (bytes.length >= 2 &&
      bytes[0] == 0xFE &&
      bytes[1] == 0xFF &&
      (forced == null || forced == TextEncoding.utf16be)) {
    encoding = TextEncoding.utf16be;
    bom = true;
    start = 2;
  }
  final body = Uint8List.sublistView(bytes, start);
  if (encoding == null) {
    if (body.contains(0)) throw const NotTextException();
    try {
      final text = utf8.decode(body);
      return _finish(text, TextEncoding.utf8, false);
    } on FormatException {
      encoding = TextEncoding.latin1;
    }
  }
  final String text;
  switch (encoding) {
    case TextEncoding.utf8:
      text = utf8.decode(body, allowMalformed: true);
    case TextEncoding.latin1:
      text = latin1.decode(body);
    case TextEncoding.utf16le:
    case TextEncoding.utf16be:
      final units = Uint16List(body.length ~/ 2);
      final le = encoding == TextEncoding.utf16le;
      for (var i = 0; i < units.length; i++) {
        final a = body[2 * i];
        final b = body[2 * i + 1];
        units[i] = le ? a | (b << 8) : (a << 8) | b;
      }
      text = String.fromCharCodes(units);
  }
  return _finish(text, encoding, bom);
}

DecodedText _finish(String raw, TextEncoding encoding, bool bom) {
  final crlf = raw.contains('\r\n');
  final cr = !crlf && raw.contains('\r');
  final ending = crlf
      ? LineEnding.crlf
      : cr
      ? LineEnding.cr
      : LineEnding.lf;
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return DecodedText(text, encoding, bom, ending);
}

/// [text] (with `\n` line ends) as bytes. Throws [UnencodableException].
Uint8List encodeText(
  String text,
  TextEncoding encoding, {
  bool bom = false,
  LineEnding lineEnding = LineEnding.lf,
}) {
  final body = lineEnding == LineEnding.lf
      ? text
      : text.replaceAll('\n', lineEnding.chars);
  final out = BytesBuilder(copy: false);
  switch (encoding) {
    case TextEncoding.utf8:
      if (bom) out.add(const [0xEF, 0xBB, 0xBF]);
      out.add(utf8.encode(body));
    case TextEncoding.latin1:
      for (final r in body.runes) {
        if (r > 0xFF) throw UnencodableException(String.fromCharCode(r));
      }
      out.add(latin1.encode(body));
    case TextEncoding.utf16le:
    case TextEncoding.utf16be:
      final le = encoding == TextEncoding.utf16le;
      final units = body.codeUnits;
      final bytes = Uint8List(units.length * 2 + (bom ? 2 : 0));
      var at = 0;
      if (bom) {
        bytes[0] = le ? 0xFF : 0xFE;
        bytes[1] = le ? 0xFE : 0xFF;
        at = 2;
      }
      for (final u in units) {
        bytes[at++] = le ? u & 0xFF : u >> 8;
        bytes[at++] = le ? u >> 8 : u & 0xFF;
      }
      out.add(bytes);
  }
  return out.takeBytes();
}
