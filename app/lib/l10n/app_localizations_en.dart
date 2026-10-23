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
  String get appPurpose => 'Turn paper into clean PDFs. Works offline, no account needed.';

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
  String get noScansHint => 'Tap “Scan Document” to scan a page with your camera, or import photos or a PDF.';

  @override
  String get howItWorksTitle => 'How it works';

  @override
  String get howItWorksStep1 => 'Point the camera at a page. It is captured when you hold still.';

  @override
  String get howItWorksStep2 => 'Check the corners, then pick a look such as Black & White.';

  @override
  String get howItWorksStep3 => 'Save as PDF or JPG and share it.';

  @override
  String get statusLocalOnly => 'Scans are saved on this device';

  @override
  String get statusSynced => 'Backed up';

  @override
  String get statusSyncing => 'Backing up…';

  @override
  String get statusOffline => 'Backup server not reachable. Your scans are safe on this device and will upload later.';

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
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count pages', one: '1 page');
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
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count pages added', one: '1 page added');
    return '$_temp0 · $name';
  }

  @override
  String importFailed(String message) {
    return 'Could not import: $message';
  }

  @override
  String get pagePreview => 'Page preview';

  @override
  String get pagePreviewLoading => 'Loading page preview';

  @override
  String get previewUnavailable => 'Preview not available';

  @override
  String get exportCancelled => 'Export cancelled.';

  @override
  String get importCancelled => 'Import cancelled. Pages already added were kept.';

  @override
  String get storageBackup => 'Storage and backup';

  @override
  String get privacyNote =>
      'Your documents stay on this device. Nothing is uploaded unless you sign in and choose to back up.';

  @override
  String storageUsed(String size, int documents, int pages) {
    return 'Space used on this device: $size ($documents documents, $pages pages)';
  }

  @override
  String storageUnknown(int documents, int pages) {
    return '$documents documents, $pages pages on this device';
  }

  @override
  String get exportAll => 'Export all documents (ZIP)';

  @override
  String get exportAllHint => 'Keep a copy without an account, or move your documents to another device.';

  @override
  String get importBackup => 'Import backup';

  @override
  String get makingBackup => 'Making the backup…';

  @override
  String get restoringBackup => 'Restoring documents…';

  @override
  String backupSaved(String name) {
    return 'Backup saved: $name';
  }

  @override
  String backupRestored(int added, int updated, int skipped) {
    return '$added added, $updated updated, $skipped already up to date.';
  }

  @override
  String backupFailed(String message) {
    return 'Backup failed: $message';
  }

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorBody => 'Your documents are safe. Try again; if it keeps happening, restart the app.';

  @override
  String deleteFailed(String title) {
    return 'Couldn’t delete “$title”. It has been put back.';
  }

  @override
  String importSkipped(String names) {
    return 'These files could not be opened and were skipped: $names';
  }

  @override
  String get importNothing => 'Nothing to import. Choose JPG, PNG or PDF files.';

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
  String get spokenGuidanceHint => 'Says “Move closer”, “Hold still”, “Captured” while scanning, and vibrates';

  @override
  String get textRecognition => 'Text recognition';

  @override
  String get autoOcr => 'Recognise text automatically';

  @override
  String get autoOcrHint => 'Lets you search, copy text and make searchable PDFs. Runs on this device.';

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
  String get guide2Body => 'Adjust the corners, choose Black & White or Magic Color, add text or a signature.';

  @override
  String get guide3Title => 'Save and share, no account needed';

  @override
  String get guide3Body => 'Export as PDF or JPG. Your scans stay on this device unless you choose to back them up.';

  @override
  String get getStarted => 'Get started';

  @override
  String guideStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get text => 'Text';

  @override
  String get textOnPage => 'Text on this page';

  @override
  String get copyText => 'Copy text';

  @override
  String get copied => 'Copied';

  @override
  String get recognisingText => 'Recognising text…';

  @override
  String recognisingProgress(int current, int total) {
    return 'Recognising text: page $current of $total';
  }

  @override
  String get noTextFound => 'No text found on this page';

  @override
  String get noTextFoundHint => 'Try a clearer photo, or choose the right language below.';

  @override
  String ocrFailed(String message) {
    return 'Text recognition failed: $message. Try again, or use a clearer photo.';
  }

  @override
  String get ocrUnavailable => 'Text recognition is not available on this device.';

  @override
  String get recogniseAgain => 'Recognise again';

  @override
  String get readAs => 'Text language';

  @override
  String get markup => 'Markup';

  @override
  String get markupTitle => 'Edit / Markup';

  @override
  String get toolSelect => 'Select';

  @override
  String get toolText => 'Add text';

  @override
  String get toolPen => 'Pen';

  @override
  String get toolHighlighter => 'Highlighter';

  @override
  String get toolEraser => 'Eraser';

  @override
  String get toolSignature => 'Signature';

  @override
  String get toolRect => 'Rectangle';

  @override
  String get toolArrow => 'Arrow';

  @override
  String get toolLine => 'Line';

  @override
  String get toolWhiteout => 'Whiteout';

  @override
  String get markupHint => 'Choose a tool, then tap or drag on the page.';

  @override
  String get addInMiddle => 'Add in the middle';

  @override
  String get colour => 'Colour';

  @override
  String get size => 'Size';

  @override
  String get bold => 'Bold';

  @override
  String get background => 'Background';

  @override
  String get bgNone => 'None';

  @override
  String get bgWhite => 'White';

  @override
  String get editText => 'Edit text';

  @override
  String get bigger => 'Bigger';

  @override
  String get smaller => 'Smaller';

  @override
  String get rotateLeft => 'Rotate left';

  @override
  String get rotateRight => 'Rotate right';

  @override
  String get moveLeft => 'Move left';

  @override
  String get moveRight => 'Move right';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get deleteItem => 'Delete item';

  @override
  String get itemsOnPage => 'Items on this page';

  @override
  String get noItems => 'Nothing added yet.';

  @override
  String get typeText => 'Type the text';

  @override
  String get drawSignature => 'Draw your signature';

  @override
  String get signatureHint => 'Draw with your finger, mouse or pen. It is saved on this device for next time.';

  @override
  String get clear => 'Clear';

  @override
  String get changeSignature => 'Change signature';

  @override
  String get discardChanges => 'Discard your changes?';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String itemText(String text) {
    return 'Text: $text';
  }

  @override
  String get itemPen => 'Pen stroke';

  @override
  String get itemHighlighter => 'Highlight';

  @override
  String get itemSignature => 'Signature';

  @override
  String get itemRect => 'Rectangle';

  @override
  String get itemArrow => 'Arrow';

  @override
  String get itemLine => 'Line';

  @override
  String get itemWhiteout => 'Whiteout box';

  @override
  String get selected => 'selected';

  @override
  String get scanTitle => 'Scan';

  @override
  String get scanDemoTitle => 'Scan (demo camera)';

  @override
  String get retakeTitle => 'Retake page';

  @override
  String get flashOn => 'Flashlight on';

  @override
  String get flashOff => 'Flashlight off';

  @override
  String get switchCamera => 'Switch camera';

  @override
  String get autoCaptureOn => 'Auto capture: on';

  @override
  String get autoCaptureOff => 'Auto capture: off';

  @override
  String get uploadPhoto => 'Upload a photo';

  @override
  String get nextSample => 'Next sample page';

  @override
  String get useDemoCamera => 'Use demo camera';

  @override
  String get useDeviceCamera => 'Use device camera';

  @override
  String get demoCameraNote => 'Demo camera: shows sample pages, not your camera.';

  @override
  String get diagnostics => 'Detector diagnostics';

  @override
  String get startingCamera => 'Starting camera…';

  @override
  String get capturing => 'Capturing…';

  @override
  String get hintTooDarkFlash => 'Too dark: turn on the flashlight';

  @override
  String get hintTooDark => 'Too dark: add more light';

  @override
  String get hintPointCamera => 'Point the camera at a document';

  @override
  String get hintMoveCloser => 'Move closer';

  @override
  String get hintHoldStill => 'Hold still';

  @override
  String get hintFound => 'Document found';

  @override
  String get hintNextPage => 'Page captured. Show the next page.';

  @override
  String get hintTapShutter => 'Document found: tap Capture';

  @override
  String get capture => 'Capture';

  @override
  String capturedPage(int page) {
    return 'Captured, page $page';
  }

  @override
  String reviewPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review $count pages',
      one: 'Review 1 page',
    );
    return '$_temp0';
  }

  @override
  String get savingPages => 'Saving…';

  @override
  String get keepScan => 'Keep scan';

  @override
  String get replacePage => 'Replace page';

  @override
  String get retake => 'Retake';

  @override
  String get couldNotSavePage => 'Could not save the page. Please try again.';

  @override
  String get camOffTitle => 'Camera access is off';

  @override
  String get camOffWeb =>
      'Allow camera access for this site (camera icon in the address bar), then try again. You can also upload a photo instead.';

  @override
  String get camOffApp =>
      'Allow camera access for DocScanner in Settings, then try again. You can also upload a photo instead.';

  @override
  String get noCameraTitle => 'No camera found';

  @override
  String get noCameraBody =>
      'This computer has no camera we can use. Upload a photo of the page, or try the demo camera.';

  @override
  String get cameraBusyTitle => 'Camera is busy';

  @override
  String get cameraBusyBody => 'Another app or browser tab is using the camera. Close it and try again.';

  @override
  String get cameraHttpsTitle => 'Camera not available here';

  @override
  String get cameraHttpsBody =>
      'Browsers only allow the camera on https:// pages or localhost. Upload a photo instead.';

  @override
  String get cameraErrorTitle => 'Could not start the camera';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get msgCaptureFailed => 'Could not take the photo. Please try again.';

  @override
  String get msgBadPhotoFile => 'That file could not be opened as a photo.';

  @override
  String get msgNoFlashlight => 'This camera has no flashlight.';

  @override
  String pageOf(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get previousPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String get addPages => 'Add pages';

  @override
  String get scanMore => 'Scan more';

  @override
  String get importPdfOrFiles => 'Import PDF or files';

  @override
  String get toolFilters => 'Filters';

  @override
  String get toolRotate => 'Rotate';

  @override
  String get toolCrop => 'Crop';

  @override
  String get toolCorners => 'Corners';

  @override
  String get toolPageText => 'Text';

  @override
  String get toolRetake => 'Retake';

  @override
  String get moveEarlier => 'Move earlier';

  @override
  String get moveLater => 'Move later';

  @override
  String get deletePage => 'Delete page';

  @override
  String get deleteDocument => 'Delete document';

  @override
  String pageDeleted(int page) {
    return 'Page $page deleted';
  }

  @override
  String pageMoved(int page) {
    return 'Page moved to position $page';
  }

  @override
  String deleteDocTitle(String title) {
    return 'Delete “$title”?';
  }

  @override
  String deleteDocBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All $count pages will be removed.',
      one: 'Its page will be removed.',
    );
    return '$_temp0';
  }

  @override
  String get recognizingText => 'Recognising text…';

  @override
  String recognizingTextOf(int done, int total) {
    return 'Recognising text $done of $total…';
  }

  @override
  String somethingWentWrong(String message) {
    return 'Something went wrong: $message';
  }

  @override
  String get noPagesYet => 'No pages yet';

  @override
  String get noPagesHint => 'Scan a page or import photos or a PDF to add pages.';

  @override
  String pageThumbLabel(int page) {
    return 'Page $page. Drag to reorder, or use Move earlier and Move later.';
  }

  @override
  String get documentNotFound => 'This document could not be opened.';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get filterBw => 'Black & White';

  @override
  String get filterMagic => 'Magic Color';

  @override
  String get showOriginal => 'Compare with original';

  @override
  String get before => 'Before';

  @override
  String get after => 'After';

  @override
  String get applying => 'Applying…';

  @override
  String applyToAll(String filter) {
    return 'Apply $filter to all pages';
  }

  @override
  String get previewFailed => 'Preview not available';

  @override
  String exportTitle(String title) {
    return 'Export “$title”';
  }

  @override
  String get formatPdf => 'PDF';

  @override
  String formatJpg(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'JPG ($count files)', one: 'JPG');
    return '$_temp0';
  }

  @override
  String get pageSize => 'Page size';

  @override
  String get pageSizeFit => 'Fit to page';

  @override
  String get pageSizeA4 => 'A4';

  @override
  String get pageSizeLetter => 'US Letter';

  @override
  String get searchablePdf => 'Searchable PDF';

  @override
  String get searchablePdfHint => 'Recognise text so it can be searched and copied';

  @override
  String get download => 'Download';

  @override
  String get share => 'Share';

  @override
  String get shareOrSave => 'Share or save';

  @override
  String get creatingPdf => 'Creating PDF…';

  @override
  String get creatingImages => 'Creating images…';

  @override
  String savedFile(String name) {
    return 'Saved $name to your Downloads folder';
  }

  @override
  String savedImages(int count) {
    return 'Saved $count images to your Downloads folder';
  }

  @override
  String exportFailed(String message) {
    return 'Export failed: $message';
  }

  @override
  String get exportHelpWeb =>
      'Download saves the file to your Downloads folder. Share opens your device’s share menu in browsers that support it (for example Safari and Chrome on phones); elsewhere it downloads the file.';

  @override
  String get exportHelpIos => 'To save the file, tap Share or save, then “Save to Files”.';

  @override
  String get exportHelpAndroid => 'To save the file, tap Share or save, then pick Files, Drive or another app.';

  @override
  String get markupBurnedIn => 'Markup will be part of the exported pages.';

  @override
  String get adjustCorners => 'Adjust corners';

  @override
  String get noEdgesFound => 'No page edges found. Adjust the corners or keep the full photo.';

  @override
  String get cornersHint =>
      'Drag the corners or edges onto the page. Keyboard: Tab picks a corner, arrow keys move it.';

  @override
  String get cornersCrossed => 'The corners cross over. Drag them back around the page.';

  @override
  String get resetCorners => 'Reset corners';

  @override
  String get useFullPhoto => 'Use full photo';

  @override
  String get rotate => 'Rotate';

  @override
  String get confirm => 'Confirm';

  @override
  String get couldNotRotate => 'Could not rotate the photo.';

  @override
  String get cornerTopLeft => 'top-left';

  @override
  String get cornerTopRight => 'top-right';

  @override
  String get cornerBottomRight => 'bottom-right';

  @override
  String get cornerBottomLeft => 'bottom-left';

  @override
  String cornersSemantics(String corner) {
    return 'Page corners. Selected: $corner corner. Use the move actions, or drag the corners.';
  }

  @override
  String get nextCorner => 'Next corner';

  @override
  String get moveCornerLeft => 'Move corner left';

  @override
  String get moveCornerRight => 'Move corner right';

  @override
  String get moveCornerUp => 'Move corner up';

  @override
  String get moveCornerDown => 'Move corner down';

  @override
  String get cropTitle => 'Crop';

  @override
  String get reset => 'Reset';

  @override
  String get apply => 'Apply';

  @override
  String get cropHint => 'Drag the edges or corners of the box. Drag inside it to move it.';

  @override
  String get backUpYourScans => 'Back up and sync your scans';

  @override
  String get backUpIntro =>
      'Optional. Without an account everything stays on this device and every feature still works. Sign in to back up and use your scans on other devices.';

  @override
  String get server => 'Server';

  @override
  String get serverHint => 'Enter a URL like http://192.168.1.20:8000';

  @override
  String get testConnection => 'Test connection';

  @override
  String get serverReachable => 'Connected to the server.';

  @override
  String get serverUnreachable => 'Can’t reach the server. Check the address and that the backend is running.';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get email => 'Email';

  @override
  String get enterEmail => 'Enter your email';

  @override
  String get password => 'Password';

  @override
  String get passwordRule => 'At least 8 characters';

  @override
  String get showPassword => 'Show';

  @override
  String get hidePassword => 'Hide';

  @override
  String get showPasswordLabel => 'Show password';

  @override
  String get hidePasswordLabel => 'Hide password';

  @override
  String errOffline(String url) {
    return 'Can’t reach the server at $url. Check the address and that the backend is running.';
  }

  @override
  String get errWrongPassword => 'Wrong email or password.';

  @override
  String get errAccountExists => 'An account with this email already exists. Sign in instead.';

  @override
  String get errInvalidInput => 'Check the email address; passwords need at least 8 characters.';

  @override
  String get syncNow => 'Sync now';

  @override
  String get processOnServer => 'Process photos on the server';

  @override
  String get processOnServerHint =>
      'For slow devices: page detection, flattening and filters run on the server. The live camera preview still runs on this device.';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutTitle => 'Sign out?';

  @override
  String get signOutBody =>
      'Your scans stay on this device. Changes made while signed out sync after you sign in again.';

  @override
  String get signedInNote =>
      'Scans are stored on this device and backed up to your account. They keep working offline.';

  @override
  String get syncNever => 'Not synced yet';

  @override
  String get syncJustNow => 'Synced just now';

  @override
  String syncMinutesAgo(int minutes) {
    return 'Synced $minutes min ago';
  }

  @override
  String syncHoursAgo(int hours) {
    return 'Synced $hours h ago';
  }

  @override
  String get syncNotSignedIn => 'Not signed in';

  @override
  String get syncSyncing => 'Syncing…';

  @override
  String get syncOffline => 'Offline. Changes are saved on this device and will sync later.';

  @override
  String syncProblem(String message) {
    return 'Sync problem: $message';
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
      other: '$count documents were edited on two devices; the newer edits were kept: $titles',
      one: '1 document was edited on two devices; the newer edit was kept: $titles',
    );
    return '$_temp0';
  }
}
