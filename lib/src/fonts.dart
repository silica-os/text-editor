// The font families the Font pop-up offers: Inter and JetBrains Mono (served by silica_ui),
// then the families installed on the system (fontconfig's `fc-list`), sorted.

import 'dart:io';

import 'editor/doc_controller.dart';
import 'external.dart';

List<String>? _cache;

/// The families to choose from; [extra] (the fonts of the open document) are added.
List<String> fontFamilies({Iterable<String> extra = const []}) {
  final known = _cache ??= _systemFamilies();
  final all = <String>{uiFont, monoFont, ...known, ...extra};
  final rest = all.where((f) => !bundledFonts.contains(f)).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [uiFont, monoFont, ...rest];
}

List<String> _systemFamilies() {
  if (startsNothing) return const [];
  try {
    final result = Process.runSync('fc-list', [':', 'family']);
    if (result.exitCode != 0) return const [];
    final out = <String>{};
    for (final line in '${result.stdout}'.split('\n')) {
      // "Family,Localized Family": the first name.
      final name = line.split(',').first.trim();
      if (name.isNotEmpty && !name.startsWith('.')) out.add(name);
    }
    return out.toList();
  } on ProcessException {
    return const [];
  }
}
