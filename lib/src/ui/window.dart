// A document window (kit `Apps/Text Editor/*`): the toolbar with the document title (its
// popover renames the file), Document Info and Share; for rich text the format bar (paragraph
// style, font, size, colour, bold/italic/underline, lists and indentation); the find bar; the
// text; for plain text the status bar with the format, the encoding and the caret's position.

import 'dart:async';
import 'dart:io' show FileSystemException;
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:silica_ui/silica_ui.dart';

import '../../l10n/app_localizations.dart';
import '../editor/doc_controller.dart';
import '../fonts.dart';
import '../menus.dart';
import '../model/document.dart';
import '../model/styled.dart';
import '../model/text_codec.dart';
import '../portal.dart';
import '../recent.dart';
import '../settings.dart';
import '../style.dart';
import 'settings_view.dart';

/// What a window needs from the app.
abstract interface class EditorHost {
  EditorSettings get settings;
  FileDialogs get dialogs;

  /// File › New.
  void newDocument();

  /// File › Open…: the Open dialog, then each file in a window.
  Future<void> openDialog();

  /// Opens [paths], each in a window (an untitled blank document is replaced).
  void openPaths(List<String> paths);

  /// File › Duplicate: a new untitled window with a copy of [doc].
  void duplicate(TextDocument doc);

  /// App › Settings….
  void showSettings();

  /// The window has the keyboard: the menu bar shows its menus.
  void focusWindow(EditorWindowState window);

  /// The window's menus changed.
  void publishMenus(EditorWindowState window, List<PlatformMenuItem> menus);

  /// Closes the window (after it agreed).
  void closeWindow(EditorWindowState window);
}

/// A button of an alert.
class _Button {
  const _Button(this.label, this.onPressed, {this.role = AlertRole.normal});
  final String label;
  final VoidCallback onPressed;
  final AlertRole role;
}

class _Alert {
  const _Alert(this.title, this.buttons, {this.message});
  final String title;
  final String? message;
  final List<_Button> buttons;
}

/// Answers of the save question.
enum _SaveAnswer { save, discard, cancel }

class EditorWindow extends StatefulWidget {
  const EditorWindow({
    super.key,
    required this.document,
    required this.host,
    this.active = true,
  });

  final TextDocument document;
  final EditorHost host;
  final bool active;

  @override
  State<EditorWindow> createState() => EditorWindowState();
}

class EditorWindowState extends State<EditorWindow> implements EditorCommands {
  final FocusNode _textFocus = FocusNode(debugLabel: 'text');
  final GlobalKey<EditableTextState> _editable = GlobalKey();
  final GlobalKey _titleKey = GlobalKey(debugLabel: 'title');
  final GlobalKey _infoKey = GlobalKey(debugLabel: 'info');
  final GlobalKey _shareKey = GlobalKey(debugLabel: 'share');
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _findFocus = FocusNode(debugLabel: 'find');
  final FocusNode _replaceFocus = FocusNode(debugLabel: 'replace');
  final ScrollController _scroll = ScrollController();
  late final _Gestures _gestures = _Gestures(this);

  late TextDocument _doc = widget.document;
  bool _findShown = false;
  bool _replaceShown = false;
  bool _wrapToPage = false;
  double _zoom = 1;
  _Alert? _alert;
  Timer? _autosave;
  bool _shareable = false;
  String? _shareFor;
  bool _encodingChanged = false;

  bool _settingsSheet = false;
  bool _appActive = true;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (s) {
      if (mounted) setState(() => _appActive = s == AppLifecycleState.resumed);
    },
  );

  /// The answer to the save question, while it is asked.
  Completer<_SaveAnswer>? _asking;

  TextDocument get document => _doc;
  DocController get _c => _doc.controller;
  EditorSettings get _settings => widget.host.settings;
  AppLocalizations get l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _attach(_doc);
    _settings.addListener(_changed);
    _textFocus.addListener(_focusChanged);
    _find.addListener(_findChanged);
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(EditorWindow old) {
    super.didUpdateWidget(old);
    if (old.document != widget.document) replaceDocument(widget.document);
  }

  void _attach(TextDocument doc) {
    doc.addListener(_docChanged);
    doc.controller.addListener(_changed);
  }

  void _detach(TextDocument doc) {
    doc.removeListener(_docChanged);
    doc.controller.removeListener(_changed);
  }

  /// Shows [doc] in this window instead (Open over a blank untitled document).
  void replaceDocument(TextDocument doc) {
    if (doc == _doc) return;
    _detach(_doc);
    _doc = doc;
    _attach(doc);
    _encodingChanged = false;
    _shareFor = null;
    if (_find.text.isNotEmpty) _c.setFind(_find.text);
    setState(() {});
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _lifecycle.dispose();
    _detach(_doc);
    _settings.removeListener(_changed);
    _textFocus.dispose();
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    _replaceFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _focusChanged() {
    if (_textFocus.hasFocus) widget.host.focusWindow(this);
    _changed();
  }

  void _docChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleAutosave();
  }

  // MARK: saving

  bool get _edited => _doc.edited || _encodingChanged;

  void _scheduleAutosave() {
    _autosave?.cancel();
    if (!_settings.autosave || !_edited || _doc.needsSaveAs) return;
    _autosave = Timer(EditorMetrics.autosaveDelay, () {
      if (!mounted || !_edited || _doc.needsSaveAs) return;
      if (_doc.changedOnDisk) return;
      try {
        _write();
      } on Object {
        // Shown when the user saves or closes.
      }
    });
  }

  void _write({String? to, TextEncoding? encoding}) {
    _doc.save(to: to, encoding: encoding);
    _encodingChanged = false;
    final p = _doc.path;
    if (p != null) RecentFiles.add(p);
  }

  /// File › Save: to the document's file, or asks where.
  @override
  Future<bool> save() async {
    if (_doc.needsSaveAs) return saveAs();
    if (_doc.changedOnDisk) {
      final overwrite = await _ask(
        l10n.changedOnDiskTitle(_title),
        l10n.changedOnDiskMessage,
        [
          (l10n.cancel, AlertRole.cancel, false),
          (l10n.saveAnyway, AlertRole.primary, true),
        ],
      );
      if (overwrite != true) return false;
    }
    return _tryWrite();
  }

  bool _tryWrite({String? to, TextEncoding? encoding}) {
    try {
      _write(to: to, encoding: encoding);
      setState(() {});
      return true;
    } on UnencodableException catch (e) {
      _show(
        l10n.cannotEncodeTitle(_encodingName(encoding ?? _doc.encoding)),
        message: l10n.cannotEncodeMessage(e.character),
      );
    } on FileSystemException catch (e) {
      _show(
        l10n.cannotSaveTitle(_title),
        message: e.osError?.message ?? e.message,
      );
    }
    return false;
  }

  /// File › Save As…: asks for a file and writes there; the window then shows that file.
  @override
  Future<bool> saveAs() async {
    final ext = _doc.format == DocFormat.rich ? 'rtf' : 'txt';
    final current = _doc.path;
    final name = current == null
        ? '${_title}.$ext'
        : withExtension(
            baseName(current),
            ext == 'txt' && extensionOf(current) != 'rtf'
                ? extensionOf(current).isEmpty
                      ? 'txt'
                      : extensionOf(current)
                : ext,
          );
    String? target;
    try {
      target = await widget.host.dialogs.save(title: l10n.saveAs, name: name);
    } on FileDialogUnavailable {
      if (mounted) _show(l10n.noFileDialog);
      return false;
    }
    if (!mounted || target == null) return false;
    final encoding = _doc.isUntitled && _doc.format == DocFormat.plain
        ? _settings.saveEncoding
        : null;
    return _tryWrite(to: target, encoding: encoding);
  }

  /// Asked before the window closes: saves by itself, or asks. False keeps the window.
  Future<bool> confirmClose() async {
    _autosave?.cancel();
    if (!_edited) return true;
    if (_settings.autosave && !_doc.needsSaveAs && !_doc.changedOnDisk) {
      if (_tryWrite()) return true;
      return false;
    }
    if (_asking != null) return false;
    final asking = _asking = Completer<_SaveAnswer>();
    setState(
      () => _alert = _Alert(l10n.saveChangesTitle(_title), [
        _Button(
          l10n.dontSave,
          () => _answer(_SaveAnswer.discard),
          role: AlertRole.destructive,
        ),
        _Button(
          l10n.cancel,
          () => _answer(_SaveAnswer.cancel),
          role: AlertRole.cancel,
        ),
        _Button(
          l10n.saveEllipsis,
          () => _answer(_SaveAnswer.save),
          role: AlertRole.primary,
        ),
      ], message: l10n.saveChangesMessage),
    );
    final answer = await asking.future;
    _asking = null;
    switch (answer) {
      case _SaveAnswer.discard:
        return true;
      case _SaveAnswer.cancel:
        return false;
      case _SaveAnswer.save:
        return save();
    }
  }

  void _answer(_SaveAnswer a) {
    setState(() => _alert = null);
    _asking?.complete(a);
    _textFocus.requestFocus();
  }

  /// File › Close (⌘W).
  @override
  Future<void> close() async {
    if (await confirmClose() && mounted) widget.host.closeWindow(this);
  }

  // MARK: alerts

  void _show(String title, {String? message}) => setState(
    () => _alert = _Alert(title, [
      _Button(l10n.ok, () {
        setState(() => _alert = null);
        _textFocus.requestFocus();
      }, role: AlertRole.primary),
    ], message: message),
  );

  Future<T?> _ask<T>(
    String title,
    String? message,
    List<(String, AlertRole, T)> buttons,
  ) {
    final done = Completer<T?>();
    setState(
      () => _alert = _Alert(title, [
        for (final (label, role, value) in buttons)
          _Button(label, () {
            setState(() => _alert = null);
            _textFocus.requestFocus();
            if (!done.isCompleted) done.complete(value);
          }, role: role),
      ], message: message),
    );
    return done.future;
  }

  /// A file could not be opened.
  void showOpenFailure(OpenFailure e) {
    final name = baseName(e.path);
    _show(
      l10n.cannotOpenTitle(name),
      message: switch (e.problem) {
        OpenProblem.missing => l10n.openMissing,
        OpenProblem.notText => l10n.openNotText,
        OpenProblem.unreadable => l10n.openUnreadable,
        OpenProblem.directory => l10n.openDirectory,
      },
    );
  }

  /// Settings inside this window, where Silica cannot open a window for them.
  void showSettingsSheet() => setState(() => _settingsSheet = true);

  // MARK: names

  String get _title {
    final p = _doc.path;
    if (p != null) return baseName(p);
    return _doc.untitledNumber <= 1
        ? l10n.untitled
        : l10n.untitledNumber(_doc.untitledNumber);
  }

  String _encodingName(TextEncoding e) => switch (e) {
    TextEncoding.utf8 => l10n.encodingUtf8,
    TextEncoding.utf16le => l10n.encodingUtf16le,
    TextEncoding.utf16be => l10n.encodingUtf16be,
    TextEncoding.latin1 => l10n.encodingLatin1,
  };

  // MARK: commands (EditorCommands)

  @override
  AppLocalizations get strings => l10n;

  @override
  TextDocument get doc => _doc;

  @override
  DocController get controller => _c;

  @override
  bool get edited => _edited;

  @override
  bool get textFocused => _textFocus.hasFocus;

  @override
  bool get findShown => _findShown;

  @override
  bool get wrapToPage => _wrapToPage;

  @override
  double get zoom => _zoom;

  @override
  EditorSettings get settings => _settings;

  @override
  EditorHost get host => widget.host;

  @override
  void undo() => _c.undo();

  @override
  void redo() => _c.redo();

  @override
  void toggleTrait(Trait t) {
    _c.toggleTrait(t);
    _textFocus.requestFocus();
  }

  @override
  void changeSize(int delta) => _c.changeSize(delta);

  @override
  void setPreset(ParaPreset p) {
    _c.setPreset(p);
    _textFocus.requestFocus();
  }

  @override
  void toggleList({bool numbered = false}) {
    _c.toggleList(numbered: numbered);
    _textFocus.requestFocus();
  }

  @override
  void indent(int delta) {
    _c.indent(delta);
    _textFocus.requestFocus();
  }

  @override
  Future<void> setRich(bool rich) async {
    if (rich == _c.rich) return;
    if (!rich && !_c.doc.isPlain) {
      final ok = await _ask(l10n.makePlainTitle, l10n.makePlainMessage, [
        (l10n.cancel, AlertRole.cancel, false),
        (l10n.ok, AlertRole.primary, true),
      ]);
      if (ok != true) return;
    }
    _c.setRich(rich);
  }

  @override
  void setWrapToPage(bool page) => setState(() => _wrapToPage = page);

  @override
  void setZoom(double zoom) => setState(() => _zoom = zoom);

  @override
  void showFind({bool replace = false}) {
    setState(() {
      _findShown = true;
      _replaceShown = _replaceShown || replace;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (replace ? _replaceFocus : _findFocus).requestFocus();
      _find.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _find.text.length,
      );
    });
  }

  @override
  void hideFind() {
    setState(() => _findShown = false);
    _c.setFind('');
    _textFocus.requestFocus();
  }

  void _findChanged() {
    if (_find.text == _c.findText) return;
    _c.setFind(_find.text);
  }

  @override
  void findNext({bool backwards = false}) {
    if (_c.findText.isEmpty) {
      showFind();
      return;
    }
    _c.findNext(backwards: backwards);
    _revealSelection();
  }

  @override
  void useSelectionForFind() {
    final sel = _c.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = _c.text.substring(sel.start, sel.end);
    _find.text = text;
    _c.setFind(text);
  }

  @override
  void replaceAll() {
    final n = _c.replaceAll(_replace.text);
    if (n == 0) {
      _show(l10n.notFound);
    }
  }

  void _revealSelection() {
    // The editable scrolls the caret into view once it has the focus.
    _editable.currentState?.bringIntoView(_c.selection.extent);
  }

  @override
  Future<void> setEncoding(TextEncoding encoding) async {
    if (_doc.format != DocFormat.plain || encoding == _doc.encoding) return;
    try {
      encodeText(_c.text, encoding);
    } on UnencodableException catch (e) {
      _show(
        l10n.cannotEncodeTitle(_encodingName(encoding)),
        message: l10n.cannotEncodeMessage(e.character),
      );
      return;
    }
    setState(() {
      _doc.encoding = encoding;
      _encodingChanged = true;
    });
    _scheduleAutosave();
  }

  @override
  Future<void> reopenWithEncoding(TextEncoding encoding) async {
    if (_edited) {
      final ok = await _ask(l10n.reopenTitle, l10n.reopenMessage, [
        (l10n.cancel, AlertRole.cancel, false),
        (l10n.reopen, AlertRole.destructive, true),
      ]);
      if (ok != true) return;
    }
    try {
      _doc.reopen(encoding);
      _encodingChanged = false;
    } on OpenFailure {
      _show(l10n.cannotOpenTitle(_title));
    }
  }

  @override
  Future<void> revertToSaved() async {
    final ok = await _ask(l10n.revertTitle(_title), l10n.revertMessage, [
      (l10n.cancel, AlertRole.cancel, false),
      (l10n.revert, AlertRole.destructive, true),
    ]);
    if (ok == true) {
      _doc.revertToSaved();
      _encodingChanged = false;
    }
  }

  @override
  void revertToOpened() {
    _doc.revertToOpened();
    _scheduleAutosave();
  }

  @override
  void rename() {
    if (_doc.isUntitled) {
      unawaited(saveAs());
      return;
    }
    _titleMenu();
  }

  @override
  void showInfo() => unawaited(_infoPopover());

  // MARK: share

  void _refreshShare() {
    final p = _doc.path;
    if (p == _shareFor) return;
    _shareFor = p;
    _shareable = false;
    if (p == null) return;
    unawaited(() async {
      final targets = await SilicaShare.targets([Uri.file(p)]);
      if (!mounted || p != _shareFor || targets.isEmpty) return;
      setState(() => _shareable = true);
    }());
  }

  Future<void> _openShare() async {
    final p = _doc.path;
    final box = _shareKey.currentContext?.findRenderObject();
    if (p == null || box is! RenderBox || !box.attached) return;
    if (_edited && !_doc.needsSaveAs) _tryWrite();
    final at = box.localToGlobal(Offset(0, box.size.height + 4));
    await showSilicaShareMenu(
      context: context,
      position: at,
      files: [Uri.file(p)],
      copyLabel: l10n.copy,
    );
  }

  // MARK: popovers

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _titleMenu() {
    final rect = _rectOf(_titleKey);
    final p = _doc.path;
    if (rect == null) return;
    if (p == null) {
      unawaited(saveAs());
      return;
    }
    unawaited(
      showAmalfiPopover(
        context: context,
        anchor: rect,
        builder: (context, dismiss) => SizedBox(
          width: EditorMetrics.titlePopoverWidth,
          child: _TitlePopover(
            path: p,
            close: dismiss,
            onRename: (name) {
              try {
                _doc.rename(name);
                RecentFiles.add(_doc.path!);
              } on FileSystemException catch (e) {
                _show(
                  l10n.cannotRenameTitle(name),
                  message: e.osError?.message ?? e.message,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _infoPopover() async {
    final rect = _rectOf(_infoKey);
    if (rect == null) return;
    final counts = _doc.counts;
    final pages = _pageCount();
    final locale = l10n.localeName;
    final number = NumberFormat.decimalPattern(locale);
    final modified = _doc.fileModified;
    String date(DateTime d) {
      final now = DateTime.now();
      final today =
          d.year == now.year && d.month == now.month && d.day == now.day;
      return today
          ? l10n.todayAt(DateFormat.Hm(locale).format(d))
          : DateFormat.yMMMd(locale).format(d);
    }

    final rows = <(String, String)>[
      (l10n.infoWords, number.format(counts.words)),
      (l10n.infoCharacters, number.format(counts.characters)),
      (l10n.infoParagraphs, number.format(counts.paragraphs)),
      (l10n.infoPages, number.format(pages)),
      if (modified != null) (l10n.infoModified, date(modified)),
      if (_doc.fileSize != null) (l10n.infoSize, _size(_doc.fileSize!)),
      _doc.format == DocFormat.rich
          ? (l10n.infoFormat, l10n.formatRich)
          : (l10n.infoEncoding, _encodingName(_doc.encoding)),
    ];
    await showAmalfiPopover(
      context: context,
      anchor: rect,
      builder: (context, dismiss) {
        final colors = EditorColors.of(context);
        return SizedBox(
          key: const ValueKey('info popover'),
          width: EditorMetrics.infoWidth - 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.documentInfo,
                style: AmalfiType.headline(color: colors.text),
              ),
              const SizedBox(height: 12),
              for (final (label, value) in rows)
                SizedBox(
                  height: 26,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: AmalfiType.callout(color: colors.secondary),
                        ),
                      ),
                      Text(
                        value,
                        key: ValueKey('info $label'),
                        style: AmalfiType.callout(color: colors.text),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _size(int bytes) {
    final n = NumberFormat.decimalPattern(l10n.localeName);
    if (bytes < 1000) return l10n.bytes(bytes);
    if (bytes < 1000 * 1000)
      return l10n.kilobytes(n.format((bytes / 1000).round()));
    return l10n.megabytes((bytes / 1000000).toStringAsFixed(1));
  }

  /// Pages of US Letter with one-inch margins the text fills.
  int _pageCount() {
    final saved = _c.look;
    final look = saved;
    if (look == null) return 1;
    _c.look = DocLook(
      font: look.font,
      size: look.size,
      package: look.package,
      text: look.text,
      match: look.match,
      currentMatch: look.currentMatch,
    );
    final span = _c.buildTextSpan(context: context, withComposing: false);
    _c.look = saved;
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: EditorMetrics.pageWidth - 2 * EditorMetrics.pageMargin);
    final height = tp.height;
    tp.dispose();
    const usable = EditorMetrics.pageHeight - 2 * EditorMetrics.pageMargin;
    return max(1, (height / usable).ceil());
  }

  // MARK: build

  @override
  Widget build(BuildContext context) {
    _refreshShare();
    final menus = editorMenus(l10n, this);
    widget.host.publishMenus(this, menus);
    final colors = EditorColors.of(context);
    return CallbackShortcuts(
      bindings: silicaMenuShortcuts(menus),
      child: Listener(
        onPointerDown: (_) => widget.host.focusWindow(this),
        child: WindowActiveScope(
          active: widget.active && _appActive,
          child: ColoredBox(
            color: colors.window,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: EditorMetrics.toolbar,
                        child: _toolbar(colors),
                      ),
                      if (_c.rich) ...[
                        SizedBox(
                          height: EditorMetrics.formatBar,
                          child: _formatBar(colors),
                        ),
                        Container(height: 1, color: colors.separator),
                      ],
                      if (_findShown) ...[
                        SizedBox(
                          height: EditorMetrics.findBar,
                          child: _findBar(colors),
                        ),
                        Container(height: 1, color: colors.separator),
                      ],
                      Expanded(child: _text(colors)),
                      if (!_c.rich) _statusBar(colors),
                    ],
                  ),
                ),
                if (_settingsSheet)
                  Positioned.fill(
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: AbsorbPointer(child: AmalfiSheetScrim()),
                        ),
                        Center(
                          child: SizedBox(
                            width: settingsSize.width,
                            height: settingsSize.height + 56,
                            child: SettingsView(
                              settings: _settings,
                              onClose: () =>
                                  setState(() => _settingsSheet = false),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_alert case final alert?)
                  Positioned.fill(child: _alertView(alert)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(EditorColors colors) => WindowDragArea(
    child: AmalfiToolbar(
      key: const ValueKey('toolbar'),
      children: [
        const SizedBox(width: AmalfiToolbarPieceMetrics.controlsWidth),
        const AmalfiSpacerPiece(),
        KeyedSubtree(
          key: _titleKey,
          child: AmalfiTitlePiece(
            key: const ValueKey('title'),
            title: _title,
            subtitle: _edited ? l10n.edited : null,
            document: true,
            onDocumentMenu: _titleMenu,
          ),
        ),
        const AmalfiSpacerPiece(),
        AmalfiToolbarPiece(
          child: KeyedSubtree(
            key: _infoKey,
            child: AmalfiToolbarButton(
              key: const ValueKey('info'),
              semanticLabel: l10n.documentInfo,
              icon: AmalfiSymbol('info'),
              onPressed: showInfo,
            ),
          ),
        ),
        if (_shareable)
          AmalfiToolbarPiece(
            child: KeyedSubtree(
              key: _shareKey,
              child: AmalfiToolbarButton(
                key: const ValueKey('share'),
                semanticLabel: l10n.share,
                icon: const AmalfiGlyph(AmalfiGlyphs.share),
                onPressed: () => unawaited(_openShare()),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _formatBar(EditorColors colors) {
    final style = _c.currentStyle;
    final look = _c.look;
    final font = style.font ?? look?.font ?? _settings.richFont;
    final size = style.size ?? look?.size ?? _settings.richSize;
    final fonts = fontFamilies(
      extra: [
        font,
        for (final r in _c.doc.runs)
          if (r.style.font != null) r.style.font!,
      ],
    );
    final sizes = {...EditorMetrics.sizes, size}.toList()..sort();
    String sizeLabel(double s) =>
        s == s.roundToDouble() ? '${s.round()}' : s.toStringAsFixed(1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: EditorMetrics.formatBarPadding,
      ),
      child: Row(
        spacing: EditorMetrics.formatGap,
        children: [
          AmalfiPopUpButton<ParaPreset>(
            key: const ValueKey('preset'),
            width: EditorMetrics.popupWidth,
            semanticLabel: l10n.paragraphStyle,
            placeholder: l10n.presetOther,
            value: _c.currentPreset,
            items: [
              for (final (p, label) in [
                (ParaPreset.title, l10n.presetTitle),
                (ParaPreset.heading, l10n.presetHeading),
                (ParaPreset.subheading, l10n.presetSubheading),
                (ParaPreset.body, l10n.presetBody),
                (ParaPreset.mono, l10n.presetMono),
              ])
                AmalfiPopUpItem(value: p, label: label),
            ],
            onChanged: setPreset,
          ),
          AmalfiPopUpButton<String>(
            key: const ValueKey('font'),
            width: EditorMetrics.popupWidth,
            semanticLabel: l10n.font,
            value: font,
            items: [for (final f in fonts) AmalfiPopUpItem(value: f, label: f)],
            onChanged: (f) {
              _c.setFont(f);
              _textFocus.requestFocus();
            },
          ),
          AmalfiPopUpButton<double>(
            key: const ValueKey('size'),
            width: EditorMetrics.popupWidth,
            semanticLabel: l10n.fontSize,
            value: size,
            items: [
              for (final s in sizes)
                AmalfiPopUpItem(value: s, label: sizeLabel(s)),
            ],
            onChanged: (s) {
              _c.setSize(s);
              _textFocus.requestFocus();
            },
          ),
          AmalfiColorWell(
            key: const ValueKey('colour'),
            style: AmalfiColorWellStyle.minimal,
            color: style.color == null ? colors.text : Color(style.color!),
            semanticLabel: l10n.textColour,
            panelTitle: l10n.textColour,
            onChanged: (c) => _c.setColor(c.toARGB32()),
          ),
          AmalfiActionSegments(
            key: const ValueKey('text style'),
            size: AmalfiControlSize.regular,
            segments: [
              AmalfiSegment.icon(
                AmalfiSymbol('text-bold'),
                semanticLabel: l10n.bold,
                tooltip: l10n.bold,
              ),
              AmalfiSegment.icon(
                AmalfiSymbol('text-italic'),
                semanticLabel: l10n.italic,
                tooltip: l10n.italic,
              ),
              AmalfiSegment.icon(
                AmalfiSymbol('text-underline'),
                semanticLabel: l10n.underline,
                tooltip: l10n.underline,
              ),
            ],
            selected: {
              if (style.bold) 0,
              if (style.italic) 1,
              if (style.underline) 2,
            },
            onPressed: (i) => toggleTrait(switch (i) {
              0 => Trait.bold,
              1 => Trait.italic,
              _ => Trait.underline,
            }),
          ),
          AmalfiActionSegments(
            key: const ValueKey('lists'),
            size: AmalfiControlSize.regular,
            segments: [
              AmalfiSegment.icon(
                const AmalfiGlyph(AmalfiGlyphs.listBullet),
                semanticLabel: l10n.bulletedList,
                tooltip: l10n.bulletedList,
              ),
              AmalfiSegment.icon(
                Transform.flip(flipX: true, child: AmalfiSymbol('indent')),
                semanticLabel: l10n.decreaseIndent,
                tooltip: l10n.decreaseIndent,
              ),
              AmalfiSegment.icon(
                AmalfiSymbol('indent'),
                semanticLabel: l10n.increaseIndent,
                tooltip: l10n.increaseIndent,
              ),
            ],
            selected: {if (_c.inList) 0},
            onPressed: (i) => switch (i) {
              0 => toggleList(),
              1 => indent(-1),
              _ => indent(1),
            },
          ),
        ],
      ),
    );
  }

  Widget _findBar(EditorColors colors) {
    final count = _c.matchCount;
    final current = _c.currentMatch;
    final status = _c.findText.isEmpty
        ? ''
        : count == 0
        ? l10n.notFound
        : current >= 0
        ? l10n.matchOf(current + 1, count)
        : l10n.matches(count);
    final wide =
        MediaQuery.sizeOf(context).width >= EditorMetrics.replaceAllButtonWidth;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): hideFind},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          spacing: 12,
          children: [
            AmalfiSearchField(
              key: const ValueKey('find field'),
              controller: _find,
              focusNode: _findFocus,
              width: EditorMetrics.findField,
              placeholder: l10n.find,
              semanticLabel: l10n.find,
              clearLabel: l10n.clear,
              onSubmitted: (_) {
                findNext();
                _findFocus.requestFocus();
              },
              onCleared: () => _c.setFind(''),
            ),
            AmalfiTextField(
              key: const ValueKey('replace field'),
              controller: _replace,
              focusNode: _replaceFocus,
              width: EditorMetrics.replaceField,
              placeholder: l10n.replace,
              semanticLabel: l10n.replace,
              onSubmitted: (_) {
                _c.replaceCurrent(_replace.text);
                _replaceFocus.requestFocus();
              },
            ),
            AmalfiCheckbox(
              key: const ValueKey('match case'),
              value: _c.matchCase,
              label: l10n.matchCase,
              onChanged: (v) => _c.setFind(_find.text, matchCase: v),
            ),
            Expanded(
              child: Text(
                status,
                key: const ValueKey('find status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AmalfiType.callout(color: colors.secondary),
              ),
            ),
            if (wide)
              AmalfiPushButton(
                key: const ValueKey('replace all'),
                label: l10n.replaceAll,
                onPressed: count == 0 ? null : replaceAll,
              ),
            AmalfiActionSegments(
              key: const ValueKey('find nav'),
              size: AmalfiControlSize.regular,
              segments: [
                AmalfiSegment.icon(
                  const AmalfiGlyph(AmalfiGlyphs.chevronLeft),
                  semanticLabel: l10n.findPrevious,
                  tooltip: l10n.findPrevious,
                  enabled: count > 0,
                ),
                AmalfiSegment.icon(
                  const AmalfiGlyph(AmalfiGlyphs.chevronRight),
                  semanticLabel: l10n.findNext,
                  tooltip: l10n.findNext,
                  enabled: count > 0,
                ),
              ],
              onPressed: (i) => findNext(backwards: i == 0),
            ),
            AmalfiPushButton(
              key: const ValueKey('find done'),
              label: l10n.done,
              onPressed: hideFind,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBar(EditorColors colors) {
    final (line, column) = _c.lineColumn;
    return Container(
      key: const ValueKey('status bar'),
      height: EditorMetrics.statusBar,
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(top: BorderSide(color: colors.separator)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Text(
        l10n.statusLine(
          l10n.formatPlain,
          _encodingName(_doc.encoding),
          line,
          column,
        ),
        key: const ValueKey('status'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AmalfiType.caption(color: colors.secondary),
      ),
    );
  }

  Widget _text(EditorColors colors) {
    final rich = _c.rich;
    // Rich text keeps the defaults it was opened or made with (they are written to RTF).
    final defaultFont = rich ? _doc.defaults.font : monoFont;
    final defaultSize = rich ? _doc.defaults.size : _settings.plainSize;
    _c.look = DocLook(
      font: defaultFont,
      size: defaultSize,
      package: bundledFonts.contains(defaultFont) ? 'silica_ui' : null,
      text: colors.text,
      match: colors.match,
      currentMatch: colors.currentMatch,
      zoom: _zoom,
    );
    final base = _c.styleOf(CharStyle.plain);
    final editable = EditableText(
      key: _editable,
      controller: _c,
      focusNode: _textFocus,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: null,
      style: base,
      strutStyle: StrutStyle.disabled,
      cursorColor: colors.accent,
      cursorWidth: 2,
      cursorOpacityAnimates: true,
      showCursor: widget.active && _appActive,
      backgroundCursorColor: colors.tertiary,
      selectionColor: AmalfiTheme.of(context).selectionColor,
      rendererIgnoresPointer: true,
      enableInteractiveSelection: true,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
    );
    final field = Actions(
      actions: {
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (i) {
            unawaited(_c.copy(cut: i.collapseSelection));
            return null;
          },
        ),
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            unawaited(_c.paste());
            return null;
          },
        ),
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            _c.undo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            _c.redo();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: const {
          // Tab is text here, not a move to the next control.
          SingleActivator(LogicalKeyboardKey.tab): _InsertTabIntent(),
        },
        child: Actions(
          actions: {
            _InsertTabIntent: CallbackAction<_InsertTabIntent>(
              onInvoke: (_) {
                _c.insertText('\t');
                return null;
              },
            ),
          },
          child: MouseRegion(
            key: const ValueKey('text area'),
            cursor: SystemMouseCursors.text,
            child: Listener(
              onPointerDown: (e) {
                if (e.buttons == kSecondaryButton) {
                  unawaited(_contextMenu(e.position));
                }
              },
              child: _gestures.buildGestureDetector(
                behavior: HitTestBehavior.translucent,
                child: editable,
              ),
            ),
          ),
        ),
      ),
    );
    if (_wrapToPage) {
      final scale = _zoom;
      return ColoredBox(
        color: colors.canvas,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(EditorMetrics.pageGap),
          child: Center(
            child: Container(
              key: const ValueKey('page'),
              width: EditorMetrics.pageWidth * scale,
              constraints: BoxConstraints(
                minHeight: EditorMetrics.pageHeight * scale,
              ),
              padding: EdgeInsets.all(EditorMetrics.pageMargin * scale),
              decoration: BoxDecoration(
                color: colors.page,
                border: Border.all(color: colors.border),
              ),
              child: field,
            ),
          ),
        ),
      );
    }
    final padding = rich
        ? const EdgeInsets.fromLTRB(
            EditorMetrics.richPaddingX,
            EditorMetrics.richPaddingTop,
            EditorMetrics.richPaddingX,
            EditorMetrics.richPaddingTop,
          )
        : const EdgeInsets.all(EditorMetrics.plainPadding);
    return GestureDetector(
      // A click under the text puts the caret at the end.
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _textFocus.requestFocus();
      },
      child: SingleChildScrollView(
        controller: _scroll,
        padding: padding,
        child: field,
      ),
    );
  }

  Future<void> _contextMenu(Offset position) async {
    final sel = _c.selection;
    final has = sel.isValid && !sel.isCollapsed;
    await showAmalfiMenu(
      context: context,
      position: position,
      entries: [
        AmalfiMenuAction(
          l10n.cut,
          enabled: has,
          onSelected: () => unawaited(_c.copy(cut: true)),
        ),
        AmalfiMenuAction(
          l10n.copy,
          enabled: has,
          onSelected: () => unawaited(_c.copy()),
        ),
        AmalfiMenuAction(l10n.paste, onSelected: () => unawaited(_c.paste())),
        const AmalfiMenuDivider(),
        AmalfiMenuAction(
          l10n.selectAll,
          onSelected: () => _c.select(0, _c.text.length),
        ),
        if (_c.rich) ...[
          const AmalfiMenuDivider(),
          AmalfiMenuAction(
            l10n.bold,
            checked: _c.hasTrait(Trait.bold),
            onSelected: () => toggleTrait(Trait.bold),
          ),
          AmalfiMenuAction(
            l10n.italic,
            checked: _c.hasTrait(Trait.italic),
            onSelected: () => toggleTrait(Trait.italic),
          ),
          AmalfiMenuAction(
            l10n.underline,
            checked: _c.hasTrait(Trait.underline),
            onSelected: () => toggleTrait(Trait.underline),
          ),
        ],
      ],
    );
  }

  Widget _alertView(_Alert alert) => Stack(
    children: [
      const Positioned.fill(child: AbsorbPointer(child: AmalfiSheetScrim())),
      Center(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              for (final b in alert.buttons) {
                if (b.role == AlertRole.cancel) return b.onPressed();
              }
              if (alert.buttons.length == 1) alert.buttons.first.onPressed();
            },
            const SingleActivator(LogicalKeyboardKey.enter): () {
              for (final b in alert.buttons) {
                if (b.role == AlertRole.primary) return b.onPressed();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: SizedBox(
              width: AmalfiAlertMetrics.width,
              child: AmalfiAlert(
                key: const ValueKey('alert'),
                icon: Image.asset(
                  'icon/icon.png',
                  width: 56,
                  height: 56,
                  cacheWidth: 112,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) =>
                      const SizedBox(width: 56, height: 56),
                ),
                title: alert.title,
                message: alert.message,
                critical: alert.buttons.any(
                  (b) => b.role == AlertRole.destructive,
                ),
                actions: [
                  for (final b in alert.buttons)
                    KeyedSubtree(
                      key: ValueKey('alert ${b.label}'),
                      child: AmalfiPushButton(
                        label: b.label,
                        onPressed: b.onPressed,
                        variant: switch (b.role) {
                          AlertRole.primary => AmalfiPushButtonVariant.primary,
                          AlertRole.destructive =>
                            AmalfiPushButtonVariant.destructive,
                          _ => AmalfiPushButtonVariant.secondary,
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _InsertTabIntent extends Intent {
  const _InsertTabIntent();
}

/// The text's selection gestures (click, double click for a word, drag).
class _Gestures extends TextSelectionGestureDetectorBuilder {
  _Gestures(EditorWindowState state) : super(delegate: _GestureDelegate(state));
}

class _GestureDelegate implements TextSelectionGestureDetectorBuilderDelegate {
  _GestureDelegate(this.state);
  final EditorWindowState state;

  @override
  GlobalKey<EditableTextState> get editableTextKey => state._editable;

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;
}

/// The title popover: the name (Return renames the file) and the folder.
class _TitlePopover extends StatefulWidget {
  const _TitlePopover({
    required this.path,
    required this.onRename,
    required this.close,
  });

  final String path;
  final ValueChanged<String> onRename;
  final VoidCallback close;

  @override
  State<_TitlePopover> createState() => _TitlePopoverState();
}

class _TitlePopoverState extends State<_TitlePopover> {
  late final TextEditingController _name = TextEditingController(
    text: baseName(widget.path),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final name = _name.text;
    final dot = name.lastIndexOf('.');
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : name.length,
    );
  }

  @override
  void dispose() {
    _commit();
    _name.dispose();
    super.dispose();
  }

  void _commit() {
    if (_done) return;
    _done = true;
    final name = _name.text.trim();
    if (name.isEmpty || name == baseName(widget.path) || name.contains('/')) {
      return;
    }
    final rename = widget.onRename;
    Future.microtask(() => rename(name));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = EditorColors.of(context);
    final slash = widget.path.lastIndexOf('/');
    final folder = slash <= 0 ? '/' : widget.path.substring(0, slash);
    Widget row(String label, Widget child) => Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: AmalfiType.body(color: colors.secondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
    return Column(
      key: const ValueKey('title popover'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        row(
          l.nameLabel,
          Align(
            alignment: Alignment.centerLeft,
            child: AmalfiTextField(
              key: const ValueKey('rename field'),
              controller: _name,
              autofocus: true,
              width: EditorMetrics.titlePopoverWidth - 32 - 84,
              semanticLabel: l.nameLabel,
              onSubmitted: (_) {
                _commit();
                widget.close();
              },
            ),
          ),
        ),
        row(
          l.whereLabel,
          Text(
            folder,
            key: const ValueKey('where'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AmalfiType.body(color: colors.text),
          ),
        ),
      ],
    );
  }
}
