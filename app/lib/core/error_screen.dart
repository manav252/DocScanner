// "Something went wrong" instead of Flutter's grey error box, with Retry.
// Retry rebuilds the app at the home screen; documents are on disk, so nothing is lost.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';

/// Bumped by Retry: the app rebuilds its screens from scratch.
final appRetry = ValueNotifier<int>(0);

/// Navigator of the app (Retry returns to the first screen).
final appNavigatorKey = GlobalKey<NavigatorState>();

void retryApp() {
  appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  appRetry.value++;
}

/// Installs the error screen and logs errors with context (once each).
void installErrorHandling() {
  ErrorWidget.builder = (details) => SomethingWentWrong(details: details);
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    defaultOnError?.call(details); // keeps the normal report (console / test failures)
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // An async error nobody awaited: report it, keep the app running.
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'DocScanner'));
    return true;
  };
}

class SomethingWentWrong extends StatelessWidget {
  const SomethingWentWrong({super.key, this.details});
  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    // May be shown above MaterialApp/Localizations: fall back to English.
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final title = l?.errorTitle ?? 'Something went wrong';
    final body = l?.errorBody ?? 'Your documents are safe. Try again; if it keeps happening, restart the app.';
    final retry = l?.tryAgain ?? 'Try again';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFFF7F8FB),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 56, color: Color(0xFFB3261E)),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF15171C)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Color(0xFF464B55)),
                    ),
                    if (kDebugMode && details != null) ...[
                      const SizedBox(height: 12),
                      Text(details!.exceptionAsString(), style: const TextStyle(fontSize: 12, color: Color(0xFF464B55))),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const ValueKey('error-retry'),
                      onPressed: retryApp,
                      icon: const Icon(Icons.refresh),
                      label: Text(retry),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
