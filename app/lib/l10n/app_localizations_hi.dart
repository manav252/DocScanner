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
  String get appPurpose =>
      'काग़ज़ को साफ़ PDF में बदलें। ऑफ़लाइन चलता है, खाते की ज़रूरत नहीं।';

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
  String get noScansHint =>
      'कैमरे से पेज स्कैन करने के लिए “दस्तावेज़ स्कैन करें” दबाएँ, या फ़ोटो या PDF जोड़ें।';

  @override
  String get howItWorksTitle => 'यह कैसे काम करता है';

  @override
  String get howItWorksStep1 =>
      'कैमरे को पेज पर रखें। स्थिर रहने पर तस्वीर अपने-आप ली जाती है।';

  @override
  String get howItWorksStep2 =>
      'कोनों की जाँच करें, फिर ब्लैक एंड व्हाइट जैसा रूप चुनें।';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पेज',
      one: '1 पेज',
    );
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पेज जोड़े',
      one: '1 पेज जोड़ा',
    );
    return '$_temp0 · $name';
  }

  @override
  String importFailed(String message) {
    return 'जोड़ नहीं सके: $message';
  }

  @override
  String get importNothing =>
      'जोड़ने के लिए कुछ नहीं। JPG, PNG या PDF फ़ाइलें चुनें।';

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
  String get spokenGuidanceHint =>
      'स्कैन करते समय “पास लाएँ”, “स्थिर रखें”, “तस्वीर ली गई” बोलता है और कंपन करता है';

  @override
  String get textRecognition => 'टेक्स्ट पहचान';

  @override
  String get autoOcr => 'टेक्स्ट अपने-आप पहचानें';

  @override
  String get autoOcrHint =>
      'खोजने, टेक्स्ट कॉपी करने और खोजने योग्य PDF बनाने देता है। इसी डिवाइस पर चलता है।';

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
  String get guide1Body =>
      'कैमरे को दस्तावेज़ पर रखें। डॉकस्कैनर किनारे ढूँढता है और स्थिर रहने पर तस्वीर ले लेता है।';

  @override
  String get guide2Title => 'ठीक करें और सुधारें';

  @override
  String get guide2Body =>
      'कोने ठीक करें, ब्लैक एंड व्हाइट या मैजिक कलर चुनें, टेक्स्ट या हस्ताक्षर जोड़ें।';

  @override
  String get guide3Title => 'सहेजें और साझा करें, खाते की ज़रूरत नहीं';

  @override
  String get guide3Body =>
      'PDF या JPG के रूप में निर्यात करें। जब तक आप बैकअप न चुनें, स्कैन इसी डिवाइस पर रहते हैं।';

  @override
  String get getStarted => 'शुरू करें';

  @override
  String guideStep(int current, int total) {
    return 'चरण $current / $total';
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
