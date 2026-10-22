// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DocScanner';

  @override
  String get appPurpose =>
      'Turn paper into clean PDFs. Works offline, no account needed.';

  @override
  String get scanDocument => 'Scan Document';

  @override
  String get importPhotos => 'Import Photos';

  @override
  String get importPdf => 'Import PDF';

  @override
  String get viewDocuments => 'View Documents';

  @override
  String get recentScans => 'Recent scans';

  @override
  String get seeAllDocuments => 'See all documents';

  @override
  String get settings => 'Settings';

  @override
  String get noScansYet => 'No scans yet';

  @override
  String get noScansHint =>
      'Tap “Scan Document” to scan a page with your camera, or import photos or a PDF.';

  @override
  String get howItWorksTitle => 'How it works';

  @override
  String get howItWorksStep1 =>
      'Point the camera at a page. It is captured when you hold still.';

  @override
  String get howItWorksStep2 =>
      'Check the corners, then pick a look such as Black & White.';

  @override
  String get howItWorksStep3 => 'Save as PDF or JPG and share it.';

  @override
  String get statusLocalOnly => 'Scans are saved on this device';

  @override
  String get statusSynced => 'Backed up';

  @override
  String get statusSyncing => 'Backing up…';

  @override
  String get statusOffline =>
      'Backup server not reachable. Your scans are safe on this device and will upload later.';

  @override
  String statusSyncError(String message) {
    return 'Backup problem: $message';
  }

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to upload',
      one: '1 change waiting to upload',
    );
    return '$_temp0';
  }

  @override
  String get documents => 'Documents';

  @override
  String get searchDocuments => 'Search documents and text inside pages';

  @override
  String noResults(String query) {
    return 'No documents match “$query”.';
  }

  @override
  String get clearSearch => 'Clear search';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String modified(String date) {
    return 'Modified $date';
  }

  @override
  String get open => 'Open';

  @override
  String get rename => 'Rename';

  @override
  String get export => 'Export';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get done => 'Done';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get close => 'Close';

  @override
  String get tryAgain => 'Try again';

  @override
  String get badgeDeviceOnly => 'On this device';

  @override
  String get badgeBackedUp => 'Backed up';

  @override
  String get badgeWaiting => 'Waiting to upload';

  @override
  String get renameTitle => 'Rename document';

  @override
  String get documentName => 'Document name';

  @override
  String deleteDocumentTitle(String title) {
    return 'Delete “$title”?';
  }

  @override
  String deleteDocumentBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count pages will be removed from this device.',
      one: 'Its page will be removed from this device.',
    );
    return '$_temp0';
  }

  @override
  String get documentDeleted => 'Document deleted';

  @override
  String get importing => 'Importing…';

  @override
  String importProgress(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages added',
      one: '1 page added',
    );
    return '$_temp0 · $name';
  }

  @override
  String importFailed(String message) {
    return 'Could not import: $message';
  }

  @override
  String get importNothing =>
      'Nothing to import. Choose JPG, PNG or PDF files.';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get highContrast => 'High contrast';

  @override
  String get highContrastHint => 'Stronger colours and outlines';

  @override
  String get textSize => 'Text size';

  @override
  String get simpleMode => 'Simple Mode';

  @override
  String get simpleModeHint => 'Fewer options and plain words';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Same as device';

  @override
  String get scanning => 'Scanning';

  @override
  String get spokenGuidance => 'Spoken guidance';

  @override
  String get spokenGuidanceHint =>
      'Says “Move closer”, “Hold still”, “Captured” while scanning, and vibrates';

  @override
  String get textRecognition => 'Text recognition';

  @override
  String get autoOcr => 'Recognise text automatically';

  @override
  String get autoOcrHint =>
      'Lets you search, copy text and make searchable PDFs. Runs on this device.';

  @override
  String get ocrLanguage => 'Text language';

  @override
  String get langEnglish => 'English';

  @override
  String get langHindi => 'Hindi';

  @override
  String get backupSync => 'Back up and sync across devices';

  @override
  String get backupSyncHint => 'Optional. Everything works without an account.';

  @override
  String signedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get help => 'Help';

  @override
  String get showGuide => 'Show the welcome guide';

  @override
  String get about => 'About';

  @override
  String get guide1Title => 'Scan any page';

  @override
  String get guide1Body =>
      'Point your camera at a document. DocScanner finds the edges and captures it when you hold still.';

  @override
  String get guide2Title => 'Fix and enhance';

  @override
  String get guide2Body =>
      'Adjust the corners, choose Black & White or Magic Color, add text or a signature.';

  @override
  String get guide3Title => 'Save and share, no account needed';

  @override
  String get guide3Body =>
      'Export as PDF or JPG. Your scans stay on this device unless you choose to back them up.';

  @override
  String get getStarted => 'Get started';

  @override
  String guideStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get uploadExistingTitle => 'Upload your scans?';

  @override
  String uploadExistingBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'You have $count documents on this device. Upload them to your account so they are backed up and available on your other devices?',
      one: 'You have 1 document on this device. Upload it to your account so it is backed up and available on your other devices?',
    );
    return '$_temp0';
  }

  @override
  String get uploadNow => 'Upload now';

  @override
  String get notNow => 'Not now';

  @override
  String get uploadLocalDocs => 'Upload documents from this device';

  @override
  String conflictsResolved(int count, String titles) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count documents were edited on two devices; the newer edits were kept: $titles',
      one:
          '1 document was edited on two devices; the newer edit was kept: $titles',
    );
    return '$_temp0';
  }
}
