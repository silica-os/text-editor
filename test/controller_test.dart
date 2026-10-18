// The document controller: styles through typing, format commands, lists, find and replace,
// undo, and the rich clipboard.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:text_editor/src/editor/doc_controller.dart';
import 'package:text_editor/src/model/styled.dart';

void type(DocController c, String s) {
  final v = c.value;
  final sel = v.selection;
  c.value = TextEditingValue(
    text: v.text.replaceRange(sel.start, sel.end, s),
    selection: TextSelection.collapsed(offset: sel.start + s.length),
  );
}

void caret(DocController c, int o) =>
    c.selection = TextSelection.collapsed(offset: o);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('typed text takes the style before it; bold for the next text', () {
    final c = DocController();
    type(c, 'Hello');
    c.select(0, 5);
    c.toggleTrait(Trait.bold);
    caret(c, 5);
    type(c, '!');
    expect(Runs.at(c.doc.runs, 5).bold, isTrue);
    c.toggleTrait(Trait.bold);
    type(c, ' x');
    expect(Runs.at(c.doc.runs, 7).bold, isFalse);
    c.select(0, 7);
    expect(c.hasTrait(Trait.bold), isFalse);
    c.select(0, 5);
    expect(c.hasTrait(Trait.bold), isTrue);
  });

  test('font, size, colour and presets', () {
    final c = DocController()
      ..look = const DocLook(
        font: 'Inter',
        size: 13,
        text: Color(0xFF000000),
        match: Color(0xFF00FF00),
        currentMatch: Color(0xFFFFFF00),
      );
    type(c, 'Title\nbody');
    c.select(0, 5);
    c.setFont('JetBrains Mono');
    c.setSize(20);
    c.setColor(0xFFFF0000);
    final s = Runs.at(c.doc.runs, 0);
    expect((s.font, s.size, s.color), ('JetBrains Mono', 20.0, 0xFFFF0000));
    c.setFont('Inter');
    expect(Runs.at(c.doc.runs, 0).font, isNull);
    caret(c, 2);
    c.setPreset(ParaPreset.title);
    // The caret's whole paragraph takes it.
    expect(c.currentPreset, ParaPreset.title);
    c.select(0, 1);
    c.setPreset(ParaPreset.title);
    c.select(1, 1);
    expect(Runs.at(c.doc.runs, 4).size, 26);
    expect(Runs.at(c.doc.runs, 7).size, isNull);
    c.changeSize(1);
    c.select(6, 10);
    c.changeSize(2);
    expect(Runs.at(c.doc.runs, 7).size, 15);
  });

  test('lists go on with Return and end on an empty item', () {
    final c = DocController();
    type(c, 'eggs');
    c.toggleList();
    expect(c.text, '•\teggs');
    caret(c, c.text.length);
    type(c, '\n');
    expect(c.text, '•\teggs\n•\t');
    type(c, 'milk');
    type(c, '\n');
    type(c, '\n');
    expect(c.text, '•\teggs\n•\tmilk\n');
    c.select(0, 0);
    c.toggleList(numbered: true);
    expect(c.text.startsWith('eggs'), isTrue);
    c.toggleList(numbered: true);
    expect(c.text.startsWith('1.\teggs'), isTrue);
    caret(c, 7);
    type(c, '\n');
    expect(c.text.startsWith('1.\teggs\n2.\t'), isTrue);
    c.indent(1);
    expect(c.text.split('\n')[1], '\t2.\t');
    c.indent(-1);
    expect(c.text.split('\n')[1], '2.\t');
  });

  test('find, replace one, replace all, match case', () {
    final c = DocController(doc: StyledText.plain('Lemon lemon LEMON'));
    c.setFind('lemon');
    expect(c.matchCount, 3);
    expect(c.findNext(), isTrue);
    expect((c.selection.start, c.currentMatch), (0, 0));
    c.findNext();
    expect(c.selection.start, 6);
    c.findNext(backwards: true);
    expect(c.selection.start, 0);
    c.setFind('lemon', matchCase: true);
    expect(c.matchCount, 1);
    c.findNext();
    c.replaceCurrent('lime');
    expect(c.text, 'Lemon lime LEMON');
    c.setFind('lemon', matchCase: false);
    expect(c.replaceAll('x'), 2);
    expect(c.text, 'x lime x');
    c.undo();
    expect(c.text, 'Lemon lime LEMON');
  });

  test('plain text has no styles; making it plain drops them', () {
    final c = DocController(doc: StyledText.plain('ab'));
    c.select(0, 1);
    c.toggleTrait(Trait.bold);
    expect(c.doc.isPlain, isFalse);
    c.setRich(false);
    expect(c.doc.isPlain, isTrue);
    c.toggleTrait(Trait.bold);
    expect(c.doc.isPlain, isTrue);
    c.undo();
    expect(c.rich, isFalse);
  });

  test('copy and paste keep styles inside the app', () async {
    String? clip;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') return {'text': clip};
          return null;
        });
    final c = DocController(
      doc: StyledText('ab', const [
        Run(1, CharStyle(italic: true)),
        Run(1, CharStyle.plain),
      ]),
    );
    c.select(0, 1);
    await c.copy();
    expect(clip, 'a');
    caret(c, 2);
    await c.paste();
    expect(c.text, 'aba');
    expect(Runs.at(c.doc.runs, 2).italic, isTrue);
    clip = 'z\r\nq';
    await c.paste();
    expect(c.text, 'abaz\nq');
  });

  test('line and column', () {
    final c = DocController(doc: StyledText.plain('ab\ncde'));
    caret(c, 5);
    expect(c.lineColumn, (2, 3));
  });
}
