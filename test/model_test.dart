// RTF, plain text encodings and documents on disk.
import 'package:flutter/services.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:text_editor/src/model/document.dart';
import 'package:text_editor/src/model/rtf.dart';
import 'package:text_editor/src/model/styled.dart';
import 'package:text_editor/src/model/text_codec.dart';

StyledText styled(List<(String, CharStyle)> chunks) => StyledText(
  chunks.map((c) => c.$1).join(),
  Runs.merged([for (final (t, s) in chunks) Run(t.length, s)]),
);

void main() {
  group('rtf', () {
    test('styles, fonts, colours, tabs and Unicode survive a round trip', () {
      final doc = styled([
        ('Lemon cake\n', const CharStyle(bold: true, size: 26)),
        ('A ', CharStyle.plain),
        ('soft', const CharStyle(italic: true, underline: true)),
        (' cake {for} \\ Sunday\tcafé — 🍋\n', CharStyle.plain),
        ('red', const CharStyle(color: 0xFFCC2200, strike: true)),
        (' mono', const CharStyle(font: 'JetBrains Mono', size: 12)),
      ]);
      final rtf = writeRtf(doc, defaultFont: 'Inter', defaultSize: 13);
      expect(rtf, startsWith(r'{\rtf1'));
      expect(rtf, contains(r'\red204\green34\blue0'));
      expect(readRtf(rtf, defaultFont: 'Inter', defaultSize: 13), doc);
    });

    test(
      'files from other programs: tables, lists, code pages, skipped groups',
      () {
        const source =
            r'{\rtf1\ansi\ansicpg1252\cocoartf2822'
            '\n'
            r'{\fonttbl\f0\fswiss\fcharset0 Helvetica;\f1\fnil Menlo;}'
            '\n'
            r'{\colortbl;\red255\green255\blue255;\red200\green0\blue0;}'
            r'{\*\expandedcolortbl;;\csgray\c0;}'
            r'{\info{\title Secret}{\author Someone}}'
            r'\paperw11900\paperh16840\margl1440\margr1440'
            '\n'
            r'\pard\tx566\pardirnatural\partightenfactor0'
            '\n'
            r"\f0\fs24 \cf0 Caf\'e9 \b bold\b0  and \i it\i0 \ulnone  "
            r'{\cf2 red}\par'
            '\n'
            r'{\listtext	\uc0\u8226 	}Three eggs\par'
            '\n'
            r'\uc1\u8364? euro \~nbsp\line next\par}';
        final doc = readRtf(source, defaultFont: 'Inter', defaultSize: 13);
        expect(
          doc.text,
          'Café bold and it red\n\t•\tThree eggs\n€ euro \u00A0nbsp\nnext',
        );
        final bold = doc.text.indexOf('bold');
        expect(Runs.at(doc.runs, bold).bold, isTrue);
        expect(Runs.at(doc.runs, bold).font, 'Helvetica');
        expect(Runs.at(doc.runs, bold).size, 12);
        expect(Runs.at(doc.runs, doc.text.indexOf('red')).color, 0xFFC80000);
        expect(Runs.at(doc.runs, doc.text.indexOf('Café')).color, isNull);
      },
    );

    test('not RTF', () {
      expect(
        () => readRtf('hello', defaultFont: 'Inter', defaultSize: 13),
        throwsA(isA<RtfFormatException>()),
      );
      expect(looksLikeRtf(utf8.encode(r'{\rtf1}')), isTrue);
    });
  });

  group('encodings', () {
    test('UTF-8 with and without a mark, UTF-16 both ways, Latin-1', () {
      final plain = decodeText(Uint8List.fromList(utf8.encode('perché\r\nsì')));
      expect(plain.text, 'perché\nsì');
      expect(plain.encoding, TextEncoding.utf8);
      expect(plain.lineEnding, LineEnding.crlf);
      expect(
        encodeText(plain.text, plain.encoding, lineEnding: plain.lineEnding),
        utf8.encode('perché\r\nsì'),
      );
      final bom = decodeText(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x61]));
      expect((bom.text, bom.bom), ('a', true));
      for (final e in [TextEncoding.utf16le, TextEncoding.utf16be]) {
        final bytes = encodeText('Città 🍋', e, bom: true);
        final back = decodeText(bytes);
        expect((back.text, back.encoding, back.bom), ('Città 🍋', e, true));
      }
      final latin = decodeText(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9]));
      expect((latin.text, latin.encoding), ('café', TextEncoding.latin1));
      expect(
        decodeText(
          Uint8List.fromList(utf8.encode('x')),
          forced: TextEncoding.latin1,
        ).encoding,
        TextEncoding.latin1,
      );
    });

    test('binary files are not text; Latin-1 refuses what it lacks', () {
      expect(
        () => decodeText(Uint8List.fromList([0x50, 0x4B, 0x00, 0x03])),
        throwsA(isA<NotTextException>()),
      );
      expect(
        () => encodeText('€', TextEncoding.latin1),
        throwsA(isA<UnencodableException>()),
      );
    });
  });

  group('documents', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('text_editor'));
    tearDown(() => dir.deleteSync(recursive: true));
    const defaults = RichDefaults();

    test('a plain file keeps its encoding and line endings', () {
      final file = File('${dir.path}/notes.txt')
        ..writeAsBytesSync(
          encodeText(
            'a\nb',
            TextEncoding.utf16le,
            bom: true,
            lineEnding: LineEnding.crlf,
          ),
        );
      final doc = TextDocument.open(file.path, defaults: defaults);
      expect(doc.format, DocFormat.plain);
      expect(doc.controller.text, 'a\nb');
      doc.controller.value = doc.controller.value.copyWith(
        text: 'a\nbc',
        selection: const TextSelection.collapsed(offset: 4),
      );
      expect(doc.edited, isTrue);
      expect(doc.needsSaveAs, isFalse);
      doc.save();
      expect(doc.edited, isFalse);
      expect(
        file.readAsBytesSync(),
        encodeText(
          'a\nbc',
          TextEncoding.utf16le,
          bom: true,
          lineEnding: LineEnding.crlf,
        ),
      );
      doc.revertToOpened();
      expect(doc.controller.text, 'a\nb');
    });

    test('rich text is written as RTF; a rich .txt needs Save As', () {
      final doc = TextDocument.untitled(
        format: DocFormat.rich,
        defaults: defaults,
      );
      expect(doc.isBlank, isTrue);
      doc.controller.value = const TextEditingValue(
        text: 'Hi',
        selection: TextSelection.collapsed(offset: 2),
      );
      doc.controller.select(0, 2);
      doc.controller.toggleTrait(Trait.bold);
      final path = '${dir.path}/hi.rtf';
      doc.save(to: path);
      final again = TextDocument.open(path, defaults: defaults);
      expect(again.format, DocFormat.rich);
      expect(Runs.at(again.controller.doc.runs, 0).bold, isTrue);
      final txt = File('${dir.path}/a.txt')..writeAsStringSync('x');
      final plain = TextDocument.open(txt.path, defaults: defaults);
      plain.controller.setRich(true);
      expect(plain.needsSaveAs, isTrue);
    });

    test('rename, missing files, folders and binary files', () {
      final file = File('${dir.path}/one.txt')..writeAsStringSync('1');
      final doc = TextDocument.open(file.path, defaults: defaults);
      doc.rename('two.txt');
      expect(doc.path, '${dir.path}/two.txt');
      expect(File('${dir.path}/two.txt').existsSync(), isTrue);
      OpenProblem problem(String p) {
        try {
          TextDocument.open(p, defaults: defaults);
        } on OpenFailure catch (e) {
          return e.problem;
        }
        throw StateError('opened');
      }

      expect(problem('${dir.path}/none.txt'), OpenProblem.missing);
      expect(problem(dir.path), OpenProblem.directory);
      File('${dir.path}/bin').writeAsBytesSync([0, 1, 2]);
      expect(problem('${dir.path}/bin'), OpenProblem.notText);
    });

    test('a file changed by another program is noticed', () async {
      final file = File('${dir.path}/c.txt')..writeAsStringSync('1');
      final doc = TextDocument.open(file.path, defaults: defaults);
      expect(doc.changedOnDisk, isFalse);
      file.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      expect(doc.changedOnDisk, isTrue);
    });

    test('counts', () {
      final doc = TextDocument.untitled(
        format: DocFormat.plain,
        defaults: defaults,
      );
      doc.controller.value = const TextEditingValue(
        text: "It's a cake.\n\nTwo words",
        selection: TextSelection.collapsed(offset: 0),
      );
      final c = doc.counts;
      expect((c.words, c.paragraphs), (5, 2));
      expect(c.characters, 21);
    });
  });
}
