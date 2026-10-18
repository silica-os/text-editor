// The app's main flows: a new rich document, Save As, opening plain text, the find bar,
// closing with changes, converting to plain text, Document Info and the menus.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silica_ui/silica_ui.dart' show SilicaMenuDelegate, SilicaWindow;
import 'package:text_editor/src/app.dart';
import 'package:text_editor/src/model/document.dart';
import 'package:text_editor/src/model/styled.dart';
import 'package:text_editor/src/portal.dart';
import 'package:text_editor/src/recent.dart';
import 'package:text_editor/src/settings.dart';

class FakeDialogs implements FileDialogs {
  List<String>? openResult;
  String? saveResult;
  String? suggested;

  @override
  Future<List<String>?> open({
    required String title,
    bool multiple = true,
  }) async => openResult;

  @override
  Future<String?> save({required String title, required String name}) async {
    suggested = name;
    return saveResult;
  }
}

void main() {
  late Directory dir;
  late FakeDialogs dialogs;
  late EditorSettings settings;
  late List<MethodCall> menuCalls;
  final app = GlobalKey<EditorAppState>();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('text_editor_window');
    dialogs = FakeDialogs();
    settings = EditorSettings(null);
    RecentFiles.reset();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    menuCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SilicaMenuDelegate.defaultChannel,
      (call) async {
        menuCalls.add(call);
        return true;
      },
    );
    // No windows of their own here: documents open in the main window.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SilicaWindow.channel,
      (call) async => null,
    );
    await tester.pumpWidget(
      TextEditorApp(
        key: app,
        settings: settings,
        dialogs: dialogs,
        locale: locale,
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final text = find.descendant(
    of: find.byKey(const ValueKey('text area')),
    matching: find.byType(EditableText),
  );

  List<String> labels(String menu) {
    final menus =
        ((menuCalls.lastWhere((c) => c.method == 'setMenus').arguments
                    as Map)['menus']
                as List)
            .cast<Map<Object?, Object?>>();
    return [
      for (final i
          in (menus.firstWhere((m) => m['label'] == menu)['items'] as List))
        if (i is Map && i['label'] is String) i['label'] as String,
    ];
  }

  testWidgets('a new document is rich text; Save asks where and writes RTF', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Untitled'), findsOneWidget);
    expect(find.byKey(const ValueKey('font')), findsOneWidget);
    expect(find.byKey(const ValueKey('status bar')), findsNothing);
    await tester.enterText(text, 'Lemon cake');
    await settle(tester);
    expect(find.text('Edited'), findsOneWidget);
    final path = '${dir.path}/Lemon.rtf';
    dialogs.saveResult = path;
    final saved = await app.currentState!.mainWindow!.save();
    await settle(tester);
    expect(saved, isTrue);
    expect(dialogs.suggested, 'Untitled.rtf');
    expect(File(path).readAsStringSync(), startsWith(r'{\rtf1'));
    expect(find.text('Lemon.rtf'), findsOneWidget);
    expect(find.text('Edited'), findsNothing);
    expect(RecentFiles.paths, [path]);
  });

  testWidgets('plain text opens over a blank document, with a status bar', (
    tester,
  ) async {
    final file = File('${dir.path}/notes.txt')
      ..writeAsStringSync('eggs 3\nsugar 200 g');
    await pump(tester);
    app.currentState!.openPaths([file.path]);
    await settle(tester);
    expect(app.currentState!.documents.single.path, file.path);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('font')), findsNothing);
    expect(
      find.text('Plain text · Unicode (UTF-8) · Line 1, column 1'),
      findsOneWidget,
    );
    // A missing file says why.
    app.currentState!.openPaths(['${dir.path}/missing.txt']);
    await settle(tester);
    expect(find.text('“missing.txt” can’t be opened.'), findsOneWidget);
    expect(find.text('The file doesn’t exist.'), findsOneWidget);
  });

  testWidgets(
    'a document with a file saves itself; closing asks for untitled ones',
    (tester) async {
      final file = File('${dir.path}/a.txt')..writeAsStringSync('one');
      await pump(tester);
      app.currentState!.openPaths([file.path]);
      await settle(tester);
      await tester.enterText(text, 'one two');
      await tester.pump(const Duration(seconds: 3));
      expect(file.readAsStringSync(), 'one two');
      // Untitled: the question.
      app.currentState!.newDocument();
      await settle(tester);
      final window = app.currentState!.mainWindow!;
      expect(window.document.isUntitled, isTrue);
      await tester.enterText(text, 'draft');
      await settle(tester);
      late bool closed;
      unawaited(window.confirmClose().then((v) => closed = v));
      await settle(tester);
      expect(
        find.text('Do you want to save the changes you made to “Untitled”?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('alert Cancel')));
      await settle(tester);
      expect(closed, isFalse);
      unawaited(window.confirmClose().then((v) => closed = v));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('alert Don’t Save')));
      await settle(tester);
      expect(closed, isTrue);
    },
  );

  testWidgets('the find bar counts, moves through and replaces matches', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(text, 'lemon Lemon lemons');
    final window = app.currentState!.mainWindow!;
    window.showFind(replace: true);
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('find field')),
        matching: find.byType(EditableText),
      ),
      'lemon',
    );
    await settle(tester);
    expect(find.text('3 matches'), findsOneWidget);
    window.findNext();
    await settle(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('match case')));
    await settle(tester);
    expect(window.controller.matchCount, 2);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('replace field')),
        matching: find.byType(EditableText),
      ),
      'lime',
    );
    window.replaceAll();
    await settle(tester);
    expect(window.controller.text, 'lime Lemon limes');
    await tester.tap(find.byKey(const ValueKey('find done')));
    await settle(tester);
    expect(find.byKey(const ValueKey('find field')), findsNothing);
  });

  testWidgets('Make Plain Text asks before dropping styles', (tester) async {
    await pump(tester);
    await tester.enterText(text, 'Bold');
    final window = app.currentState!.mainWindow!;
    window.controller.select(0, 4);
    window.toggleTrait(
      window.controller.hasTrait(Trait.bold) ? Trait.italic : Trait.bold,
    );
    await settle(tester);
    unawaited(window.setRich(false));
    await settle(tester);
    expect(find.text('Convert this document to plain text?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alert OK')));
    await settle(tester);
    expect(window.controller.rich, isFalse);
    expect(find.byKey(const ValueKey('status bar')), findsOneWidget);
    expect(window.document.format, DocFormat.plain);
  });

  testWidgets('Document Info counts the text', (tester) async {
    await pump(tester);
    await tester.enterText(text, 'Two words\n\nand more');
    await settle(tester);
    app.currentState!.mainWindow!.showInfo();
    await settle(tester);
    expect(find.byKey(const ValueKey('info popover')), findsOneWidget);
    expect(find.byKey(const ValueKey('info Words')), findsOneWidget);
    expect(
      (tester.widget(find.byKey(const ValueKey('info Words'))) as Text).data,
      '4',
    );
    expect(
      (tester.widget(find.byKey(const ValueKey('info Paragraphs'))) as Text)
          .data,
      '2',
    );
  });

  testWidgets('the menus follow the document', (tester) async {
    await pump(tester);
    await settle(tester);
    expect(
      labels('File'),
      containsAll(['New', 'Open…', 'Save…', 'Save As…', 'Duplicate']),
    );
    expect(labels('Format'), contains('Make Plain Text'));
    expect(labels('Edit'), isNotEmpty);
  });

  testWidgets('Italian', (tester) async {
    await pump(tester, locale: const Locale('it'));
    expect(find.text('Senza titolo'), findsOneWidget);
  });
}
