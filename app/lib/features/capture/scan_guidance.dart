// Spoken and haptic scan guidance ("Move closer", "Hold still",
// "Captured, page 2"). Speech follows the "Spoken guidance" setting; captures
// are always announced to screen readers.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/app_settings.dart';
import '../../core/l10n.dart';
import 'capture_page.dart' show ScanHint;

/// Text-to-speech (system voices: Android/iOS TTS, the browser's speechSynthesis).
abstract interface class Speaker {
  Future<void> speak(String text, {required String languageTag});
  Future<void> stop();
}

class TtsSpeaker implements Speaker {
  FlutterTts? _tts;
  String? _lang;

  @override
  Future<void> speak(String text, {required String languageTag}) async {
    try {
      final tts = _tts ??= FlutterTts();
      if (_lang != languageTag) {
        await tts.setLanguage(languageTag);
        _lang = languageTag;
      }
      await tts.stop();
      await tts.speak(text);
    } catch (_) {
      // No voice for this language / speech unavailable: the hint stays on screen.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

final speakerProvider = Provider<Speaker>((_) => TtsSpeaker());

/// Lives while the scanner is open (it watches this); closing it stops speech.
final scanGuidanceProvider = Provider.autoDispose<ScanGuidance>((ref) {
  final g = ScanGuidance(ref, ref.watch(speakerProvider));
  ref.onDispose(g.dispose);
  return g;
});

class ScanGuidance {
  ScanGuidance(this._ref, this._speaker);
  final Ref _ref;
  final Speaker _speaker;

  /// A hint must stay on screen this long before it is spoken (detection flickers).
  static const settle = Duration(milliseconds: 700);

  /// The same hint is not repeated sooner than this.
  static const repeatAfter = Duration(seconds: 6);

  /// Hints worth saying out loud (the others are transient or obvious).
  static const spoken = {
    ScanHint.moveCloser,
    ScanHint.holdStill,
    ScanHint.tooDark,
    ScanHint.tooDarkFlash,
    ScanHint.pointCamera,
  };

  Timer? _pending;
  ScanHint? _lastSpoken;
  final _clock = Stopwatch()..start();
  Duration _lastSpokenAt = -repeatAfter;

  bool get _enabled => _ref.read(appSettingsProvider).spokenGuidance;

  void hint(BuildContext context, ScanHint hint) {
    _pending?.cancel();
    if (hint == ScanHint.holdStill) unawaited(HapticFeedback.selectionClick());
    if (!_enabled || !spoken.contains(hint)) return;
    final text = hint.text(context.l10n);
    final lang = _languageTag(context);
    _pending = Timer(settle, () {
      final now = _clock.elapsed;
      if (hint == _lastSpoken && now - _lastSpokenAt < repeatAfter) return;
      _lastSpoken = hint;
      _lastSpokenAt = now;
      _speaker.speak(text, languageTag: lang);
    });
  }

  /// A page was kept: haptic, screen-reader announcement and (if on) speech.
  void captured(BuildContext context, int page) {
    _pending?.cancel();
    unawaited(HapticFeedback.mediumImpact());
    final text = context.l10n.capturedPage(page);
    SemanticsService.sendAnnouncement(View.of(context), text, Directionality.of(context));
    if (_enabled) {
      _lastSpoken = null;
      _lastSpokenAt = _clock.elapsed;
      _speaker.speak(text, languageTag: _languageTag(context));
    }
  }

  static String _languageTag(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'hi' ? 'hi-IN' : 'en-US';

  void dispose() {
    _pending?.cancel();
    _speaker.stop();
  }
}
