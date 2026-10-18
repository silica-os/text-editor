// Text Editor, the text editor of Silica.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import 'src/app.dart';
import 'src/args.dart';
import 'src/portal.dart';
import 'src/settings.dart';
import 'src/style.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  // The toolbar is unified with the window: Ossido draws only the window buttons.
  SilicaWindow.setFullSizeContent(EditorMetrics.toolbar).ignore();
  SilicaWindow.setSizeLimits(min: EditorMetrics.minimumWindow).ignore();
  // A document app: closing its last window keeps it running (APP-LC).
  SilicaApp.quitWhenLastWindowCloses = false;
  runApp(
    TextEditorApp(
      settings: EditorSettings.forUser(Platform.environment),
      dialogs: PortalFileDialogs(),
      files: filesFromArgs(args),
    ),
  );
}
