import 'package:docscanner/core/l10n.dart';
import 'package:docscanner/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The app's MaterialApp setup (theme, localisations) around [home].
Widget testApp(Widget home, {List<Override> overrides = const [], Locale locale = const Locale('en'), bool highContrast = false}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light, highContrast: highContrast),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );
