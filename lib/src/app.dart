// The app: the language, the documents and their windows, the menu bar.
//
// Every document has a window: the main one, then windows of their own (Silica's
// multi-window). Open replaces an untitled document nobody typed in. Closing a window asks
// to save what has no file yet (documents with a file save by themselves, Settings › Save
// changes automatically); the app keeps running with no window, and File › New or Open shows
// the main window again. A second launch with files opens them (Open With).

import 'dart:async';
import 'dart:ui' show AppExitResponse, Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:silica_ui/silica_ui.dart';

import '../l10n/app_localizations.dart';
import 'args.dart';
import 'menus.dart';
import 'model/document.dart';
import 'portal.dart';
import 'recent.dart';
import 'settings.dart';
import 'style.dart';
import 'ui/settings_view.dart';
import 'ui/window.dart';

Locale resolveLocale(List<Locale> preferred) =>
    basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);

class TextEditorApp extends StatefulWidget {
  const TextEditorApp({
    super.key,
    required this.settings,
    required this.dialogs,
    this.files = const [],
    this.locale,
  });

  final EditorSettings settings;
  final FileDialogs dialogs;

  /// The files from the command line.
  final List<String> files;

  /// A fixed language (tests); null follows the system.
  final Locale? locale;

  @override
  State<TextEditorApp> createState() => EditorAppState();
}

/// A document in a window of its own.
class _Extra {
  _Extra(this.document, this.key);
  final TextDocument document;
  final GlobalKey<EditorWindowState> key;
  SilicaWindowController? window;
}

class EditorAppState extends State<TextEditorApp>
    with WidgetsBindingObserver
    implements EditorHost {
  late Locale _locale =
      widget.locale ?? resolveLocale(PlatformDispatcher.instance.locales);
  bool _active = _isActive(WidgetsBinding.instance.lifecycleState);
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (s) => setState(() => _active = _isActive(s)),
    onExitRequested: _exitRequested,
  );

  static bool _isActive(AppLifecycleState? s) =>
      s == null || s == AppLifecycleState.resumed;

  final GlobalKey<EditorWindowState> _mainKey = GlobalKey();
  final ValueNotifier<TextDocument?> _mainDoc = ValueNotifier(null);
  TextDocument? get _main => _mainDoc.value;
  set _main(TextDocument? doc) => _mainDoc.value = doc;
  bool _mainConfirmed = false;
  final List<_Extra> _extras = [];
  EditorWindowState? _activeWindow;
  final ValueNotifier<List<PlatformMenuItem>?> _menus = ValueNotifier(null);
  SilicaWindowController? _settingsWindow;

  /// Untitled numbers in use.
  final Set<int> _untitled = {};

  /// The documents open now (tests).
  List<TextDocument> get documents => [
    ?_main,
    for (final e in _extras) e.document,
  ];

  /// The main window's state (tests).
  EditorWindowState? get mainWindow => _mainKey.currentState;

  @override
  EditorSettings get settings => widget.settings;

  @override
  FileDialogs get dialogs => widget.dialogs;

  AppLocalizations? get _l10n => _mainKey.currentContext == null
      ? null
      : AppLocalizations.of(_mainKey.currentContext!);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle;
    unawaited(initializeDateFormatting());
    SilicaApp.onOpen = (args) => openPaths(filesFromArgs(args));
    SilicaWindows.onMainCloseRequested = _mainCloseRequested;
    _main = _newDocument();
    if (widget.files.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => openPaths(widget.files),
      );
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.locale != null || locales == null) return;
    setState(() => _locale = resolveLocale(locales));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SilicaApp.onOpen = null;
    SilicaWindows.onMainCloseRequested = null;
    _lifecycle.dispose();
    _menus.dispose();
    _mainDoc.dispose();
    super.dispose();
  }

  TextDocument _newDocument() {
    var n = 1;
    while (_untitled.contains(n)) {
      n++;
    }
    _untitled.add(n);
    return TextDocument.untitled(
      format: settings.newFormat,
      defaults: settings.richDefaults,
      number: n,
    );
  }

  void _release(TextDocument doc) {
    if (doc.isUntitled) _untitled.remove(doc.untitledNumber);
    doc.dispose();
  }

  // MARK: windows

  Future<bool> _mainCloseRequested() async {
    if (_mainConfirmed) {
      _mainConfirmed = false;
      _mainClosed();
      return true;
    }
    final ok = await _mainKey.currentState?.confirmClose() ?? true;
    if (ok) _mainClosed();
    return ok;
  }

  void _mainClosed() {
    final doc = _main;
    if (doc == null) return;
    _main = null;
    if (_activeWindow == _mainKey.currentState) _activeWindow = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _release(doc));
    _publishFor(_activeWindow);
  }

  /// Shows [doc]: in the main window when it is closed or holds a blank document, else in a
  /// window of its own.
  Future<void> _show(TextDocument doc) async {
    final main = _main;
    if (main == null) {
      _main = doc;
      unawaited(SilicaApp.openWindow());
      return;
    }
    if (main.isBlank) {
      _main = doc;
      WidgetsBinding.instance.addPostFrameCallback((_) => _release(main));
      return;
    }
    final extra = _Extra(doc, GlobalKey<EditorWindowState>());
    final window = await SilicaWindows.openWindow(
      title: doc.path == null ? '' : baseName(doc.path!),
      size: EditorMetrics.defaultWindow,
      minSize: EditorMetrics.minimumWindow,
      toolbarHeight: EditorMetrics.toolbar,
      builder: (context) => Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => EditorWindow(
              key: extra.key,
              document: doc,
              host: this,
              active: _active,
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (window == null) {
      // No windows of their own here: the main window takes the document once its own is
      // saved or given up.
      final ok = await _mainKey.currentState?.confirmClose() ?? true;
      if (!mounted) return;
      if (!ok) {
        _release(doc);
        return;
      }
      final old = _main;
      _main = doc;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _release(old));
      }
      return;
    }
    extra.window = window;
    window.onCloseRequested = () async {
      final state = extra.key.currentState;
      if (state == null) return true;
      return state.confirmClose();
    };
    _extras.add(extra);
    unawaited(
      window.closed.then((_) {
        if (!mounted) return;
        _extras.remove(extra);
        if (_activeWindow == extra.key.currentState) _activeWindow = null;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _release(extra.document),
        );
        _publishFor(_activeWindow);
      }),
    );
    setState(() {});
  }

  @override
  void closeWindow(EditorWindowState window) {
    if (window == _mainKey.currentState) {
      _mainConfirmed = true;
      unawaited(SilicaApp.closeWindow());
      // When the close does not come back through onMainCloseRequested (outside Silica),
      // the window gives up its document anyway.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (_mainConfirmed && mounted) {
          _mainConfirmed = false;
          _mainClosed();
        }
      });
      return;
    }
    for (final e in _extras) {
      if (e.key.currentState == window) {
        e.window?.onCloseRequested = null;
        unawaited(e.window?.close());
      }
    }
  }

  // MARK: EditorHost

  @override
  void newDocument() => unawaited(_show(_newDocument()));

  @override
  Future<void> openDialog() async {
    final l = _l10n;
    List<String>? files;
    try {
      files = await dialogs.open(title: l?.open ?? 'Open');
    } on FileDialogUnavailable {
      return;
    }
    if (files == null || files.isEmpty || !mounted) return;
    openPaths(files);
  }

  @override
  void openPaths(List<String> paths) {
    for (final path in paths) {
      final open = documents.where((d) => d.path == path).firstOrNull;
      if (open != null) continue;
      try {
        final doc = TextDocument.open(
          path,
          defaults: settings.richDefaults,
          encoding: settings.openEncoding,
        );
        RecentFiles.add(path);
        unawaited(_show(doc));
      } on OpenFailure catch (e) {
        final window = _activeWindow ?? _mainKey.currentState;
        window?.showOpenFailure(e);
      }
    }
  }

  @override
  void duplicate(TextDocument doc) {
    final copy = _newDocument();
    copy.controller.load(doc.controller.doc, rich: doc.controller.rich);
    unawaited(_show(copy));
  }

  @override
  void showSettings() => unawaited(_openSettings());

  Future<void> _openSettings() async {
    if (_settingsWindow?.isOpen ?? false) return;
    final l = _l10n;
    final window = await SilicaWindows.openWindow(
      title: l?.settingsTitle ?? 'Settings',
      size: settingsSize,
      minSize: settingsSize,
      maxSize: settingsSize,
      builder: (context) => Overlay(
        initialEntries: [
          OverlayEntry(builder: (context) => SettingsView(settings: settings)),
        ],
      ),
    );
    if (!mounted) return;
    if (window == null) {
      (_activeWindow ?? _mainKey.currentState)?.showSettingsSheet();
      return;
    }
    _settingsWindow = window;
    unawaited(window.closed.then((_) => _settingsWindow = null));
  }

  @override
  void focusWindow(EditorWindowState window) {
    if (_activeWindow == window) return;
    _activeWindow = window;
    _publishFor(window);
  }

  final Map<EditorWindowState, List<PlatformMenuItem>> _published = {};

  @override
  void publishMenus(EditorWindowState window, List<PlatformMenuItem> menus) {
    _published[window] = menus;
    final active = _activeWindow ?? _mainKey.currentState;
    if (active == null || active == window) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _menus.value = menus;
      });
    }
  }

  void _publishFor(EditorWindowState? window) {
    _published.removeWhere((w, _) => !w.mounted);
    final menus = window == null ? null : _published[window];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menus.value = menus;
    });
  }

  Future<AppExitResponse> _exitRequested() async {
    final windows = [
      ?_mainKey.currentState,
      for (final e in _extras) ?e.key.currentState,
    ];
    for (final w in windows) {
      if (!await w.confirmClose()) return AppExitResponse.cancel;
    }
    return AppExitResponse.exit;
  }

  // MARK: build

  @override
  Widget build(BuildContext context) => Localizations(
    locale: _locale,
    delegates: const [
      AppLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    child: DefaultTextEditingShortcuts(
      child: ScrollConfiguration(
        behavior: const SilicaScrollBehavior(),
        child: AmalfiTheme(
          child: _MenuBarHost(
            menus: _menus,
            host: this,
            child: SilicaWindowHost(
              child: Builder(
                builder: (context) => ColoredBox(
                  color: EditorColors.of(context).window,
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (context) => SilicaAppWindow(
                          onReopen: () async {
                            _main ??= _newDocument();
                          },
                          builder: (context) => _MainWindow(app: this),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The main window: built again when its document changes (Open over a blank document,
/// a reopen after it closed).
class _MainWindow extends StatelessWidget {
  const _MainWindow({required this.app});
  final EditorAppState app;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextDocument?>(
    valueListenable: app._mainDoc,
    builder: (context, doc, _) => doc == null
        ? const SizedBox.shrink()
        : EditorWindow(
            key: app._mainKey,
            document: doc,
            host: app,
            active: app._active,
          ),
  );
}

/// The menu bar: the active window's menus, or the app's with no window.
class _MenuBarHost extends StatelessWidget {
  const _MenuBarHost({
    required this.menus,
    required this.host,
    required this.child,
  });

  final ValueListenable<List<PlatformMenuItem>?> menus;
  final EditorHost host;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<List<PlatformMenuItem>?>(
        valueListenable: menus,
        builder: (context, value, child) => SilicaMenuBar(
          menus: value ?? appMenus(AppLocalizations.of(context), host),
          // Each window binds the shortcuts of its own menus.
          shortcuts: value == null,
          child: child!,
        ),
        child: child,
      );
}
