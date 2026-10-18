// The Open and Save dialogs through xdg-desktop-portal (`org.freedesktop.portal.FileChooser`),
// which Silica answers with its own backend (silica-desktop docs/portal.md: Mustache in dialog
// mode). The bus is reached through the embedder's `silica/dbus` channel, as the other Silica
// apps do. The portal replies to a call with a request object; the chosen files arrive later in
// that object's `Response` signal (0 chosen, 1 cancelled, 2 failed). The window asking is the
// dialog's `parent_window` ("wayland:<handle>", exported by the embedder): the dialog opens
// over it, stays above it and gives it the focus back when it closes.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:silica_ui/silica_ui.dart';

import 'external.dart';

/// The dialogs could not be shown (no portal, outside Silica, under tests).
class FileDialogUnavailable implements Exception {
  const FileDialogUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'FileDialogUnavailable($reason)';
}

/// The Open and Save dialogs.
abstract class FileDialogs {
  /// The chosen files; null if cancelled. Throws [FileDialogUnavailable].
  Future<List<String>?> open({required String title, bool multiple = true});

  /// The chosen path for a new file named `name` at first; null if cancelled. Throws
  /// [FileDialogUnavailable].
  Future<String?> save({required String title, required String name});
}

const MethodChannel _dbus = MethodChannel('silica/dbus', JSONMethodCodec());

const String _portal = 'org.freedesktop.portal.Desktop';
const String _portalPath = '/org/freedesktop/portal/desktop';
const String _chooser = 'org.freedesktop.portal.FileChooser';
const String _request = 'org.freedesktop.portal.Request';

/// The dialogs of the desktop portal.
class PortalFileDialogs implements FileDialogs {
  PortalFileDialogs({
    MethodChannel? channel,
    Future<String?> Function()? parentWindow,
  }) : _channel = channel ?? _dbus,
       _parentWindow = parentWindow ?? SilicaWindow.exportHandle,
       _mocked = channel != null;

  final MethodChannel _channel;

  /// The app window's identifier for the portal (`wayland:<handle>`); null without one.
  final Future<String?> Function() _parentWindow;

  /// A channel given by a test (mocked): the guard against real dialogs does not apply.
  final bool _mocked;
  int _tokens = 0;
  int? _subscription;
  bool _listening = false;

  /// Requests waiting for their `Response`, by object path.
  final Map<String, Completer<(int, Map<Object?, Object?>)>> _waiting = {};

  /// Responses that arrived before their request's path was known.
  final Map<String, (int, Map<Object?, Object?>)> _early = {};

  @override
  Future<List<String>?> open({
    required String title,
    bool multiple = true,
  }) async {
    final uris = await _ask('OpenFile', title, {'multiple': multiple});
    return uris == null ? null : _paths(uris);
  }

  @override
  Future<String?> save({required String title, required String name}) async {
    final uris = await _ask('SaveFile', title, {'current_name': name});
    if (uris == null) return null;
    final paths = _paths(uris);
    return paths.isEmpty ? null : paths.first;
  }

  static List<String> _paths(List<String> uris) => [
    for (final u in uris)
      if (Uri.tryParse(u) case final uri? when uri.scheme == 'file')
        uri.toFilePath(),
  ];

  Future<List<String>?> _ask(
    String method,
    String title,
    Map<String, Object?> options,
  ) async {
    if (startsNothing && !_mocked) {
      throw const FileDialogUnavailable('no dialogs under flutter test');
    }
    try {
      await _listen();
      final parent = await _parentWindow() ?? '';
      final token = 'texteditor${++_tokens}';
      final reply = await _channel.invokeMethod<Object?>('call', {
        'bus': 'session',
        'destination': _portal,
        'path': _portalPath,
        'interface': _chooser,
        'method': method,
        'signature': 'ssa{sv}',
        'args': [
          parent,
          title,
          {'handle_token': token, 'modal': true, ...options},
        ],
      });
      final handle = reply is List && reply.isNotEmpty ? '${reply.first}' : '';
      if (handle.isEmpty) throw const FileDialogUnavailable('no request');
      final (code, results) = _early.remove(handle) ?? await _wait(handle);
      if (code == 1) return null;
      if (code != 0) throw FileDialogUnavailable('portal response $code');
      final uris = results['uris'];
      return uris is List ? [for (final u in uris) '$u'] : const [];
    } on MissingPluginException {
      throw const FileDialogUnavailable('outside Silica');
    } on PlatformException catch (e) {
      throw FileDialogUnavailable(e.code);
    }
  }

  Future<(int, Map<Object?, Object?>)> _wait(String handle) {
    final done = Completer<(int, Map<Object?, Object?>)>();
    _waiting[handle] = done;
    return done.future;
  }

  Future<void> _listen() async {
    if (_listening) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'signal') return null;
      final a = call.arguments;
      if (a is! Map || a['id'] != _subscription) return null;
      if (a['member'] != 'Response') return null;
      final path = '${a['path']}';
      final args = a['args'];
      final code = args is List && args.isNotEmpty && args.first is int
          ? args.first as int
          : 2;
      final results = args is List && args.length > 1 && args[1] is Map
          ? args[1] as Map<Object?, Object?>
          : const <Object?, Object?>{};
      final waiting = _waiting.remove(path);
      if (waiting != null) {
        waiting.complete((code, results));
      } else {
        _early[path] = (code, results);
      }
      return null;
    });
    final id = await _channel.invokeMethod<Object?>('subscribe', {
      'bus': 'session',
      'interface': _request,
      'member': 'Response',
    });
    if (id is int) _subscription = id;
    _listening = true;
  }
}
