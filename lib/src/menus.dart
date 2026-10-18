// Text Editor's menus in Silica's menu bar (silica-menu-v1): the app menu, File, Edit, Format,
// View, Window and Help, built for the active document window (or, with no window, the app
// alone). Items that do not apply are disabled; what Text Editor cannot do is not listed.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import '../l10n/app_localizations.dart';
import 'editor/doc_controller.dart';
import 'model/document.dart';
import 'model/styled.dart';
import 'model/text_codec.dart';
import 'recent.dart';
import 'settings.dart';
import 'style.dart';
import 'ui/window.dart';

/// What the menus act on: a document window.
abstract interface class EditorCommands {
  AppLocalizations get strings;
  TextDocument get doc;
  DocController get controller;
  EditorSettings get settings;
  EditorHost get host;
  bool get edited;
  bool get textFocused;
  bool get findShown;
  bool get wrapToPage;
  double get zoom;

  Future<bool> save();
  Future<bool> saveAs();
  Future<void> close();
  Future<void> revertToSaved();
  void revertToOpened();
  void rename();
  void showInfo();
  void undo();
  void redo();
  void toggleTrait(Trait t);
  void changeSize(int delta);
  void setPreset(ParaPreset p);
  void toggleList({bool numbered = false});
  void indent(int delta);
  Future<void> setRich(bool rich);
  void setWrapToPage(bool page);
  void setZoom(double zoom);
  void showFind({bool replace = false});
  void hideFind();
  void findNext({bool backwards = false});
  void useSelectionForFind();
  void replaceAll();
  Future<void> setEncoding(TextEncoding encoding);
  Future<void> reopenWithEncoding(TextEncoding encoding);
}

SingleActivator _cmd(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) => SingleActivator(key, meta: true, shift: shift, alt: alt);

String encodingLabel(AppLocalizations l, TextEncoding e) => switch (e) {
  TextEncoding.utf8 => l.encodingUtf8,
  TextEncoding.utf16le => l.encodingUtf16le,
  TextEncoding.utf16be => l.encodingUtf16be,
  TextEncoding.latin1 => l.encodingLatin1,
};

/// The app menu and File › New, Open, Open Recent: also shown with no window open.
List<PlatformMenuItem> _appAndFile(
  AppLocalizations l,
  EditorHost host, {
  required List<PlatformMenuItem> fileItems,
}) {
  final recent = RecentFiles.paths;
  return [
    SilicaMenus.app(l.appTitle, onSettings: host.showSettings),
    SilicaMenu(
      label: l.menuFile,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.newDocument,
              shortcut: _cmd(LogicalKeyboardKey.keyN),
              onSelected: host.newDocument,
            ),
            SilicaMenuItem(
              label: l.openEllipsis,
              shortcut: _cmd(LogicalKeyboardKey.keyO),
              onSelected: () => host.openDialog(),
            ),
            SilicaMenu(
              label: l.openRecent,
              enabled: recent.isNotEmpty,
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    for (final p in recent)
                      SilicaMenuItem(
                        label: baseName(p),
                        onSelected: () => host.openPaths([p]),
                      ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    SilicaMenuItem(
                      label: l.clearMenu,
                      onSelected: RecentFiles.clear,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        ...fileItems,
      ],
    ),
  ];
}

/// The menus with no window open.
List<PlatformMenuItem> appMenus(AppLocalizations l, EditorHost host) => [
  ..._appAndFile(l, host, fileItems: const []),
  SilicaMenus.window(l.menuWindow),
  SilicaMenus.help(l.menuHelp),
];

/// The menus of a document window.
List<PlatformMenuItem> editorMenus(AppLocalizations l, EditorCommands w) {
  final c = w.controller;
  final doc = w.doc;
  final rich = c.rich;
  final plainFile = !rich && doc.path != null;
  final sel = c.selection;
  final hasSelection = sel.isValid && !sel.isCollapsed;
  const cause = SelectionChangedCause.keyboard;
  SilicaMenuItem text(
    SilicaMenuItemRole role,
    Intent intent,
    SingleActivator? shortcut, {
    bool enabled = true,
  }) => SilicaMenuItem(
    role: role,
    shortcut: shortcut,
    onSelectedIntent: enabled ? intent : null,
    enabled: enabled,
  );
  SilicaMenuItem trait(Trait t, String label, LogicalKeyboardKey? key) =>
      SilicaMenuItem(
        label: label,
        shortcut: key == null ? null : _cmd(key),
        checked: rich && c.hasTrait(t),
        enabled: rich,
        onSelected: rich ? () => w.toggleTrait(t) : null,
      );
  final zoomAt = EditorMetrics.zoomSteps.indexOf(w.zoom);
  return [
    ..._appAndFile(
      l,
      w.host,
      fileItems: [
        const PlatformMenuItemGroup(
          members: [SilicaMenuItem.system(SilicaMenuItemRole.close)],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: doc.needsSaveAs ? l.saveEllipsis : l.save,
              shortcut: _cmd(LogicalKeyboardKey.keyS),
              onSelected: () => w.save(),
            ),
            SilicaMenuItem(
              label: l.duplicate,
              shortcut: _cmd(LogicalKeyboardKey.keyS, shift: true),
              onSelected: () => w.host.duplicate(doc),
            ),
            SilicaMenuItem(
              label: l.renameEllipsis,
              enabled: doc.path != null,
              onSelected: doc.path != null ? w.rename : null,
            ),
            SilicaMenuItem(
              label: l.saveAsEllipsis,
              shortcut: _cmd(LogicalKeyboardKey.keyS, shift: true, alt: true),
              onSelected: () => w.saveAs(),
            ),
            SilicaMenu(
              label: l.revertTo,
              enabled: w.edited || doc.changedSinceOpened,
              menus: [
                SilicaMenuItem(
                  label: l.lastSavedVersion,
                  enabled: w.edited && doc.path != null,
                  onSelected: w.edited && doc.path != null
                      ? () => w.revertToSaved()
                      : null,
                ),
                SilicaMenuItem(
                  label: l.lastOpenedVersion,
                  enabled: doc.changedSinceOpened,
                  onSelected: doc.changedSinceOpened ? w.revertToOpened : null,
                ),
              ],
            ),
          ],
        ),
        if (!rich)
          PlatformMenuItemGroup(
            members: [
              SilicaMenu(
                label: l.textEncoding,
                menus: [
                  for (final e in TextEncoding.values)
                    SilicaMenuItem(
                      label: encodingLabel(l, e),
                      checked: doc.encoding == e,
                      onSelected: () => w.setEncoding(e),
                    ),
                ],
              ),
              SilicaMenu(
                label: l.reopenWithEncoding,
                enabled: plainFile,
                menus: [
                  for (final e in TextEncoding.values)
                    SilicaMenuItem(
                      label: encodingLabel(l, e),
                      enabled: plainFile,
                      onSelected: plainFile
                          ? () => w.reopenWithEncoding(e)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.showDocumentInfo,
              shortcut: _cmd(LogicalKeyboardKey.keyI, alt: true),
              onSelected: w.showInfo,
            ),
          ],
        ),
      ],
    ),
    SilicaMenu(
      label: l.menuEdit,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              role: SilicaMenuItemRole.undo,
              shortcut: _cmd(LogicalKeyboardKey.keyZ),
              enabled: w.textFocused && c.canUndo,
              onSelected: w.textFocused && c.canUndo ? w.undo : null,
            ),
            SilicaMenuItem(
              role: SilicaMenuItemRole.redo,
              shortcut: _cmd(LogicalKeyboardKey.keyZ, shift: true),
              enabled: w.textFocused && c.canRedo,
              onSelected: w.textFocused && c.canRedo ? w.redo : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            text(
              SilicaMenuItemRole.cut,
              const CopySelectionTextIntent.cut(cause),
              _cmd(LogicalKeyboardKey.keyX),
            ),
            text(
              SilicaMenuItemRole.copy,
              CopySelectionTextIntent.copy,
              _cmd(LogicalKeyboardKey.keyC),
            ),
            text(
              SilicaMenuItemRole.paste,
              const PasteTextIntent(cause),
              _cmd(LogicalKeyboardKey.keyV),
            ),
            text(
              SilicaMenuItemRole.delete,
              const DeleteCharacterIntent(forward: true),
              null,
            ),
            text(
              SilicaMenuItemRole.selectAll,
              const SelectAllTextIntent(cause),
              _cmd(LogicalKeyboardKey.keyA),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenu(
              label: l.menuFind,
              menus: [
                SilicaMenuItem(
                  label: l.findEllipsis,
                  shortcut: _cmd(LogicalKeyboardKey.keyF),
                  onSelected: w.showFind,
                ),
                SilicaMenuItem(
                  label: l.findAndReplaceEllipsis,
                  shortcut: _cmd(LogicalKeyboardKey.keyF, alt: true),
                  onSelected: () => w.showFind(replace: true),
                ),
                SilicaMenuItem(
                  label: l.findNext,
                  shortcut: _cmd(LogicalKeyboardKey.keyG),
                  enabled: c.findText.isNotEmpty,
                  onSelected: c.findText.isNotEmpty ? w.findNext : null,
                ),
                SilicaMenuItem(
                  label: l.findPrevious,
                  shortcut: _cmd(LogicalKeyboardKey.keyG, shift: true),
                  enabled: c.findText.isNotEmpty,
                  onSelected: c.findText.isNotEmpty
                      ? () => w.findNext(backwards: true)
                      : null,
                ),
                SilicaMenuItem(
                  label: l.useSelectionForFind,
                  shortcut: _cmd(LogicalKeyboardKey.keyE),
                  enabled: hasSelection,
                  onSelected: hasSelection ? w.useSelectionForFind : null,
                ),
                SilicaMenuItem(
                  label: l.replaceAll,
                  enabled: c.matchCount > 0,
                  onSelected: c.matchCount > 0 ? w.replaceAll : null,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    SilicaMenu(
      label: l.menuFormat,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenu(
              label: l.menuFont,
              enabled: rich,
              menus: [
                trait(Trait.bold, l.bold, LogicalKeyboardKey.keyB),
                trait(Trait.italic, l.italic, LogicalKeyboardKey.keyI),
                trait(Trait.underline, l.underline, LogicalKeyboardKey.keyU),
                trait(Trait.strike, l.strikethrough, null),
                SilicaMenuItem(
                  label: l.bigger,
                  shortcut: _cmd(LogicalKeyboardKey.equal),
                  enabled: rich,
                  onSelected: rich ? () => w.changeSize(1) : null,
                ),
                SilicaMenuItem(
                  label: l.smaller,
                  shortcut: _cmd(LogicalKeyboardKey.minus),
                  enabled: rich,
                  onSelected: rich ? () => w.changeSize(-1) : null,
                ),
              ],
            ),
            SilicaMenu(
              label: l.menuStyle,
              enabled: rich,
              menus: [
                for (final (p, label) in [
                  (ParaPreset.title, l.presetTitle),
                  (ParaPreset.heading, l.presetHeading),
                  (ParaPreset.subheading, l.presetSubheading),
                  (ParaPreset.body, l.presetBody),
                  (ParaPreset.mono, l.presetMono),
                ])
                  SilicaMenuItem(
                    label: label,
                    checked: rich && c.currentPreset == p,
                    enabled: rich,
                    onSelected: rich ? () => w.setPreset(p) : null,
                  ),
              ],
            ),
            SilicaMenu(
              label: l.menuLists,
              enabled: rich,
              menus: [
                SilicaMenuItem(
                  label: l.bulletedList,
                  enabled: rich,
                  onSelected: rich ? w.toggleList : null,
                ),
                SilicaMenuItem(
                  label: l.numberedList,
                  enabled: rich,
                  onSelected: rich ? () => w.toggleList(numbered: true) : null,
                ),
                SilicaMenuItem(
                  label: l.increaseIndent,
                  shortcut: _cmd(LogicalKeyboardKey.bracketRight),
                  onSelected: () => w.indent(1),
                ),
                SilicaMenuItem(
                  label: l.decreaseIndent,
                  shortcut: _cmd(LogicalKeyboardKey.bracketLeft),
                  onSelected: () => w.indent(-1),
                ),
              ],
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: rich ? l.makePlainText : l.makeRichText,
              shortcut: _cmd(LogicalKeyboardKey.keyT, shift: true),
              onSelected: () => w.setRich(!rich),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: w.wrapToPage ? l.wrapToWindow : l.wrapToPage,
              shortcut: _cmd(LogicalKeyboardKey.keyW, shift: true),
              onSelected: () => w.setWrapToPage(!w.wrapToPage),
            ),
          ],
        ),
      ],
    ),
    SilicaMenu(
      label: l.menuView,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.actualSize,
              shortcut: _cmd(LogicalKeyboardKey.digit0),
              enabled: w.zoom != 1,
              onSelected: w.zoom != 1 ? () => w.setZoom(1) : null,
            ),
            SilicaMenuItem(
              label: l.zoomIn,
              shortcut: _cmd(LogicalKeyboardKey.period, shift: true),
              enabled: zoomAt < EditorMetrics.zoomSteps.length - 1,
              onSelected: zoomAt < EditorMetrics.zoomSteps.length - 1
                  ? () => w.setZoom(EditorMetrics.zoomSteps[zoomAt + 1])
                  : null,
            ),
            SilicaMenuItem(
              label: l.zoomOut,
              shortcut: _cmd(LogicalKeyboardKey.comma, shift: true),
              enabled: zoomAt > 0,
              onSelected: zoomAt > 0
                  ? () => w.setZoom(EditorMetrics.zoomSteps[zoomAt - 1])
                  : null,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [SilicaMenuItem.system(SilicaMenuItemRole.fullScreen)],
        ),
      ],
    ),
    SilicaMenus.window(l.menuWindow),
    SilicaMenus.help(l.menuHelp),
  ];
}
