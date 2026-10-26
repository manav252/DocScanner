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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('hi')];

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

  /// No description provided for @pagePreview.
  ///
  /// In en, this message translates to:
  /// **'Page preview'**
  String get pagePreview;

  /// No description provided for @pagePreviewLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading page preview'**
  String get pagePreviewLoading;

  /// No description provided for @previewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Preview not available'**
  String get previewUnavailable;

  /// No description provided for @exportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Export cancelled.'**
  String get exportCancelled;

  /// No description provided for @importCancelled.
  ///
  /// In en, this message translates to:
  /// **'Import cancelled. Pages already added were kept.'**
  String get importCancelled;

  /// No description provided for @storageBackup.
  ///
  /// In en, this message translates to:
  /// **'Storage and backup'**
  String get storageBackup;

  /// No description provided for @privacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your documents stay on this device. Nothing is uploaded unless you sign in and choose to back up.'**
  String get privacyNote;

  /// No description provided for @storageUsed.
  ///
  /// In en, this message translates to:
  /// **'Space used on this device: {size} ({documents} documents, {pages} pages)'**
  String storageUsed(String size, int documents, int pages);

  /// No description provided for @storageUnknown.
  ///
  /// In en, this message translates to:
  /// **'{documents} documents, {pages} pages on this device'**
  String storageUnknown(int documents, int pages);

  /// No description provided for @exportAll.
  ///
  /// In en, this message translates to:
  /// **'Export all documents (ZIP)'**
  String get exportAll;

  /// No description provided for @exportAllHint.
  ///
  /// In en, this message translates to:
  /// **'Keep a copy without an account, or move your documents to another device.'**
  String get exportAllHint;

  /// No description provided for @importBackup.
  ///
  /// In en, this message translates to:
  /// **'Import backup'**
  String get importBackup;

  /// No description provided for @makingBackup.
  ///
  /// In en, this message translates to:
  /// **'Making the backup…'**
  String get makingBackup;

  /// No description provided for @restoringBackup.
  ///
  /// In en, this message translates to:
  /// **'Restoring documents…'**
  String get restoringBackup;

  /// No description provided for @backupSaved.
  ///
  /// In en, this message translates to:
  /// **'Backup saved: {name}'**
  String backupSaved(String name);

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'{added} added, {updated} updated, {skipped} already up to date.'**
  String backupRestored(int added, int updated, int skipped);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {message}'**
  String backupFailed(String message);

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @errorBody.
  ///
  /// In en, this message translates to:
  /// **'Your documents are safe. Try again; if it keeps happening, restart the app.'**
  String get errorBody;

  /// No description provided for @serverWaking.
  ///
  /// In en, this message translates to:
  /// **'Waking up the server, this can take up to a minute…'**
  String get serverWaking;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t delete “{title}”. It has been put back.'**
  String deleteFailed(String title);

  /// No description provided for @importSkipped.
  ///
  /// In en, this message translates to:
  /// **'These files could not be opened and were skipped: {names}'**
  String importSkipped(String names);

  /// No description provided for @importWhyPassword.
  ///
  /// In en, this message translates to:
  /// **'password-protected PDF'**
  String get importWhyPassword;

  /// No description provided for @importWhyUnreadable.
  ///
  /// In en, this message translates to:
  /// **'damaged or unsupported file'**
  String get importWhyUnreadable;

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

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanTitle;

  /// No description provided for @scanDemoTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan (demo camera)'**
  String get scanDemoTitle;

  /// No description provided for @retakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Retake page'**
  String get retakeTitle;

  /// No description provided for @flashOn.
  ///
  /// In en, this message translates to:
  /// **'Flashlight on'**
  String get flashOn;

  /// No description provided for @flashOff.
  ///
  /// In en, this message translates to:
  /// **'Flashlight off'**
  String get flashOff;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get switchCamera;

  /// No description provided for @autoCaptureOn.
  ///
  /// In en, this message translates to:
  /// **'Auto capture: on'**
  String get autoCaptureOn;

  /// No description provided for @autoCaptureOff.
  ///
  /// In en, this message translates to:
  /// **'Auto capture: off'**
  String get autoCaptureOff;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload a photo'**
  String get uploadPhoto;

  /// No description provided for @nextSample.
  ///
  /// In en, this message translates to:
  /// **'Next sample page'**
  String get nextSample;

  /// No description provided for @useDemoCamera.
  ///
  /// In en, this message translates to:
  /// **'Use demo camera'**
  String get useDemoCamera;

  /// No description provided for @useDeviceCamera.
  ///
  /// In en, this message translates to:
  /// **'Use device camera'**
  String get useDeviceCamera;

  /// No description provided for @demoCameraNote.
  ///
  /// In en, this message translates to:
  /// **'Demo camera: shows sample pages, not your camera.'**
  String get demoCameraNote;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Detector diagnostics'**
  String get diagnostics;

  /// No description provided for @startingCamera.
  ///
  /// In en, this message translates to:
  /// **'Starting camera…'**
  String get startingCamera;

  /// No description provided for @capturing.
  ///
  /// In en, this message translates to:
  /// **'Capturing…'**
  String get capturing;

  /// No description provided for @hintTooDarkFlash.
  ///
  /// In en, this message translates to:
  /// **'Too dark: turn on the flashlight'**
  String get hintTooDarkFlash;

  /// No description provided for @hintTooDark.
  ///
  /// In en, this message translates to:
  /// **'Too dark: add more light'**
  String get hintTooDark;

  /// No description provided for @hintPointCamera.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a document'**
  String get hintPointCamera;

  /// No description provided for @hintMoveCloser.
  ///
  /// In en, this message translates to:
  /// **'Move closer'**
  String get hintMoveCloser;

  /// No description provided for @hintHoldStill.
  ///
  /// In en, this message translates to:
  /// **'Hold still'**
  String get hintHoldStill;

  /// No description provided for @hintFound.
  ///
  /// In en, this message translates to:
  /// **'Document found'**
  String get hintFound;

  /// No description provided for @hintNextPage.
  ///
  /// In en, this message translates to:
  /// **'Page captured. Show the next page.'**
  String get hintNextPage;

  /// No description provided for @hintTapShutter.
  ///
  /// In en, this message translates to:
  /// **'Document found: tap Capture'**
  String get hintTapShutter;

  /// No description provided for @capture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get capture;

  /// No description provided for @capturedPage.
  ///
  /// In en, this message translates to:
  /// **'Captured, page {page}'**
  String capturedPage(int page);

  /// No description provided for @reviewPages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review 1 page} other{Review {count} pages}}'**
  String reviewPages(int count);

  /// No description provided for @savingPages.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingPages;

  /// No description provided for @keepScan.
  ///
  /// In en, this message translates to:
  /// **'Keep scan'**
  String get keepScan;

  /// No description provided for @replacePage.
  ///
  /// In en, this message translates to:
  /// **'Replace page'**
  String get replacePage;

  /// No description provided for @retake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get retake;

  /// No description provided for @couldNotSavePage.
  ///
  /// In en, this message translates to:
  /// **'Could not save the page. Please try again.'**
  String get couldNotSavePage;

  /// No description provided for @camOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access is off'**
  String get camOffTitle;

  /// No description provided for @camOffWeb.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access for this site (camera icon in the address bar), then try again. You can also upload a photo instead.'**
  String get camOffWeb;

  /// No description provided for @camOffApp.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access for DocScanner in Settings, then try again. You can also upload a photo instead.'**
  String get camOffApp;

  /// No description provided for @noCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'No camera found'**
  String get noCameraTitle;

  /// No description provided for @noCameraBody.
  ///
  /// In en, this message translates to:
  /// **'This computer has no camera we can use. Upload a photo of the page, or try the demo camera.'**
  String get noCameraBody;

  /// No description provided for @cameraBusyTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera is busy'**
  String get cameraBusyTitle;

  /// No description provided for @cameraBusyBody.
  ///
  /// In en, this message translates to:
  /// **'Another app or browser tab is using the camera. Close it and try again.'**
  String get cameraBusyBody;

  /// No description provided for @cameraHttpsTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera not available here'**
  String get cameraHttpsTitle;

  /// No description provided for @cameraHttpsBody.
  ///
  /// In en, this message translates to:
  /// **'Browsers only allow the camera on https:// pages or localhost. Upload a photo instead.'**
  String get cameraHttpsBody;

  /// No description provided for @cameraErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not start the camera'**
  String get cameraErrorTitle;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @msgCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not take the photo. Please try again.'**
  String get msgCaptureFailed;

  /// No description provided for @msgBadPhotoFile.
  ///
  /// In en, this message translates to:
  /// **'That file could not be opened as a photo.'**
  String get msgBadPhotoFile;

  /// No description provided for @msgNoFlashlight.
  ///
  /// In en, this message translates to:
  /// **'This camera has no flashlight.'**
  String get msgNoFlashlight;

  /// No description provided for @pageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {total}'**
  String pageOf(int page, int total);

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// No description provided for @addPages.
  ///
  /// In en, this message translates to:
  /// **'Add pages'**
  String get addPages;

  /// No description provided for @scanMore.
  ///
  /// In en, this message translates to:
  /// **'Scan more'**
  String get scanMore;

  /// No description provided for @importPdfOrFiles.
  ///
  /// In en, this message translates to:
  /// **'Import PDF or files'**
  String get importPdfOrFiles;

  /// No description provided for @toolFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get toolFilters;

  /// No description provided for @toolRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get toolRotate;

  /// No description provided for @toolCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get toolCrop;

  /// No description provided for @toolCorners.
  ///
  /// In en, this message translates to:
  /// **'Corners'**
  String get toolCorners;

  /// No description provided for @toolPageText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolPageText;

  /// No description provided for @toolRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get toolRetake;

  /// No description provided for @moveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get moveEarlier;

  /// No description provided for @moveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get moveLater;

  /// No description provided for @deletePage.
  ///
  /// In en, this message translates to:
  /// **'Delete page'**
  String get deletePage;

  /// No description provided for @deleteDocument.
  ///
  /// In en, this message translates to:
  /// **'Delete document'**
  String get deleteDocument;

  /// No description provided for @pageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Page {page} deleted'**
  String pageDeleted(int page);

  /// No description provided for @pageMoved.
  ///
  /// In en, this message translates to:
  /// **'Page moved to position {page}'**
  String pageMoved(int page);

  /// No description provided for @deleteDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{title}”?'**
  String deleteDocTitle(String title);

  /// No description provided for @deleteDocBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Its page will be removed.} other{All {count} pages will be removed.}}'**
  String deleteDocBody(int count);

  /// No description provided for @recognizingText.
  ///
  /// In en, this message translates to:
  /// **'Recognising text…'**
  String get recognizingText;

  /// No description provided for @recognizingTextOf.
  ///
  /// In en, this message translates to:
  /// **'Recognising text {done} of {total}…'**
  String recognizingTextOf(int done, int total);

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {message}'**
  String somethingWentWrong(String message);

  /// No description provided for @noPagesYet.
  ///
  /// In en, this message translates to:
  /// **'No pages yet'**
  String get noPagesYet;

  /// No description provided for @noPagesHint.
  ///
  /// In en, this message translates to:
  /// **'Scan a page or import photos or a PDF to add pages.'**
  String get noPagesHint;

  /// No description provided for @pageThumbLabel.
  ///
  /// In en, this message translates to:
  /// **'Page {page}. Drag to reorder, or use Move earlier and Move later.'**
  String pageThumbLabel(int page);

  /// No description provided for @documentNotFound.
  ///
  /// In en, this message translates to:
  /// **'This document could not be opened.'**
  String get documentNotFound;

  /// No description provided for @filterOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get filterOriginal;

  /// No description provided for @filterGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get filterGrayscale;

  /// No description provided for @filterBw.
  ///
  /// In en, this message translates to:
  /// **'Black & White'**
  String get filterBw;

  /// No description provided for @filterMagic.
  ///
  /// In en, this message translates to:
  /// **'Magic Color'**
  String get filterMagic;

  /// No description provided for @showOriginal.
  ///
  /// In en, this message translates to:
  /// **'Compare with original'**
  String get showOriginal;

  /// No description provided for @before.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get before;

  /// No description provided for @after.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get after;

  /// No description provided for @applying.
  ///
  /// In en, this message translates to:
  /// **'Applying…'**
  String get applying;

  /// No description provided for @applyToAll.
  ///
  /// In en, this message translates to:
  /// **'Apply {filter} to all pages'**
  String applyToAll(String filter);

  /// No description provided for @previewFailed.
  ///
  /// In en, this message translates to:
  /// **'Preview not available'**
  String get previewFailed;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export “{title}”'**
  String exportTitle(String title);

  /// No description provided for @formatPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get formatPdf;

  /// No description provided for @formatJpg.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{JPG} other{JPG ({count} files)}}'**
  String formatJpg(int count);

  /// No description provided for @pageSize.
  ///
  /// In en, this message translates to:
  /// **'Page size'**
  String get pageSize;

  /// No description provided for @pageSizeFit.
  ///
  /// In en, this message translates to:
  /// **'Fit to page'**
  String get pageSizeFit;

  /// No description provided for @pageSizeA4.
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get pageSizeA4;

  /// No description provided for @pageSizeLetter.
  ///
  /// In en, this message translates to:
  /// **'US Letter'**
  String get pageSizeLetter;

  /// No description provided for @searchablePdf.
  ///
  /// In en, this message translates to:
  /// **'Searchable PDF'**
  String get searchablePdf;

  /// No description provided for @searchablePdfHint.
  ///
  /// In en, this message translates to:
  /// **'Recognise text so it can be searched and copied'**
  String get searchablePdfHint;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareOrSave.
  ///
  /// In en, this message translates to:
  /// **'Share or save'**
  String get shareOrSave;

  /// No description provided for @creatingPdf.
  ///
  /// In en, this message translates to:
  /// **'Creating PDF…'**
  String get creatingPdf;

  /// No description provided for @creatingImages.
  ///
  /// In en, this message translates to:
  /// **'Creating images…'**
  String get creatingImages;

  /// No description provided for @savedFile.
  ///
  /// In en, this message translates to:
  /// **'Saved {name} to your Downloads folder'**
  String savedFile(String name);

  /// No description provided for @savedImages.
  ///
  /// In en, this message translates to:
  /// **'Saved {count} images to your Downloads folder'**
  String savedImages(int count);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {message}'**
  String exportFailed(String message);

  /// No description provided for @exportHelpWeb.
  ///
  /// In en, this message translates to:
  /// **'Download saves the file to your Downloads folder. Share opens your device’s share menu in browsers that support it (for example Safari and Chrome on phones); elsewhere it downloads the file.'**
  String get exportHelpWeb;

  /// No description provided for @exportHelpIos.
  ///
  /// In en, this message translates to:
  /// **'To save the file, tap Share or save, then “Save to Files”.'**
  String get exportHelpIos;

  /// No description provided for @exportHelpAndroid.
  ///
  /// In en, this message translates to:
  /// **'To save the file, tap Share or save, then pick Files, Drive or another app.'**
  String get exportHelpAndroid;

  /// No description provided for @markupBurnedIn.
  ///
  /// In en, this message translates to:
  /// **'Markup will be part of the exported pages.'**
  String get markupBurnedIn;

  /// No description provided for @adjustCorners.
  ///
  /// In en, this message translates to:
  /// **'Adjust corners'**
  String get adjustCorners;

  /// No description provided for @noEdgesFound.
  ///
  /// In en, this message translates to:
  /// **'No page edges found. Adjust the corners or keep the full photo.'**
  String get noEdgesFound;

  /// No description provided for @cornersHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners or edges onto the page. Keyboard: Tab picks a corner, arrow keys move it.'**
  String get cornersHint;

  /// No description provided for @cornersCrossed.
  ///
  /// In en, this message translates to:
  /// **'The corners cross over. Drag them back around the page.'**
  String get cornersCrossed;

  /// No description provided for @resetCorners.
  ///
  /// In en, this message translates to:
  /// **'Reset corners'**
  String get resetCorners;

  /// No description provided for @useFullPhoto.
  ///
  /// In en, this message translates to:
  /// **'Use full photo'**
  String get useFullPhoto;

  /// No description provided for @rotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get rotate;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @couldNotRotate.
  ///
  /// In en, this message translates to:
  /// **'Could not rotate the photo.'**
  String get couldNotRotate;

  /// No description provided for @cornerTopLeft.
  ///
  /// In en, this message translates to:
  /// **'top-left'**
  String get cornerTopLeft;

  /// No description provided for @cornerTopRight.
  ///
  /// In en, this message translates to:
  /// **'top-right'**
  String get cornerTopRight;

  /// No description provided for @cornerBottomRight.
  ///
  /// In en, this message translates to:
  /// **'bottom-right'**
  String get cornerBottomRight;

  /// No description provided for @cornerBottomLeft.
  ///
  /// In en, this message translates to:
  /// **'bottom-left'**
  String get cornerBottomLeft;

  /// No description provided for @cornersSemantics.
  ///
  /// In en, this message translates to:
  /// **'Page corners. Selected: {corner} corner. Use the move actions, or drag the corners.'**
  String cornersSemantics(String corner);

  /// No description provided for @nextCorner.
  ///
  /// In en, this message translates to:
  /// **'Next corner'**
  String get nextCorner;

  /// No description provided for @moveCornerLeft.
  ///
  /// In en, this message translates to:
  /// **'Move corner left'**
  String get moveCornerLeft;

  /// No description provided for @moveCornerRight.
  ///
  /// In en, this message translates to:
  /// **'Move corner right'**
  String get moveCornerRight;

  /// No description provided for @moveCornerUp.
  ///
  /// In en, this message translates to:
  /// **'Move corner up'**
  String get moveCornerUp;

  /// No description provided for @moveCornerDown.
  ///
  /// In en, this message translates to:
  /// **'Move corner down'**
  String get moveCornerDown;

  /// No description provided for @cropTitle.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropTitle;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @cropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the edges or corners of the box. Drag inside it to move it.'**
  String get cropHint;

  /// No description provided for @backUpYourScans.
  ///
  /// In en, this message translates to:
  /// **'Back up and sync your scans'**
  String get backUpYourScans;

  /// No description provided for @backUpIntro.
  ///
  /// In en, this message translates to:
  /// **'Optional. Without an account everything stays on this device and every feature still works. Sign in to back up and use your scans on other devices.'**
  String get backUpIntro;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @serverHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a URL like http://192.168.1.20:8000'**
  String get serverHint;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @serverReachable.
  ///
  /// In en, this message translates to:
  /// **'Connected to the server.'**
  String get serverReachable;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can’t reach the server. Check the address and that the backend is running.'**
  String get serverUnreachable;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterEmail;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRule.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordRule;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hidePassword;

  /// No description provided for @showPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPasswordLabel;

  /// No description provided for @hidePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePasswordLabel;

  /// No description provided for @errOffline.
  ///
  /// In en, this message translates to:
  /// **'Can’t reach the server at {url}. Check the address and that the backend is running.'**
  String errOffline(String url);

  /// No description provided for @errWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get errWrongPassword;

  /// No description provided for @errAccountExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Sign in instead.'**
  String get errAccountExists;

  /// No description provided for @errInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Check the email address; passwords need at least 8 characters.'**
  String get errInvalidInput;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @processOnServer.
  ///
  /// In en, this message translates to:
  /// **'Process photos on the server'**
  String get processOnServer;

  /// No description provided for @processOnServerHint.
  ///
  /// In en, this message translates to:
  /// **'For slow devices: page detection, flattening and filters run on the server. The live camera preview still runs on this device.'**
  String get processOnServerHint;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutTitle;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'Your scans stay on this device. Changes made while signed out sync after you sign in again.'**
  String get signOutBody;

  /// No description provided for @signedInNote.
  ///
  /// In en, this message translates to:
  /// **'Scans are stored on this device and backed up to your account. They keep working offline.'**
  String get signedInNote;

  /// No description provided for @syncNever.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncNever;

  /// No description provided for @syncJustNow.
  ///
  /// In en, this message translates to:
  /// **'Synced just now'**
  String get syncJustNow;

  /// No description provided for @syncMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Synced {minutes} min ago'**
  String syncMinutesAgo(int minutes);

  /// No description provided for @syncHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Synced {hours} h ago'**
  String syncHoursAgo(int hours);

  /// No description provided for @syncNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get syncNotSignedIn;

  /// No description provided for @syncSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncSyncing;

  /// No description provided for @syncOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline. Changes are saved on this device and will sync later.'**
  String get syncOffline;

  /// No description provided for @syncProblem.
  ///
  /// In en, this message translates to:
  /// **'Sync problem: {message}'**
  String syncProblem(String message);

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

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'hi'].contains(locale.languageCode);

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
