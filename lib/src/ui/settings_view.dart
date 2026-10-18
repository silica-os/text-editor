// The Settings window: the format of new documents, the default fonts, the plain text
// encodings and saving changes by themselves. Every change is kept at once.

import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import '../../l10n/app_localizations.dart';
import '../fonts.dart';
import '../menus.dart' show encodingLabel;
import '../model/document.dart';
import '../model/text_codec.dart';
import '../settings.dart';
import '../style.dart';

/// The size of the Settings window.
const Size settingsSize = Size(480, 400);

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.settings, this.onClose});

  final EditorSettings settings;

  /// Closes the view when it is shown inside a document window.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = EditorColors.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        Widget row(String label, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: Text(
                  label,
                  textAlign: TextAlign.right,
                  style: AmalfiType.body(color: colors.text),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(alignment: Alignment.centerLeft, child: control),
              ),
            ],
          ),
        );
        String size(double s) =>
            s == s.roundToDouble() ? '${s.round()}' : s.toStringAsFixed(1);
        final sizes = {
          ...EditorMetrics.sizes,
          settings.richSize,
          settings.plainSize,
        }.toList()..sort();
        AmalfiPopUpButton<TextEncoding?> encodings(
          Key key,
          String label,
          TextEncoding? value,
          ValueChanged<TextEncoding?> onChanged,
        ) => AmalfiPopUpButton<TextEncoding?>(
          key: key,
          width: 200,
          semanticLabel: label,
          value: value,
          items: [
            AmalfiPopUpItem(value: null, label: l.encodingAutomatic),
            for (final e in TextEncoding.values)
              AmalfiPopUpItem(value: e, label: encodingLabel(l, e)),
          ],
          onChanged: onChanged,
        );
        return ColoredBox(
          color: colors.window,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              key: const ValueKey('settings'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(
                  l.settingsNewFormat,
                  AmalfiPopUpButton<DocFormat>(
                    key: const ValueKey('new format'),
                    width: 200,
                    semanticLabel: l.settingsNewFormat,
                    value: settings.newFormat,
                    items: [
                      AmalfiPopUpItem(
                        value: DocFormat.rich,
                        label: l.formatRich,
                      ),
                      AmalfiPopUpItem(
                        value: DocFormat.plain,
                        label: l.formatPlain,
                      ),
                    ],
                    onChanged: (v) => settings.newFormat = v,
                  ),
                ),
                row(
                  l.settingsRichFont,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      AmalfiPopUpButton<String>(
                        key: const ValueKey('rich font'),
                        width: 160,
                        semanticLabel: l.settingsRichFont,
                        value: settings.richFont,
                        items: [
                          for (final f in fontFamilies(
                            extra: [settings.richFont],
                          ))
                            AmalfiPopUpItem(value: f, label: f),
                        ],
                        onChanged: (v) => settings.richFont = v,
                      ),
                      AmalfiPopUpButton<double>(
                        key: const ValueKey('rich size'),
                        width: 72,
                        semanticLabel: l.fontSize,
                        value: settings.richSize,
                        items: [
                          for (final s in sizes)
                            AmalfiPopUpItem(value: s, label: size(s)),
                        ],
                        onChanged: (v) => settings.richSize = v,
                      ),
                    ],
                  ),
                ),
                row(
                  l.settingsPlainSize,
                  AmalfiPopUpButton<double>(
                    key: const ValueKey('plain size'),
                    width: 72,
                    semanticLabel: l.settingsPlainSize,
                    value: settings.plainSize,
                    items: [
                      for (final s in sizes)
                        AmalfiPopUpItem(value: s, label: size(s)),
                    ],
                    onChanged: (v) => settings.plainSize = v,
                  ),
                ),
                const SizedBox(height: 12),
                row(
                  l.settingsOpenEncoding,
                  encodings(
                    const ValueKey('open encoding'),
                    l.settingsOpenEncoding,
                    settings.openEncoding,
                    (v) => settings.openEncoding = v,
                  ),
                ),
                row(
                  l.settingsSaveEncoding,
                  encodings(
                    const ValueKey('save encoding'),
                    l.settingsSaveEncoding,
                    settings.saveEncoding,
                    (v) => settings.saveEncoding = v,
                  ),
                ),
                const SizedBox(height: 12),
                row(
                  '',
                  AmalfiCheckbox(
                    key: const ValueKey('autosave'),
                    value: settings.autosave,
                    label: l.settingsAutosave,
                    onChanged: (v) => settings.autosave = v,
                  ),
                ),
                if (onClose != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AmalfiPushButton(
                        key: const ValueKey('settings done'),
                        label: l.done,
                        variant: AmalfiPushButtonVariant.primary,
                        onPressed: onClose,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
