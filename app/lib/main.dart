import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_settings.dart';
import 'core/l10n.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'data/storage/key_value_store.dart';
import 'data/sync/sync_controller.dart';
import 'features/home/home_page.dart';
import 'features/onboarding/onboarding_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: build the accessibility tree from the start, so screen readers and
  // keyboard users don't first have to find Flutter's hidden "Enable accessibility" button.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final store = await KeyValueStore.open();
  final (settings, session) = await loadSettingsAndSession(store);
  // `?demo=1` on the web (or --dart-define=DEMO_CAMERA=true) starts with the demo camera.
  final demo = const bool.fromEnvironment('DEMO_CAMERA') || (kIsWeb && Uri.base.queryParameters['demo'] == '1');
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        appSettingsProvider.overrideWith(() => AppSettingsNotifier(settings)),
        sessionProvider.overrideWith(() => SessionNotifier(session)),
        if (demo) cameraModeProvider.overrideWith(() => CameraModeNotifier(CameraMode.demo)),
      ],
      child: const DocScannerApp(),
    ),
  );
}

class DocScannerApp extends ConsumerWidget {
  const DocScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Background sync runs only when signed in; everything else works as a guest.
    ref.watch(syncControllerProvider);
    final s = ref.watch(appSettingsProvider);
    final reduceMotion = MediaQueryData.fromView(View.of(context)).disableAnimations;
    ThemeData theme(Brightness b, {bool hc = false}) =>
        buildTheme(brightness: b, highContrast: s.highContrast || hc, reduceMotion: reduceMotion);
    return MaterialApp(
      title: 'DocScanner',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      highContrastTheme: theme(Brightness.light, hc: true),
      highContrastDarkTheme: theme(Brightness.dark, hc: true),
      themeMode: switch (s.theme) {
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.system => ThemeMode.system,
      },
      locale: s.localeCode == null ? null : Locale(s.localeCode!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // The app's text size setting multiplies the system one.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: _MultipliedScaler(mq.textScaler, s.textScale)),
          child: child!,
        );
      },
      home: s.onboardingDone ? const HomePage() : const OnboardingPage(),
    );
  }
}

class _MultipliedScaler extends TextScaler {
  const _MultipliedScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.scale(14) / 14 * factor;

  @override
  bool operator ==(Object other) => other is _MultipliedScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
