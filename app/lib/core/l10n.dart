import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  /// UI strings in the current language (English / Hindi).
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Short local date, e.g. 22 Oct 2026, in the app's language.
String shortDate(BuildContext context, DateTime d) {
  final loc = Localizations.localeOf(context).languageCode;
  const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const hi = ['जन', 'फ़र', 'मार्च', 'अप्रै', 'मई', 'जून', 'जुला', 'अग', 'सित', 'अक्टू', 'नव', 'दिस'];
  return '${d.day} ${(loc == 'hi' ? hi : en)[d.month - 1]} ${d.year}';
}
