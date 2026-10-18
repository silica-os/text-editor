// The styles of rich text: one [CharStyle] per character, kept as runs. A plain text document
// has a single run of the default style.

import 'package:flutter/foundation.dart';

/// The style of one character. Null [font], [size] and [color] follow the document defaults
/// (and, for the colour, the appearance: automatic text is light on dark).
@immutable
class CharStyle {
  const CharStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.font,
    this.size,
    this.color,
  });

  static const CharStyle plain = CharStyle();

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// The font family; null: the default font.
  final String? font;

  /// The size in points; null: the default size.
  final double? size;

  /// ARGB; null: automatic.
  final int? color;

  CharStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    String? font,
    double? size,
    int? color,
    bool clearFont = false,
    bool clearSize = false,
    bool clearColor = false,
  }) => CharStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    font: clearFont ? null : (font ?? this.font),
    size: clearSize ? null : (size ?? this.size),
    color: clearColor ? null : (color ?? this.color),
  );

  @override
  bool operator ==(Object other) =>
      other is CharStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.font == font &&
      other.size == size &&
      other.color == color;

  @override
  int get hashCode =>
      Object.hash(bold, italic, underline, strike, font, size, color);

  @override
  String toString() =>
      'CharStyle(${[if (bold) 'b', if (italic) 'i', if (underline) 'u', if (strike) 's', ?font, ?size, if (color != null) color!.toRadixString(16)].join(',')})';
}

/// The traits a format command toggles.
enum Trait { bold, italic, underline, strike }

extension CharTraits on CharStyle {
  bool has(Trait t) => switch (t) {
    Trait.bold => bold,
    Trait.italic => italic,
    Trait.underline => underline,
    Trait.strike => strike,
  };

  CharStyle withTrait(Trait t, bool on) => switch (t) {
    Trait.bold => copyWith(bold: on),
    Trait.italic => copyWith(italic: on),
    Trait.underline => copyWith(underline: on),
    Trait.strike => copyWith(strike: on),
  };
}

/// [length] characters in [style].
@immutable
class Run {
  const Run(this.length, this.style);
  final int length;
  final CharStyle style;

  @override
  bool operator ==(Object other) =>
      other is Run && other.length == length && other.style == style;

  @override
  int get hashCode => Object.hash(length, style);

  @override
  String toString() => 'Run($length, $style)';
}

/// Operations on run lists; they return new lists.
abstract final class Runs {
  static List<Run> merged(Iterable<Run> runs) {
    final out = <Run>[];
    for (final r in runs) {
      if (r.length <= 0) continue;
      if (out.isNotEmpty && out.last.style == r.style) {
        out[out.length - 1] = Run(out.last.length + r.length, r.style);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  static int length(List<Run> runs) {
    var n = 0;
    for (final r in runs) {
      n += r.length;
    }
    return n;
  }

  static List<Run> slice(List<Run> runs, int start, int end) {
    final out = <Run>[];
    var at = 0;
    for (final r in runs) {
      final a = at;
      final b = at + r.length;
      at = b;
      if (b <= start) continue;
      if (a >= end) break;
      final from = a < start ? start : a;
      final to = b > end ? end : b;
      if (to > from) out.add(Run(to - from, r.style));
    }
    return out;
  }

  static List<Run> replace(
    List<Run> runs,
    int start,
    int end,
    List<Run> inserted,
  ) => merged([
    ...slice(runs, 0, start),
    ...inserted,
    ...slice(runs, end, length(runs)),
  ]);

  static CharStyle at(List<Run> runs, int index) {
    if (index < 0) return CharStyle.plain;
    var at = 0;
    for (final r in runs) {
      if (index < at + r.length) return r.style;
      at += r.length;
    }
    return runs.isEmpty ? CharStyle.plain : runs.last.style;
  }

  static List<Run> map(
    List<Run> runs,
    int start,
    int end,
    CharStyle Function(CharStyle) f,
  ) => merged([
    ...slice(runs, 0, start),
    for (final r in slice(runs, start, end)) Run(r.length, f(r.style)),
    ...slice(runs, end, length(runs)),
  ]);

  /// One run of [style] over [length] characters (none when empty).
  static List<Run> of(int length, CharStyle style) =>
      length <= 0 ? const [] : [Run(length, style)];
}

/// Rich text: characters and their runs.
@immutable
class StyledText {
  StyledText(this.text, List<Run> runs) : runs = List.unmodifiable(runs) {
    assert(Runs.length(runs) == text.length, 'runs do not cover the text');
  }

  factory StyledText.plain(String text, [CharStyle style = CharStyle.plain]) =>
      StyledText(text, Runs.of(text.length, style));

  final String text;
  final List<Run> runs;

  /// Whether every character has the default style.
  bool get isPlain => runs.every((r) => r.style == CharStyle.plain);

  @override
  bool operator ==(Object other) =>
      other is StyledText && other.text == text && listEquals(other.runs, runs);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(runs));

  @override
  String toString() => 'StyledText($text, $runs)';
}
