import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

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
    Locale('hi'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'DocScanner'**
  String get appName;

  /// No description provided for @appPurpose.
  ///
  /// In en, this message translates to:
  /// **'Turn paper into clean PDFs. Works offline, no account needed.'**
  String get appPurpose;

  /// No description provided for @scanDocument.
  ///
  /// In en, this message translates to:
  /// **'Scan Document'**
  String get scanDocument;

  /// No description provided for @importPhotos.
  ///
  /// In en, this message translates to:
  /// **'Import Photos'**
  String get importPhotos;

  /// No description provided for @importPdf.
  ///
  /// In en, this message translates to:
  /// **'Import PDF'**
  String get importPdf;

  /// No description provided for @viewDocuments.
  ///
  /// In en, this message translates to:
  /// **'View Documents'**
  String get viewDocuments;

  /// No description provided for @recentScans.
  ///
  /// In en, this message translates to:
  /// **'Recent scans'**
  String get recentScans;

  /// No description provided for @seeAllDocuments.
  ///
  /// In en, this message translates to:
  /// **'See all documents'**
  String get seeAllDocuments;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @noScansYet.
  ///
  /// In en, this message translates to:
  /// **'No scans yet'**
  String get noScansYet;

  /// No description provided for @noScansHint.
  ///
  /// In en, this message translates to:
  /// **'Tap “Scan Document” to scan a page with your camera, or import photos or a PDF.'**
  String get noScansHint;

  /// No description provided for @howItWorksTitle.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get howItWorksTitle;

  /// No description provided for @howItWorksStep1.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a page. It is captured when you hold still.'**
  String get howItWorksStep1;

  /// No description provided for @howItWorksStep2.
  ///
  /// In en, this message translates to:
  /// **'Check the corners, then pick a look such as Black & White.'**
  String get howItWorksStep2;

  /// No description provided for @howItWorksStep3.
  ///
  /// In en, this message translates to:
  /// **'Save as PDF or JPG and share it.'**
  String get howItWorksStep3;

  /// No description provided for @statusLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Scans are saved on this device'**
  String get statusLocalOnly;

  /// No description provided for @statusSynced.
  ///
  /// In en, this message translates to:
  /// **'Backed up'**
  String get statusSynced;

  /// No description provided for @statusSyncing.
  ///
  /// In en, this message translates to:
  /// **'Backing up…'**
  String get statusSyncing;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Backup server not reachable. Your scans are safe on this device and will upload later.'**
  String get statusOffline;

  /// No description provided for @statusSyncError.
  ///
  /// In en, this message translates to:
  /// **'Backup problem: {message}'**
  String statusSyncError(String message);

  /// No description provided for @pendingChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change waiting to upload} other{{count} changes waiting to upload}}'**
  String pendingChanges(int count);

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @searchDocuments.
  ///
  /// In en, this message translates to:
  /// **'Search documents and text inside pages'**
  String get searchDocuments;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No documents match “{query}”.'**
  String noResults(String query);

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @pageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String pageCount(int count);

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'Modified {date}'**
  String modified(String date);

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @badgeDeviceOnly.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get badgeDeviceOnly;

  /// No description provided for @badgeBackedUp.
  ///
  /// In en, this message translates to:
  /// **'Backed up'**
  String get badgeBackedUp;

  /// No description provided for @badgeWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting to upload'**
  String get badgeWaiting;

  /// No description provided for @renameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename document'**
  String get renameTitle;

  /// No description provided for @documentName.
  ///
  /// In en, this message translates to:
  /// **'Document name'**
  String get documentName;

  /// No description provided for @deleteDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{title}”?'**
  String deleteDocumentTitle(String title);

  /// No description provided for @deleteDocumentBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Its page will be removed from this device.} other{All {count} pages will be removed from this device.}}'**
  String deleteDocumentBody(int count);

  /// No description provided for @documentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Document deleted'**
  String get documentDeleted;

  /// No description provided for @importing.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get importing;

  /// No description provided for @importProgress.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page added} other{{count} pages added}} · {name}'**
  String importProgress(int count, String name);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not import: {message}'**
  String importFailed(String message);

  /// No description provided for @importNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import. Choose JPG, PNG or PDF files.'**
  String get importNothing;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @highContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get highContrast;

  /// No description provided for @highContrastHint.
  ///
  /// In en, this message translates to:
  /// **'Stronger colours and outlines'**
  String get highContrastHint;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @simpleMode.
  ///
  /// In en, this message translates to:
  /// **'Simple Mode'**
  String get simpleMode;

  /// No description provided for @simpleModeHint.
  ///
  /// In en, this message translates to:
  /// **'Fewer options and plain words'**
  String get simpleModeHint;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Same as device'**
  String get languageSystem;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get scanning;

  /// No description provided for @spokenGuidance.
  ///
  /// In en, this message translates to:
  /// **'Spoken guidance'**
  String get spokenGuidance;

  /// No description provided for @spokenGuidanceHint.
  ///
  /// In en, this message translates to:
  /// **'Says “Move closer”, “Hold still”, “Captured” while scanning, and vibrates'**
  String get spokenGuidanceHint;

  /// No description provided for @textRecognition.
  ///
  /// In en, this message translates to:
  /// **'Text recognition'**
  String get textRecognition;

  /// No description provided for @autoOcr.
  ///
  /// In en, this message translates to:
  /// **'Recognise text automatically'**
  String get autoOcr;

  /// No description provided for @autoOcrHint.
  ///
  /// In en, this message translates to:
  /// **'Lets you search, copy text and make searchable PDFs. Runs on this device.'**
  String get autoOcrHint;

  /// No description provided for @ocrLanguage.
  ///
  /// In en, this message translates to:
  /// **'Text language'**
  String get ocrLanguage;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get langHindi;

  /// No description provided for @backupSync.
  ///
  /// In en, this message translates to:
  /// **'Back up and sync across devices'**
  String get backupSync;

  /// No description provided for @backupSyncHint.
  ///
  /// In en, this message translates to:
  /// **'Optional. Everything works without an account.'**
  String get backupSyncHint;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String signedInAs(String email);

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @showGuide.
  ///
  /// In en, this message translates to:
  /// **'Show the welcome guide'**
  String get showGuide;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @guide1Title.
  ///
  /// In en, this message translates to:
  /// **'Scan any page'**
  String get guide1Title;

  /// No description provided for @guide1Body.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at a document. DocScanner finds the edges and captures it when you hold still.'**
  String get guide1Body;

  /// No description provided for @guide2Title.
  ///
  /// In en, this message translates to:
  /// **'Fix and enhance'**
  String get guide2Title;

  /// No description provided for @guide2Body.
  ///
  /// In en, this message translates to:
  /// **'Adjust the corners, choose Black & White or Magic Color, add text or a signature.'**
  String get guide2Body;

  /// No description provided for @guide3Title.
  ///
  /// In en, this message translates to:
  /// **'Save and share, no account needed'**
  String get guide3Title;

  /// No description provided for @guide3Body.
  ///
  /// In en, this message translates to:
  /// **'Export as PDF or JPG. Your scans stay on this device unless you choose to back them up.'**
  String get guide3Body;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @guideStep.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String guideStep(int current, int total);

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @textOnPage.
  ///
  /// In en, this message translates to:
  /// **'Text on this page'**
  String get textOnPage;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @recognisingText.
  ///
  /// In en, this message translates to:
  /// **'Recognising text…'**
  String get recognisingText;

  /// No description provided for @recognisingProgress.
  ///
  /// In en, this message translates to:
  /// **'Recognising text: page {current} of {total}'**
  String recognisingProgress(int current, int total);

  /// No description provided for @noTextFound.
  ///
  /// In en, this message translates to:
  /// **'No text found on this page'**
  String get noTextFound;

  /// No description provided for @noTextFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Try a clearer photo, or choose the right language below.'**
  String get noTextFoundHint;

  /// No description provided for @ocrFailed.
  ///
  /// In en, this message translates to:
  /// **'Text recognition failed: {message}. Try again, or use a clearer photo.'**
  String ocrFailed(String message);

  /// No description provided for @ocrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Text recognition is not available on this device.'**
  String get ocrUnavailable;

  /// No description provided for @recogniseAgain.
  ///
  /// In en, this message translates to:
  /// **'Recognise again'**
  String get recogniseAgain;

  /// No description provided for @readAs.
  ///
  /// In en, this message translates to:
  /// **'Text language'**
  String get readAs;

  /// No description provided for @markup.
  ///
  /// In en, this message translates to:
  /// **'Markup'**
  String get markup;

  /// No description provided for @markupTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit / Markup'**
  String get markupTitle;

  /// No description provided for @toolSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get toolSelect;

  /// No description provided for @toolText.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get toolText;

  /// No description provided for @toolPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get toolPen;

  /// No description provided for @toolHighlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get toolHighlighter;

  /// No description provided for @toolEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get toolEraser;

  /// No description provided for @toolSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get toolSignature;

  /// No description provided for @toolRect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get toolRect;

  /// No description provided for @toolArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get toolArrow;

  /// No description provided for @toolLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get toolLine;

  /// No description provided for @toolWhiteout.
  ///
  /// In en, this message translates to:
  /// **'Whiteout'**
  String get toolWhiteout;

  /// No description provided for @markupHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a tool, then tap or drag on the page.'**
  String get markupHint;

  /// No description provided for @addInMiddle.
  ///
  /// In en, this message translates to:
  /// **'Add in the middle'**
  String get addInMiddle;

  /// No description provided for @colour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colour;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @bgNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get bgNone;

  /// No description provided for @bgWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get bgWhite;

  /// No description provided for @editText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get editText;

  /// No description provided for @bigger.
  ///
  /// In en, this message translates to:
  /// **'Bigger'**
  String get bigger;

  /// No description provided for @smaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get smaller;

  /// No description provided for @rotateLeft.
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get rotateLeft;

  /// No description provided for @rotateRight.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get rotateRight;

  /// No description provided for @moveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get moveLeft;

  /// No description provided for @moveRight.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get moveRight;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @deleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get deleteItem;

  /// No description provided for @itemsOnPage.
  ///
  /// In en, this message translates to:
  /// **'Items on this page'**
  String get itemsOnPage;

  /// No description provided for @noItems.
  ///
  /// In en, this message translates to:
  /// **'Nothing added yet.'**
  String get noItems;

  /// No description provided for @typeText.
  ///
  /// In en, this message translates to:
  /// **'Type the text'**
  String get typeText;

  /// No description provided for @drawSignature.
  ///
  /// In en, this message translates to:
  /// **'Draw your signature'**
  String get drawSignature;

  /// No description provided for @signatureHint.
  ///
  /// In en, this message translates to:
  /// **'Draw with your finger, mouse or pen. It is saved on this device for next time.'**
  String get signatureHint;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @changeSignature.
  ///
  /// In en, this message translates to:
  /// **'Change signature'**
  String get changeSignature;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get discardChanges;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @itemText.
  ///
  /// In en, this message translates to:
  /// **'Text: {text}'**
  String itemText(String text);

  /// No description provided for @itemPen.
  ///
  /// In en, this message translates to:
  /// **'Pen stroke'**
  String get itemPen;

  /// No description provided for @itemHighlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get itemHighlighter;

  /// No description provided for @itemSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get itemSignature;

  /// No description provided for @itemRect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get itemRect;

  /// No description provided for @itemArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get itemArrow;

  /// No description provided for @itemLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get itemLine;

  /// No description provided for @itemWhiteout.
  ///
  /// In en, this message translates to:
  /// **'Whiteout box'**
  String get itemWhiteout;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'selected'**
  String get selected;

  /// No description provided for @uploadExistingTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload your scans?'**
  String get uploadExistingTitle;

  /// No description provided for @uploadExistingBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have 1 document on this device. Upload it to your account so it is backed up and available on your other devices?} other{You have {count} documents on this device. Upload them to your account so they are backed up and available on your other devices?}}'**
  String uploadExistingBody(int count);

  /// No description provided for @uploadNow.
  ///
  /// In en, this message translates to:
  /// **'Upload now'**
  String get uploadNow;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @uploadLocalDocs.
  ///
  /// In en, this message translates to:
  /// **'Upload documents from this device'**
  String get uploadLocalDocs;

  /// No description provided for @conflictsResolved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 document was edited on two devices; the newer edit was kept: {titles}} other{{count} documents were edited on two devices; the newer edits were kept: {titles}}}'**
  String conflictsResolved(int count, String titles);
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
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
