// Geometry and colours of the Text Editor window, in one place. Layout and colours come from
// the Amalfi kit (`App · Text Editor`, masters `Apps/Text Editor/*`); values the kit does not
// give are marked provisional.

import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

abstract final class EditorMetrics {
  /// The kit draws the window at 800 × 600.
  static const Size defaultWindow = Size(800, 600);

  /// PROVISIONAL: the smallest window: the format bar's controls up to the text styles.
  static const Size minimumWindow = Size(480, 240);

  static const double toolbar = AmalfiToolbarMetrics.toolbarHeight;

  // Format bar (kit `Apps/Text Editor/Rich Text`: 44 tall, controls 28 at y 8).
  static const double formatBar = 44;
  static const double formatBarPadding = 16;
  static const double popupWidth = 124;
  static const double formatGap = 8;

  // Find bar (kit `Apps/Text Editor/Find`: 40 tall, fields 28 at y 6).
  static const double findBar = 40;
  static const double findField = 200;
  static const double replaceField = 160;

  /// Above this window width the find bar shows Replace All as a button too.
  static const double replaceAllButtonWidth = 900;

  // Text (kit: rich text at x 48, 24 under the bars; plain text at x 20, 20 under the toolbar).
  static const double richPaddingX = 48;
  static const double richPaddingTop = 24;
  static const double plainPadding = 20;

  // Status bar (kit `Apps/Text Editor/Plain Text`: 28 tall, text at x 20).
  static const double statusBar = 28;

  /// Wrap to Page: a US Letter page (612 × 792 pt) with one-inch margins.
  static const double pageWidth = 612;
  static const double pageHeight = 792;
  static const double pageMargin = 72;
  static const double pageGap = 24;

  /// The document info popover (kit `Apps/Text Editor/Info`): 260 wide.
  static const double infoWidth = 260;

  /// The title popover (name and folder).
  static const double titlePopoverWidth = 420;

  /// Autosave: how long after the last change a document with a file is written.
  static const Duration autosaveDelay = Duration(seconds: 2);

  /// Zoom steps of View › Zoom In / Zoom Out.
  static const List<double> zoomSteps = [0.5, 0.75, 1, 1.25, 1.5, 2, 3];

  /// The sizes the Size pop-up offers.
  static const List<double> sizes = [
    9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 26, 28, 36, 48, 64, 72, //
  ];
}

@immutable
class EditorColors {
  const EditorColors._(this._c);
  final AmalfiColors _c;

  factory EditorColors.of(BuildContext context) =>
      EditorColors._(AmalfiTheme.of(context).colors);

  Color get window => _c.surfaceWindow;
  Color get bar => _c.surfaceSidebar;
  Color get canvas => _c.surfaceSunken;
  Color get page => _c.surfaceRaised;
  Color get text => _c.textPrimary;
  Color get secondary => _c.textSecondary;
  Color get tertiary => _c.textTertiary;
  Color get separator => _c.lineSeparator;
  Color get border => _c.lineBorder;
  Color get accent => _c.accentAmalfi;

  /// Find matches (kit `Apps/Text Editor/Find`: the current one `Palette/Limone`, the others
  /// `Accent/Amalfi Soft`).
  Color get match => _c.accentAmalfiSoft;
  Color get currentMatch => _c.paletteLimone;
}
