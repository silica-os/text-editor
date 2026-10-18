// What reaches outside the app: under `flutter test` nothing may talk to the user's session
// (no dialogs, no programs started on the machine running the tests).

import 'dart:io';

/// True under `flutter test`.
bool get startsNothing => Platform.environment.containsKey('FLUTTER_TEST');
