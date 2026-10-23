// App theme: light / dark / high contrast, large touch targets, visible focus.
import 'package:flutter/material.dart';

const _seed = Color(0xFF1F5FAF); // restrained blue

/// Builds the theme. [highContrast] maxes out the colour contrast and thickens
/// outlines; [reduceMotion] removes page transition animations.
ThemeData buildTheme({required Brightness brightness, bool highContrast = false, bool reduceMotion = false}) {
  var scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness, contrastLevel: highContrast ? 1.0 : 0.0);
  if (highContrast) {
    final dark = brightness == Brightness.dark;
    scheme = scheme.copyWith(
      surface: dark ? Colors.black : Colors.white,
      onSurface: dark ? Colors.white : Colors.black,
      onSurfaceVariant: dark ? Colors.white : Colors.black,
      outline: dark ? Colors.white : Colors.black,
      outlineVariant: dark ? Colors.white70 : Colors.black87,
    );
  }
  final focusRing = highContrast
      ? (brightness == Brightness.dark ? Colors.yellowAccent : Colors.black)
      : scheme.tertiary;
  final borderWidth = highContrast ? 2.0 : 1.0;

  // Every button: at least 48x48, a thick outline when focused by keyboard.
  WidgetStateProperty<BorderSide?> focusSide(BorderSide? normal) => WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused) ? BorderSide(color: focusRing, width: 3) : normal,
  );
  const minSize = Size(48, 48);
  const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    // Bundled fonts: no runtime font downloads (offline web), Hindi included.
    fontFamily: 'NotoSans',
    fontFamilyFallback: const ['NotoSansDevanagari'],
  );
  return base.copyWith(
    materialTapTargetSize: MaterialTapTargetSize.padded,
    scaffoldBackgroundColor: scheme.surface,
    focusColor: focusRing.withValues(alpha: 0.24),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant, width: borderWidth),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        padding: const WidgetStatePropertyAll(padding),
        side: focusSide(null),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        padding: const WidgetStatePropertyAll(padding),
        side: focusSide(null),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        padding: const WidgetStatePropertyAll(padding),
        side: focusSide(BorderSide(color: scheme.outline, width: borderWidth)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        padding: const WidgetStatePropertyAll(padding),
        side: focusSide(null),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(minSize), side: focusSide(null)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minSize),
        side: focusSide(BorderSide(color: scheme.outline, width: borderWidth)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline, width: borderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: focusRing, width: 3),
      ),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: borderWidth),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: reduceMotion
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoTransition(),
              TargetPlatform.iOS: _NoTransition(),
              TargetPlatform.macOS: _NoTransition(),
              TargetPlatform.windows: _NoTransition(),
              TargetPlatform.linux: _NoTransition(),
              TargetPlatform.fuchsia: _NoTransition(),
            },
          )
        : base.pageTransitionsTheme,
  );
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
