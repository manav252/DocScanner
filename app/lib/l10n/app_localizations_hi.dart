// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'डॉकस्कैनर';

  @override
  String get appPurpose => 'काग़ज़ को साफ़ PDF में बदलें। ऑफ़लाइन चलता है, खाते की ज़रूरत नहीं।';

  @override
  String get scanDocument => 'दस्तावेज़ स्कैन करें';

  @override
  String get importPhotos => 'फ़ोटो जोड़ें';

  @override
  String get importPdf => 'PDF जोड़ें';

  @override
  String get viewDocuments => 'दस्तावेज़ देखें';

  @override
  String get recentScans => 'हाल के स्कैन';

  @override
  String get seeAllDocuments => 'सभी दस्तावेज़ देखें';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get noScansYet => 'अभी कोई स्कैन नहीं';

  @override
  String get noScansHint => 'कैमरे से पेज स्कैन करने के लिए “दस्तावेज़ स्कैन करें” दबाएँ, या फ़ोटो या PDF जोड़ें।';

  @override
  String get howItWorksTitle => 'यह कैसे काम करता है';

  @override
  String get howItWorksStep1 => 'कैमरे को पेज पर रखें। स्थिर रहने पर तस्वीर अपने-आप ली जाती है।';

  @override
  String get howItWorksStep2 => 'कोनों की जाँच करें, फिर ब्लैक एंड व्हाइट जैसा रूप चुनें।';

  @override
  String get howItWorksStep3 => 'PDF या JPG के रूप में सहेजें और साझा करें।';

  @override
  String get statusLocalOnly => 'स्कैन इसी डिवाइस पर सहेजे जाते हैं';

  @override
  String get statusSynced => 'बैकअप हो गया';

  @override
  String get statusSyncing => 'बैकअप हो रहा है…';

  @override
  String get statusOffline =>
      'बैकअप सर्वर से संपर्क नहीं हो पा रहा। आपके स्कैन इस डिवाइस पर सुरक्षित हैं और बाद में अपलोड होंगे।';

  @override
  String statusSyncError(String message) {
    return 'बैकअप में समस्या: $message';
  }

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बदलाव अपलोड होने की प्रतीक्षा में',
      one: '1 बदलाव अपलोड होने की प्रतीक्षा में',
    );
    return '$_temp0';
  }

  @override
  String get documents => 'दस्तावेज़';

  @override
  String get searchDocuments => 'दस्तावेज़ और पेजों के अंदर का टेक्स्ट खोजें';

  @override
  String noResults(String query) {
    return '“$query” से मेल खाता कोई दस्तावेज़ नहीं।';
  }

  @override
  String get clearSearch => 'खोज साफ़ करें';

  @override
  String pageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count पेज', one: '1 पेज');
    return '$_temp0';
  }

  @override
  String modified(String date) {
    return 'बदला गया $date';
  }

  @override
  String get open => 'खोलें';

  @override
  String get rename => 'नाम बदलें';

  @override
  String get export => 'निर्यात';

  @override
  String get delete => 'हटाएँ';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get save => 'सहेजें';

  @override
  String get undo => 'पूर्ववत करें';

  @override
  String get redo => 'फिर से करें';

  @override
  String get done => 'हो गया';

  @override
  String get next => 'आगे';

  @override
  String get back => 'पीछे';

  @override
  String get skip => 'छोड़ें';

  @override
  String get close => 'बंद करें';

  @override
  String get tryAgain => 'फिर कोशिश करें';

  @override
  String get badgeDeviceOnly => 'इस डिवाइस पर';

  @override
  String get badgeBackedUp => 'बैकअप हुआ';

  @override
  String get badgeWaiting => 'अपलोड की प्रतीक्षा';

  @override
  String get renameTitle => 'दस्तावेज़ का नाम बदलें';

  @override
  String get documentName => 'दस्तावेज़ का नाम';

  @override
  String deleteDocumentTitle(String title) {
    return '“$title” हटाएँ?';
  }

  @override
  String deleteDocumentBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'इसके सभी $count पेज इस डिवाइस से हटा दिए जाएँगे।',
      one: 'इसका पेज इस डिवाइस से हटा दिया जाएगा।',
    );
    return '$_temp0';
  }

  @override
  String get documentDeleted => 'दस्तावेज़ हटा दिया गया';

  @override
  String get importing => 'जोड़ा जा रहा है…';

  @override
  String importProgress(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count पेज जोड़े', one: '1 पेज जोड़ा');
    return '$_temp0 · $name';
  }

  @override
  String importFailed(String message) {
    return 'जोड़ नहीं सके: $message';
  }

  @override
  String get pagePreview => 'पेज का पूर्वावलोकन';

  @override
  String get pagePreviewLoading => 'पेज का पूर्वावलोकन लोड हो रहा है';

  @override
  String get previewUnavailable => 'पूर्वावलोकन उपलब्ध नहीं';

  @override
  String get exportCancelled => 'निर्यात रद्द किया गया।';

  @override
  String get importCancelled => 'जोड़ना रद्द किया गया। जो पेज जुड़ चुके थे, वे रखे गए।';

  @override
  String get storageBackup => 'स्टोरेज और बैकअप';

  @override
  String get privacyNote =>
      'आपके दस्तावेज़ इसी डिवाइस पर रहते हैं। जब तक आप साइन इन करके बैकअप नहीं चुनते, कुछ भी अपलोड नहीं होता।';

  @override
  String storageUsed(String size, int documents, int pages) {
    return 'इस डिवाइस पर उपयोग की गई जगह: $size ($documents दस्तावेज़, $pages पेज)';
  }

  @override
  String storageUnknown(int documents, int pages) {
    return 'इस डिवाइस पर $documents दस्तावेज़, $pages पेज';
  }

  @override
  String get exportAll => 'सभी दस्तावेज़ निर्यात करें (ZIP)';

  @override
  String get exportAllHint => 'बिना खाते के एक कॉपी रखें, या अपने दस्तावेज़ दूसरे डिवाइस पर ले जाएँ।';

  @override
  String get importBackup => 'बैकअप से वापस लाएँ';

  @override
  String get makingBackup => 'बैकअप बन रहा है…';

  @override
  String get restoringBackup => 'दस्तावेज़ वापस लाए जा रहे हैं…';

  @override
  String backupSaved(String name) {
    return 'बैकअप सहेजा गया: $name';
  }

  @override
  String backupRestored(int added, int updated, int skipped) {
    return '$added जोड़े गए, $updated अपडेट हुए, $skipped पहले से नए थे।';
  }

  @override
  String backupFailed(String message) {
    return 'बैकअप नहीं हो सका: $message';
  }

  @override
  String get errorTitle => 'कुछ गड़बड़ हो गई';

  @override
  String get errorBody => 'आपके दस्तावेज़ सुरक्षित हैं। फिर कोशिश करें; अगर बार-बार हो, तो ऐप दोबारा शुरू करें।';

  @override
  String get serverWaking => 'सर्वर चालू हो रहा है, इसमें एक मिनट तक लग सकता है…';

  @override
  String deleteFailed(String title) {
    return '“$title” हटाया नहीं जा सका। उसे वापस रख दिया गया है।';
  }

  @override
  String importSkipped(String names) {
    return 'ये फ़ाइलें खुल नहीं सकीं और छोड़ दी गईं: $names';
  }

  @override
  String get importWhyPassword => 'पासवर्ड से सुरक्षित PDF';

  @override
  String get importWhyUnreadable => 'ख़राब या असमर्थित फ़ाइल';

  @override
  String get importNothing => 'जोड़ने के लिए कुछ नहीं। JPG, PNG या PDF फ़ाइलें चुनें।';

  @override
  String get appearance => 'रूप';

  @override
  String get theme => 'थीम';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get themeLight => 'हल्का';

  @override
  String get themeDark => 'गहरा';

  @override
  String get highContrast => 'उच्च कंट्रास्ट';

  @override
  String get highContrastHint => 'गहरे रंग और मोटी रेखाएँ';

  @override
  String get textSize => 'टेक्स्ट का आकार';

  @override
  String get simpleMode => 'सरल मोड';

  @override
  String get simpleModeHint => 'कम विकल्प और आसान शब्द';

  @override
  String get language => 'भाषा';

  @override
  String get languageSystem => 'डिवाइस जैसी';

  @override
  String get scanning => 'स्कैनिंग';

  @override
  String get spokenGuidance => 'बोलकर मार्गदर्शन';

  @override
  String get spokenGuidanceHint => 'स्कैन करते समय “पास लाएँ”, “स्थिर रखें”, “तस्वीर ली गई” बोलता है और कंपन करता है';

  @override
  String get textRecognition => 'टेक्स्ट पहचान';

  @override
  String get autoOcr => 'टेक्स्ट अपने-आप पहचानें';

  @override
  String get autoOcrHint => 'खोजने, टेक्स्ट कॉपी करने और खोजने योग्य PDF बनाने देता है। इसी डिवाइस पर चलता है।';

  @override
  String get ocrLanguage => 'टेक्स्ट की भाषा';

  @override
  String get langEnglish => 'अंग्रेज़ी';

  @override
  String get langHindi => 'हिन्दी';

  @override
  String get backupSync => 'बैकअप लें और डिवाइसों के बीच सिंक करें';

  @override
  String get backupSyncHint => 'वैकल्पिक। खाते के बिना सब कुछ काम करता है।';

  @override
  String signedInAs(String email) {
    return '$email के रूप में साइन इन';
  }

  @override
  String get help => 'मदद';

  @override
  String get showGuide => 'स्वागत गाइड दिखाएँ';

  @override
  String get about => 'जानकारी';

  @override
  String get guide1Title => 'कोई भी पेज स्कैन करें';

  @override
  String get guide1Body => 'कैमरे को दस्तावेज़ पर रखें। डॉकस्कैनर किनारे ढूँढता है और स्थिर रहने पर तस्वीर ले लेता है।';

  @override
  String get guide2Title => 'ठीक करें और सुधारें';

  @override
  String get guide2Body => 'कोने ठीक करें, ब्लैक एंड व्हाइट या मैजिक कलर चुनें, टेक्स्ट या हस्ताक्षर जोड़ें।';

  @override
  String get guide3Title => 'सहेजें और साझा करें, खाते की ज़रूरत नहीं';

  @override
  String get guide3Body => 'PDF या JPG के रूप में निर्यात करें। जब तक आप बैकअप न चुनें, स्कैन इसी डिवाइस पर रहते हैं।';

  @override
  String get getStarted => 'शुरू करें';

  @override
  String guideStep(int current, int total) {
    return 'चरण $current / $total';
  }

  @override
  String get text => 'टेक्स्ट';

  @override
  String get textOnPage => 'इस पेज का टेक्स्ट';

  @override
  String get copyText => 'टेक्स्ट कॉपी करें';

  @override
  String get copied => 'कॉपी हो गया';

  @override
  String get recognisingText => 'टेक्स्ट पहचाना जा रहा है…';

  @override
  String recognisingProgress(int current, int total) {
    return 'टेक्स्ट पहचाना जा रहा है: पेज $current / $total';
  }

  @override
  String get noTextFound => 'इस पेज पर कोई टेक्स्ट नहीं मिला';

  @override
  String get noTextFoundHint => 'साफ़ फ़ोटो आज़माएँ, या नीचे सही भाषा चुनें।';

  @override
  String ocrFailed(String message) {
    return 'टेक्स्ट पहचान विफल: $message। फिर कोशिश करें, या साफ़ फ़ोटो लें।';
  }

  @override
  String get ocrUnavailable => 'इस डिवाइस पर टेक्स्ट पहचान उपलब्ध नहीं है।';

  @override
  String get recogniseAgain => 'फिर से पहचानें';

  @override
  String get readAs => 'टेक्स्ट की भाषा';

  @override
  String get markup => 'मार्कअप';

  @override
  String get markupTitle => 'संपादन / मार्कअप';

  @override
  String get toolSelect => 'चुनें';

  @override
  String get toolText => 'टेक्स्ट जोड़ें';

  @override
  String get toolPen => 'पेन';

  @override
  String get toolHighlighter => 'हाइलाइटर';

  @override
  String get toolEraser => 'रबड़';

  @override
  String get toolSignature => 'हस्ताक्षर';

  @override
  String get toolRect => 'आयत';

  @override
  String get toolArrow => 'तीर';

  @override
  String get toolLine => 'रेखा';

  @override
  String get toolWhiteout => 'व्हाइटआउट';

  @override
  String get markupHint => 'टूल चुनें, फिर पेज पर टैप करें या खींचें।';

  @override
  String get addInMiddle => 'बीच में जोड़ें';

  @override
  String get colour => 'रंग';

  @override
  String get size => 'आकार';

  @override
  String get bold => 'बोल्ड';

  @override
  String get background => 'पृष्ठभूमि';

  @override
  String get bgNone => 'कोई नहीं';

  @override
  String get bgWhite => 'सफ़ेद';

  @override
  String get editText => 'टेक्स्ट बदलें';

  @override
  String get bigger => 'बड़ा';

  @override
  String get smaller => 'छोटा';

  @override
  String get rotateLeft => 'बाएँ घुमाएँ';

  @override
  String get rotateRight => 'दाएँ घुमाएँ';

  @override
  String get moveLeft => 'बाएँ ले जाएँ';

  @override
  String get moveRight => 'दाएँ ले जाएँ';

  @override
  String get moveUp => 'ऊपर ले जाएँ';

  @override
  String get moveDown => 'नीचे ले जाएँ';

  @override
  String get deleteItem => 'आइटम हटाएँ';

  @override
  String get itemsOnPage => 'इस पेज के आइटम';

  @override
  String get noItems => 'अभी कुछ नहीं जोड़ा गया।';

  @override
  String get typeText => 'टेक्स्ट लिखें';

  @override
  String get drawSignature => 'अपना हस्ताक्षर बनाएँ';

  @override
  String get signatureHint => 'उंगली, माउस या पेन से बनाएँ। अगली बार के लिए यह इसी डिवाइस पर सहेजा जाता है।';

  @override
  String get clear => 'साफ़ करें';

  @override
  String get changeSignature => 'हस्ताक्षर बदलें';

  @override
  String get discardChanges => 'बदलाव छोड़ दें?';

  @override
  String get discard => 'छोड़ें';

  @override
  String get keepEditing => 'संपादन जारी रखें';

  @override
  String itemText(String text) {
    return 'टेक्स्ट: $text';
  }

  @override
  String get itemPen => 'पेन रेखा';

  @override
  String get itemHighlighter => 'हाइलाइट';

  @override
  String get itemSignature => 'हस्ताक्षर';

  @override
  String get itemRect => 'आयत';

  @override
  String get itemArrow => 'तीर';

  @override
  String get itemLine => 'रेखा';

  @override
  String get itemWhiteout => 'व्हाइटआउट बॉक्स';

  @override
  String get selected => 'चुना गया';

  @override
  String get scanTitle => 'स्कैन';

  @override
  String get scanDemoTitle => 'स्कैन (डेमो कैमरा)';

  @override
  String get retakeTitle => 'पेज फिर से लें';

  @override
  String get flashOn => 'टॉर्च चालू';

  @override
  String get flashOff => 'टॉर्च बंद';

  @override
  String get switchCamera => 'कैमरा बदलें';

  @override
  String get autoCaptureOn => 'अपने-आप फ़ोटो: चालू';

  @override
  String get autoCaptureOff => 'अपने-आप फ़ोटो: बंद';

  @override
  String get uploadPhoto => 'फ़ोटो अपलोड करें';

  @override
  String get nextSample => 'अगला नमूना पेज';

  @override
  String get useDemoCamera => 'डेमो कैमरा इस्तेमाल करें';

  @override
  String get useDeviceCamera => 'डिवाइस कैमरा इस्तेमाल करें';

  @override
  String get demoCameraNote => 'डेमो कैमरा: आपका कैमरा नहीं, नमूना पेज दिखाता है।';

  @override
  String get diagnostics => 'डिटेक्टर जाँच';

  @override
  String get startingCamera => 'कैमरा शुरू हो रहा है…';

  @override
  String get capturing => 'फ़ोटो ली जा रही है…';

  @override
  String get hintTooDarkFlash => 'बहुत अँधेरा: टॉर्च चालू करें';

  @override
  String get hintTooDark => 'बहुत अँधेरा: रोशनी बढ़ाएँ';

  @override
  String get hintPointCamera => 'कैमरे को दस्तावेज़ पर रखें';

  @override
  String get hintMoveCloser => 'पास लाएँ';

  @override
  String get hintHoldStill => 'स्थिर रखें';

  @override
  String get hintFound => 'दस्तावेज़ मिल गया';

  @override
  String get hintNextPage => 'पेज की फ़ोटो ली गई। अगला पेज दिखाएँ।';

  @override
  String get hintTapShutter => 'दस्तावेज़ मिल गया: फ़ोटो लें दबाएँ';

  @override
  String get capture => 'फ़ोटो लें';

  @override
  String capturedPage(int page) {
    return 'फ़ोटो ली गई, पेज $page';
  }

  @override
  String reviewPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count पेज देखें', one: '1 पेज देखें');
    return '$_temp0';
  }

  @override
  String get savingPages => 'सहेजा जा रहा है…';

  @override
  String get keepScan => 'स्कैन रखें';

  @override
  String get replacePage => 'पेज बदलें';

  @override
  String get retake => 'फिर से लें';

  @override
  String get couldNotSavePage => 'पेज सहेजा नहीं जा सका। कृपया फिर कोशिश करें।';

  @override
  String get camOffTitle => 'कैमरे की अनुमति बंद है';

  @override
  String get camOffWeb =>
      'इस साइट को कैमरे की अनुमति दें (पता बार में कैमरा आइकन), फिर कोशिश करें। चाहें तो फ़ोटो भी अपलोड कर सकते हैं।';

  @override
  String get camOffApp =>
      'सेटिंग्स में डॉकस्कैनर को कैमरे की अनुमति दें, फिर कोशिश करें। चाहें तो फ़ोटो भी अपलोड कर सकते हैं।';

  @override
  String get noCameraTitle => 'कोई कैमरा नहीं मिला';

  @override
  String get noCameraBody =>
      'इस कंप्यूटर पर इस्तेमाल लायक कैमरा नहीं है। पेज की फ़ोटो अपलोड करें, या डेमो कैमरा आज़माएँ।';

  @override
  String get cameraBusyTitle => 'कैमरा व्यस्त है';

  @override
  String get cameraBusyBody => 'कोई और ऐप या ब्राउज़र टैब कैमरा इस्तेमाल कर रहा है। उसे बंद करके फिर कोशिश करें।';

  @override
  String get cameraHttpsTitle => 'यहाँ कैमरा उपलब्ध नहीं है';

  @override
  String get cameraHttpsBody =>
      'ब्राउज़र केवल https:// या localhost पेज पर कैमरा चलने देते हैं। इसके बजाय फ़ोटो अपलोड करें।';

  @override
  String get cameraErrorTitle => 'कैमरा शुरू नहीं हो सका';

  @override
  String get openSettings => 'सेटिंग्स खोलें';

  @override
  String get msgCaptureFailed => 'फ़ोटो नहीं ली जा सकी। कृपया फिर कोशिश करें।';

  @override
  String get msgBadPhotoFile => 'यह फ़ाइल फ़ोटो के रूप में नहीं खुल सकी।';

  @override
  String get msgNoFlashlight => 'इस कैमरे में टॉर्च नहीं है।';

  @override
  String pageOf(int page, int total) {
    return 'पेज $page / $total';
  }

  @override
  String get previousPage => 'पिछला पेज';

  @override
  String get nextPage => 'अगला पेज';

  @override
  String get addPages => 'पेज जोड़ें';

  @override
  String get scanMore => 'और स्कैन करें';

  @override
  String get importPdfOrFiles => 'PDF या फ़ाइलें जोड़ें';

  @override
  String get toolFilters => 'फ़िल्टर';

  @override
  String get toolRotate => 'घुमाएँ';

  @override
  String get toolCrop => 'काटें';

  @override
  String get toolCorners => 'कोने';

  @override
  String get toolPageText => 'टेक्स्ट';

  @override
  String get toolRetake => 'फिर से लें';

  @override
  String get moveEarlier => 'पहले ले जाएँ';

  @override
  String get moveLater => 'बाद में ले जाएँ';

  @override
  String get deletePage => 'पेज हटाएँ';

  @override
  String get deleteDocument => 'दस्तावेज़ हटाएँ';

  @override
  String pageDeleted(int page) {
    return 'पेज $page हटाया गया';
  }

  @override
  String pageMoved(int page) {
    return 'पेज अब $page नंबर पर है';
  }

  @override
  String deleteDocTitle(String title) {
    return '“$title” हटाएँ?';
  }

  @override
  String deleteDocBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'सभी $count पेज हटा दिए जाएँगे।',
      one: 'इसका पेज हटा दिया जाएगा।',
    );
    return '$_temp0';
  }

  @override
  String get recognizingText => 'टेक्स्ट पहचाना जा रहा है…';

  @override
  String recognizingTextOf(int done, int total) {
    return 'टेक्स्ट पहचाना जा रहा है $done / $total…';
  }

  @override
  String somethingWentWrong(String message) {
    return 'कुछ गड़बड़ हो गई: $message';
  }

  @override
  String get noPagesYet => 'अभी कोई पेज नहीं';

  @override
  String get noPagesHint => 'पेज जोड़ने के लिए स्कैन करें या फ़ोटो या PDF जोड़ें।';

  @override
  String pageThumbLabel(int page) {
    return 'पेज $page। क्रम बदलने के लिए खींचें, या पहले/बाद में ले जाएँ बटन दबाएँ।';
  }

  @override
  String get documentNotFound => 'यह दस्तावेज़ खुल नहीं सका।';

  @override
  String get filterOriginal => 'मूल';

  @override
  String get filterGrayscale => 'ग्रेस्केल';

  @override
  String get filterBw => 'ब्लैक एंड व्हाइट';

  @override
  String get filterMagic => 'मैजिक कलर';

  @override
  String get showOriginal => 'मूल से तुलना करें';

  @override
  String get before => 'पहले';

  @override
  String get after => 'बाद में';

  @override
  String get applying => 'लागू हो रहा है…';

  @override
  String applyToAll(String filter) {
    return '$filter सभी पेज पर लगाएँ';
  }

  @override
  String get previewFailed => 'पूर्वावलोकन उपलब्ध नहीं';

  @override
  String exportTitle(String title) {
    return '“$title” निर्यात करें';
  }

  @override
  String get formatPdf => 'PDF';

  @override
  String formatJpg(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: 'JPG ($count फ़ाइलें)', one: 'JPG');
    return '$_temp0';
  }

  @override
  String get pageSize => 'पेज का आकार';

  @override
  String get pageSizeFit => 'पेज के अनुसार';

  @override
  String get pageSizeA4 => 'A4';

  @override
  String get pageSizeLetter => 'US लेटर';

  @override
  String get searchablePdf => 'खोजने योग्य PDF';

  @override
  String get searchablePdfHint => 'टेक्स्ट पहचानें ताकि उसे खोजा और कॉपी किया जा सके';

  @override
  String get download => 'डाउनलोड करें';

  @override
  String get share => 'साझा करें';

  @override
  String get shareOrSave => 'साझा करें या सहेजें';

  @override
  String get creatingPdf => 'PDF बन रहा है…';

  @override
  String get creatingImages => 'तस्वीरें बन रही हैं…';

  @override
  String savedFile(String name) {
    return '$name आपके डाउनलोड फ़ोल्डर में सहेजा गया';
  }

  @override
  String savedImages(int count) {
    return '$count तस्वीरें आपके डाउनलोड फ़ोल्डर में सहेजी गईं';
  }

  @override
  String exportFailed(String message) {
    return 'निर्यात नहीं हो सका: $message';
  }

  @override
  String get exportHelpWeb =>
      'डाउनलोड फ़ाइल को आपके डाउनलोड फ़ोल्डर में सहेजता है। साझा करें उन ब्राउज़रों में शेयर मेन्यू खोलता है जो इसे सपोर्ट करते हैं (जैसे फ़ोन पर Safari और Chrome); बाक़ी जगह फ़ाइल डाउनलोड होती है।';

  @override
  String get exportHelpIos => 'फ़ाइल सहेजने के लिए “साझा करें या सहेजें” दबाएँ, फिर “Save to Files” चुनें।';

  @override
  String get exportHelpAndroid =>
      'फ़ाइल सहेजने के लिए “साझा करें या सहेजें” दबाएँ, फिर Files, Drive या कोई और ऐप चुनें।';

  @override
  String get markupBurnedIn => 'मार्कअप निर्यात किए गए पेज का हिस्सा बन जाएगा।';

  @override
  String get adjustCorners => 'कोने ठीक करें';

  @override
  String get noEdgesFound => 'पेज के किनारे नहीं मिले। कोने ठीक करें या पूरी फ़ोटो रखें।';

  @override
  String get cornersHint => 'कोनों या किनारों को पेज पर खींचें। कीबोर्ड: Tab से कोना चुनें, तीर कुंजियों से खिसकाएँ।';

  @override
  String get cornersCrossed => 'कोने एक-दूसरे को काट रहे हैं। उन्हें वापस पेज के चारों ओर खींचें।';

  @override
  String get resetCorners => 'कोने पहले जैसे करें';

  @override
  String get useFullPhoto => 'पूरी फ़ोटो रखें';

  @override
  String get rotate => 'घुमाएँ';

  @override
  String get confirm => 'पुष्टि करें';

  @override
  String get couldNotRotate => 'फ़ोटो घुमाई नहीं जा सकी।';

  @override
  String get cornerTopLeft => 'ऊपर-बाएँ';

  @override
  String get cornerTopRight => 'ऊपर-दाएँ';

  @override
  String get cornerBottomRight => 'नीचे-दाएँ';

  @override
  String get cornerBottomLeft => 'नीचे-बाएँ';

  @override
  String cornersSemantics(String corner) {
    return 'पेज के कोने। चुना गया: $corner कोना। खिसकाने वाले विकल्प इस्तेमाल करें, या कोनों को खींचें।';
  }

  @override
  String get nextCorner => 'अगला कोना';

  @override
  String get moveCornerLeft => 'कोना बाएँ ले जाएँ';

  @override
  String get moveCornerRight => 'कोना दाएँ ले जाएँ';

  @override
  String get moveCornerUp => 'कोना ऊपर ले जाएँ';

  @override
  String get moveCornerDown => 'कोना नीचे ले जाएँ';

  @override
  String get cropTitle => 'काटें';

  @override
  String get reset => 'पहले जैसा करें';

  @override
  String get apply => 'लागू करें';

  @override
  String get cropHint => 'बॉक्स के किनारे या कोने खींचें। उसे खिसकाने के लिए अंदर से खींचें।';

  @override
  String get backUpYourScans => 'अपने स्कैन का बैकअप और सिंक करें';

  @override
  String get backUpIntro =>
      'वैकल्पिक। खाते के बिना सब कुछ इसी डिवाइस पर रहता है और हर सुविधा काम करती है। बैकअप और दूसरे डिवाइस पर इस्तेमाल के लिए साइन इन करें।';

  @override
  String get server => 'सर्वर';

  @override
  String get serverHint => 'http://192.168.1.20:8000 जैसा पता लिखें';

  @override
  String get testConnection => 'कनेक्शन जाँचें';

  @override
  String get serverReachable => 'सर्वर से जुड़ गया।';

  @override
  String get serverUnreachable => 'सर्वर तक नहीं पहुँच पा रहे। पता और बैकएंड चल रहा है या नहीं, जाँचें।';

  @override
  String get signIn => 'साइन इन करें';

  @override
  String get createAccount => 'खाता बनाएँ';

  @override
  String get email => 'ईमेल';

  @override
  String get enterEmail => 'अपना ईमेल लिखें';

  @override
  String get password => 'पासवर्ड';

  @override
  String get passwordRule => 'कम से कम 8 अक्षर';

  @override
  String get showPassword => 'दिखाएँ';

  @override
  String get hidePassword => 'छिपाएँ';

  @override
  String get showPasswordLabel => 'पासवर्ड दिखाएँ';

  @override
  String get hidePasswordLabel => 'पासवर्ड छिपाएँ';

  @override
  String errOffline(String url) {
    return '$url पर सर्वर तक नहीं पहुँच पा रहे। पता और बैकएंड चल रहा है या नहीं, जाँचें।';
  }

  @override
  String get errWrongPassword => 'ईमेल या पासवर्ड ग़लत है।';

  @override
  String get errAccountExists => 'इस ईमेल से खाता पहले से है। साइन इन करें।';

  @override
  String get errInvalidInput => 'ईमेल पता जाँचें; पासवर्ड में कम से कम 8 अक्षर चाहिए।';

  @override
  String get syncNow => 'अभी सिंक करें';

  @override
  String get processOnServer => 'फ़ोटो सर्वर पर प्रोसेस करें';

  @override
  String get processOnServerHint =>
      'धीमे डिवाइस के लिए: पेज पहचान, सीधा करना और फ़िल्टर सर्वर पर चलते हैं। कैमरा प्रीव्यू इसी डिवाइस पर चलता है।';

  @override
  String get signOut => 'साइन आउट करें';

  @override
  String get signOutTitle => 'साइन आउट करें?';

  @override
  String get signOutBody =>
      'आपके स्कैन इसी डिवाइस पर रहेंगे। साइन आउट रहते हुए किए बदलाव दोबारा साइन इन करने पर सिंक होंगे।';

  @override
  String get signedInNote => 'स्कैन इसी डिवाइस पर रहते हैं और आपके खाते में बैकअप होते हैं। ऑफ़लाइन भी काम करते हैं।';

  @override
  String get syncNever => 'अभी सिंक नहीं हुआ';

  @override
  String get syncJustNow => 'अभी-अभी सिंक हुआ';

  @override
  String syncMinutesAgo(int minutes) {
    return '$minutes मिनट पहले सिंक हुआ';
  }

  @override
  String syncHoursAgo(int hours) {
    return '$hours घंटे पहले सिंक हुआ';
  }

  @override
  String get syncNotSignedIn => 'साइन इन नहीं है';

  @override
  String get syncSyncing => 'सिंक हो रहा है…';

  @override
  String get syncOffline => 'ऑफ़लाइन। बदलाव इस डिवाइस पर सहेजे गए हैं और बाद में सिंक होंगे।';

  @override
  String syncProblem(String message) {
    return 'सिंक में समस्या: $message';
  }

  @override
  String get uploadExistingTitle => 'अपने स्कैन अपलोड करें?';

  @override
  String uploadExistingBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'इस डिवाइस पर $count दस्तावेज़ हैं। क्या इन्हें अपने खाते में अपलोड करें ताकि बैकअप रहे और दूसरे डिवाइस पर भी मिलें?',
      one: 'इस डिवाइस पर 1 दस्तावेज़ है। क्या इसे अपने खाते में अपलोड करें ताकि बैकअप रहे और दूसरे डिवाइस पर भी मिले?',
    );
    return '$_temp0';
  }

  @override
  String get uploadNow => 'अभी अपलोड करें';

  @override
  String get notNow => 'अभी नहीं';

  @override
  String get uploadLocalDocs => 'इस डिवाइस के दस्तावेज़ अपलोड करें';

  @override
  String conflictsResolved(int count, String titles) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दस्तावेज़ दो डिवाइस पर बदले गए; नए बदलाव रखे गए: $titles',
      one: '1 दस्तावेज़ दो डिवाइस पर बदला गया; नया बदलाव रखा गया: $titles',
    );
    return '$_temp0';
  }
}
