import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @actualSize.
  ///
  /// In en, this message translates to:
  /// **'Actual Size'**
  String get actualSize;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Text Editor'**
  String get appTitle;

  /// No description provided for @bigger.
  ///
  /// In en, this message translates to:
  /// **'Bigger'**
  String get bigger;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @bulletedList.
  ///
  /// In en, this message translates to:
  /// **'Bulleted List'**
  String get bulletedList;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @changedOnDiskMessage.
  ///
  /// In en, this message translates to:
  /// **'Another app changed the file since you opened it. Saving replaces its changes.'**
  String get changedOnDiskMessage;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearMenu.
  ///
  /// In en, this message translates to:
  /// **'Clear Menu'**
  String get clearMenu;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @decreaseIndent.
  ///
  /// In en, this message translates to:
  /// **'Decrease Indent'**
  String get decreaseIndent;

  /// No description provided for @documentInfo.
  ///
  /// In en, this message translates to:
  /// **'Document Info'**
  String get documentInfo;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @dontSave.
  ///
  /// In en, this message translates to:
  /// **'Don’t Save'**
  String get dontSave;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @edited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get edited;

  /// No description provided for @encodingAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get encodingAutomatic;

  /// No description provided for @encodingLatin1.
  ///
  /// In en, this message translates to:
  /// **'Western (ISO Latin 1)'**
  String get encodingLatin1;

  /// No description provided for @encodingUtf16be.
  ///
  /// In en, this message translates to:
  /// **'Unicode (UTF-16 Big Endian)'**
  String get encodingUtf16be;

  /// No description provided for @encodingUtf16le.
  ///
  /// In en, this message translates to:
  /// **'Unicode (UTF-16 Little Endian)'**
  String get encodingUtf16le;

  /// No description provided for @encodingUtf8.
  ///
  /// In en, this message translates to:
  /// **'Unicode (UTF-8)'**
  String get encodingUtf8;

  /// No description provided for @find.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get find;

  /// No description provided for @findAndReplaceEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Find and Replace…'**
  String get findAndReplaceEllipsis;

  /// No description provided for @findEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Find…'**
  String get findEllipsis;

  /// No description provided for @findNext.
  ///
  /// In en, this message translates to:
  /// **'Find Next'**
  String get findNext;

  /// No description provided for @findPrevious.
  ///
  /// In en, this message translates to:
  /// **'Find Previous'**
  String get findPrevious;

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get fontSize;

  /// No description provided for @formatPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain text'**
  String get formatPlain;

  /// No description provided for @formatRich.
  ///
  /// In en, this message translates to:
  /// **'Rich text (RTF)'**
  String get formatRich;

  /// No description provided for @increaseIndent.
  ///
  /// In en, this message translates to:
  /// **'Increase Indent'**
  String get increaseIndent;

  /// No description provided for @infoCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get infoCharacters;

  /// No description provided for @infoEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get infoEncoding;

  /// No description provided for @infoFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get infoFormat;

  /// No description provided for @infoModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get infoModified;

  /// No description provided for @infoPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get infoPages;

  /// No description provided for @infoParagraphs.
  ///
  /// In en, this message translates to:
  /// **'Paragraphs'**
  String get infoParagraphs;

  /// No description provided for @infoSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get infoSize;

  /// No description provided for @infoWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get infoWords;

  /// No description provided for @italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// No description provided for @lastOpenedVersion.
  ///
  /// In en, this message translates to:
  /// **'Last Opened Version'**
  String get lastOpenedVersion;

  /// No description provided for @lastSavedVersion.
  ///
  /// In en, this message translates to:
  /// **'Last Saved Version'**
  String get lastSavedVersion;

  /// No description provided for @makePlainMessage.
  ///
  /// In en, this message translates to:
  /// **'Bold, italic, fonts, sizes and colours are removed.'**
  String get makePlainMessage;

  /// No description provided for @makePlainText.
  ///
  /// In en, this message translates to:
  /// **'Make Plain Text'**
  String get makePlainText;

  /// No description provided for @makePlainTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert this document to plain text?'**
  String get makePlainTitle;

  /// No description provided for @makeRichText.
  ///
  /// In en, this message translates to:
  /// **'Make Rich Text'**
  String get makeRichText;

  /// No description provided for @matchCase.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get matchCase;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get menuFind;

  /// No description provided for @menuFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get menuFont;

  /// No description provided for @menuFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get menuFormat;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @menuLists.
  ///
  /// In en, this message translates to:
  /// **'Lists'**
  String get menuLists;

  /// No description provided for @menuStyle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get menuStyle;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name:'**
  String get nameLabel;

  /// No description provided for @newDocument.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newDocument;

  /// No description provided for @noFileDialog.
  ///
  /// In en, this message translates to:
  /// **'The file dialog isn’t available.'**
  String get noFileDialog;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get notFound;

  /// No description provided for @numberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered List'**
  String get numberedList;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @openDirectory.
  ///
  /// In en, this message translates to:
  /// **'It is a folder.'**
  String get openDirectory;

  /// No description provided for @openEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Open…'**
  String get openEllipsis;

  /// No description provided for @openMissing.
  ///
  /// In en, this message translates to:
  /// **'The file doesn’t exist.'**
  String get openMissing;

  /// No description provided for @openNotText.
  ///
  /// In en, this message translates to:
  /// **'The file isn’t text.'**
  String get openNotText;

  /// No description provided for @openRecent.
  ///
  /// In en, this message translates to:
  /// **'Open Recent'**
  String get openRecent;

  /// No description provided for @openUnreadable.
  ///
  /// In en, this message translates to:
  /// **'You don’t have permission to read it.'**
  String get openUnreadable;

  /// No description provided for @paragraphStyle.
  ///
  /// In en, this message translates to:
  /// **'Paragraph style'**
  String get paragraphStyle;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @presetBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get presetBody;

  /// No description provided for @presetHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get presetHeading;

  /// No description provided for @presetMono.
  ///
  /// In en, this message translates to:
  /// **'Monospaced'**
  String get presetMono;

  /// No description provided for @presetOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get presetOther;

  /// No description provided for @presetSubheading.
  ///
  /// In en, this message translates to:
  /// **'Subheading'**
  String get presetSubheading;

  /// No description provided for @presetTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get presetTitle;

  /// No description provided for @renameEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get renameEllipsis;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @reopenMessage.
  ///
  /// In en, this message translates to:
  /// **'Your changes will be lost.'**
  String get reopenMessage;

  /// No description provided for @reopenTitle.
  ///
  /// In en, this message translates to:
  /// **'Reopen the document with another encoding?'**
  String get reopenTitle;

  /// No description provided for @reopenWithEncoding.
  ///
  /// In en, this message translates to:
  /// **'Reopen with Encoding'**
  String get reopenWithEncoding;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @replaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get replaceAll;

  /// No description provided for @revert.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get revert;

  /// No description provided for @revertMessage.
  ///
  /// In en, this message translates to:
  /// **'The changes since the last save will be lost.'**
  String get revertMessage;

  /// No description provided for @revertTo.
  ///
  /// In en, this message translates to:
  /// **'Revert To'**
  String get revertTo;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save Anyway'**
  String get saveAnyway;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As'**
  String get saveAs;

  /// No description provided for @saveAsEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Save As…'**
  String get saveAsEllipsis;

  /// No description provided for @saveChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'Your changes will be lost if you don’t save them.'**
  String get saveChangesMessage;

  /// No description provided for @saveEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Save…'**
  String get saveEllipsis;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @settingsAutosave.
  ///
  /// In en, this message translates to:
  /// **'Save changes automatically'**
  String get settingsAutosave;

  /// No description provided for @settingsNewFormat.
  ///
  /// In en, this message translates to:
  /// **'New documents:'**
  String get settingsNewFormat;

  /// No description provided for @settingsOpenEncoding.
  ///
  /// In en, this message translates to:
  /// **'Open plain text as:'**
  String get settingsOpenEncoding;

  /// No description provided for @settingsPlainSize.
  ///
  /// In en, this message translates to:
  /// **'Plain text size:'**
  String get settingsPlainSize;

  /// No description provided for @settingsRichFont.
  ///
  /// In en, this message translates to:
  /// **'Rich text font:'**
  String get settingsRichFont;

  /// No description provided for @settingsSaveEncoding.
  ///
  /// In en, this message translates to:
  /// **'Save new plain text as:'**
  String get settingsSaveEncoding;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @showDocumentInfo.
  ///
  /// In en, this message translates to:
  /// **'Show Document Info'**
  String get showDocumentInfo;

  /// No description provided for @smaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get smaller;

  /// No description provided for @strikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get strikethrough;

  /// No description provided for @textColour.
  ///
  /// In en, this message translates to:
  /// **'Text colour'**
  String get textColour;

  /// No description provided for @textEncoding.
  ///
  /// In en, this message translates to:
  /// **'Text Encoding'**
  String get textEncoding;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @useSelectionForFind.
  ///
  /// In en, this message translates to:
  /// **'Use Selection for Find'**
  String get useSelectionForFind;

  /// No description provided for @whereLabel.
  ///
  /// In en, this message translates to:
  /// **'Where:'**
  String get whereLabel;

  /// No description provided for @wrapToPage.
  ///
  /// In en, this message translates to:
  /// **'Wrap to Page'**
  String get wrapToPage;

  /// No description provided for @wrapToWindow.
  ///
  /// In en, this message translates to:
  /// **'Wrap to Window'**
  String get wrapToWindow;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get zoomOut;

  /// No description provided for @bytes.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String bytes(int count);

  /// No description provided for @cannotEncodeMessage.
  ///
  /// In en, this message translates to:
  /// **'“{character}” has no place in this encoding. Choose Unicode (UTF-8) to keep every character.'**
  String cannotEncodeMessage(String character);

  /// No description provided for @cannotEncodeTitle.
  ///
  /// In en, this message translates to:
  /// **'The document can’t be saved as {encoding}.'**
  String cannotEncodeTitle(String encoding);

  /// No description provided for @cannotOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'“{name}” can’t be opened.'**
  String cannotOpenTitle(String name);

  /// No description provided for @cannotRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'The document can’t be renamed “{name}”.'**
  String cannotRenameTitle(String name);

  /// No description provided for @cannotSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'“{name}” can’t be saved.'**
  String cannotSaveTitle(String name);

  /// No description provided for @changedOnDiskTitle.
  ///
  /// In en, this message translates to:
  /// **'“{name}” was changed by another app.'**
  String changedOnDiskTitle(String name);

  /// No description provided for @kilobytes.
  ///
  /// In en, this message translates to:
  /// **'{count} KB'**
  String kilobytes(String count);

  /// No description provided for @matchOf.
  ///
  /// In en, this message translates to:
  /// **'{index} of {count}'**
  String matchOf(int index, int count);

  /// No description provided for @matches.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String matches(int count);

  /// No description provided for @megabytes.
  ///
  /// In en, this message translates to:
  /// **'{count} MB'**
  String megabytes(String count);

  /// No description provided for @revertTitle.
  ///
  /// In en, this message translates to:
  /// **'Revert “{name}” to the last saved version?'**
  String revertTitle(String name);

  /// No description provided for @saveChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save the changes you made to “{name}”?'**
  String saveChangesTitle(String name);

  /// No description provided for @statusLine.
  ///
  /// In en, this message translates to:
  /// **'{format} · {encoding} · Line {line}, column {column}'**
  String statusLine(String format, String encoding, int line, int column);

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String todayAt(String time);

  /// No description provided for @untitledNumber.
  ///
  /// In en, this message translates to:
  /// **'Untitled {number}'**
  String untitledNumber(int number);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
